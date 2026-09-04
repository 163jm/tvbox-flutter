import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:tvbox_core/tvbox_core.dart';

import 'curl_bindings.dart';

/// CURLOPT 常量，取自 curl.h。
abstract class CurlOpt {
  static const writeData = 10001;
  static const url = 10002;
  static const postfields = 10015;
  static const userAgent = 10018;
  static const httpheader = 10023;
  static const headerData = 10029;
  static const followLocation = 52;
  static const nobody = 44;
  static const post = 47;
  static const customRequest = 10036;
  static const postfieldsSize = 60; // CURLOPTTYPE_LONG + 60
  static const writeFunction = 20011;
  static const headerFunction = 20079;
  static const timeoutMs = 157;
  static const connectTimeoutMs = 156;
  static const acceptEncoding = 10102;
}

/// write / header 回调共用的 native 签名。
///
/// Dart 侧实现函数的对应参数一律用 int（UintPtr 的 Dart 表示）。
typedef WriteCallbackNative = UintPtr Function(
  Pointer<Uint8> data,
  UintPtr size,
  UintPtr nmemb,
  Pointer<Void> userdata,
);

/// [SyncHttpClient] 的 libcurl 实现。
///
/// 同步语义直接来自 `curl_easy_perform` 的阻塞特性，
/// 与 JS 爬虫的 `req(url)` 完全对齐。
///
/// **生命周期约束**：回调表按 isolate 注册，每个 isolate 需要独立的
/// 实例——这与 core 的约定一致：`PlatformBridge.createSyncHttpClient()`
/// 在 worker isolate 内调用，实例销毁时调用 [dispose]。
class CurlSyncHttpClient implements SyncHttpClient {
  CurlSyncHttpClient({String? libPath})
      : _curl = CurlLib.open(path: libPath) {
    _onWrite = NativeCallable<WriteCallbackNative>.isolateLocal(
      _writeImpl,
      exceptionalReturn: 0,
    );
    _onHeader = NativeCallable<WriteCallbackNative>.isolateLocal(
      _headerImpl,
      exceptionalReturn: 0,
    );
  }

  final CurlLib _curl;
  NativeCallable<WriteCallbackNative>? _onWrite;
  NativeCallable<WriteCallbackNative>? _onHeader;

  /// 进行中请求的缓冲区，回调按 id 取回。
  final _active = <int, CurlResponseBuffer>{};
  int _nextRequestId = 0;

  int _writeImpl(
    Pointer<Uint8> data,
    int size,
    int nmemb,
    Pointer<Void> userdata,
  ) {
    final len = size * nmemb;
    final buf = _active[userdata.cast<Int64>().value];
    if (buf != null && len > 0) {
      buf.body.add(data.asTypedList(len));
    }
    return len;
  }

  int _headerImpl(
    Pointer<Uint8> data,
    int size,
    int nmemb,
    Pointer<Void> userdata,
  ) {
    final len = size * nmemb;
    final buf = _active[userdata.cast<Int64>().value];
    if (buf != null && len > 0) {
      buf.headerBytes.addAll(data.asTypedList(len));
    }
    return len;
  }

  @override
  SyncHttpResponse execute(SyncHttpRequest request) {
    final easy = _curl.easyInit();
    final id = ++_nextRequestId;
    final buffer = CurlResponseBuffer();
    _active[id] = buffer;

    final idPtr = calloc<Int64>()..value = id;
    CurlHeaderList? headerList;
    Pointer<Uint8>? postBodyPtr;
    ({List<int> body, String? contentType})? prepared;

    try {
      _curl.setoptString(easy, CurlOpt.url, request.url);
      _curl.setoptPtr(
          easy, CurlOpt.writeFunction, _onWrite!.nativeFunction.cast());
      _curl.setoptPtr(
          easy, CurlOpt.headerFunction, _onHeader!.nativeFunction.cast());
      _curl.setoptPtr(easy, CurlOpt.writeData, idPtr.cast());
      _curl.setoptPtr(easy, CurlOpt.headerData, idPtr.cast());
      _curl.setoptLong(easy, CurlOpt.timeoutMs, request.timeoutMs);
      _curl.setoptLong(easy, CurlOpt.connectTimeoutMs, request.connectTimeoutMs);
      _curl.setoptLong(
        easy,
        CurlOpt.followLocation,
        request.followRedirects ? 1 : 0,
      );
      // 空串 = 启用全部内建压缩（gzip/deflate/br 视构建而定）
      _curl.setoptString(easy, CurlOpt.acceptEncoding, '');

      final method = request.method.toLowerCase();
      final hasBody = request.body != null || request.data != null;

      if (method == 'header') {
        _curl.setoptLong(easy, CurlOpt.nobody, 1);
      } else if (hasBody) {
        prepared = _buildBody(request);
        postBodyPtr = _copyToNative(prepared.body);
        _curl.setoptLong(easy, CurlOpt.post, 1);
        _curl.setoptPtr(easy, CurlOpt.postfields, postBodyPtr.cast());
        _curl.setoptLong(easy, CurlOpt.postfieldsSize, prepared.body.length);
        if (method != 'post') {
          // PUT / DELETE 等自定义方法复用 POSTFIELDS
          _curl.setoptString(easy, CurlOpt.customRequest, request.method);
        }
      } else if (method != 'get') {
        _curl.setoptString(easy, CurlOpt.customRequest, request.method);
      }

      headerList = CurlHeaderList(
        _curl,
        _buildHeaderLines(request, hasBody, prepared?.contentType),
      );
      if (headerList.raw != null) {
        _curl.setoptPtr(easy, CurlOpt.httpheader, headerList.raw!);
      }

      final code = _curl.perform(easy);
      if (code != 0) {
        // 对齐原版 Connect.error：网络失败返回空响应，不抛异常
        return SyncHttpResponse(content: _emptyContent(request.buffer));
      }
      return _buildResponse(request, buffer);
    } finally {
      _active.remove(id);
      calloc.free(idPtr);
      headerList?.dispose();
      if (postBodyPtr != null) calloc.free(postBodyPtr);
      _curl.easyCleanup(easy);
    }
  }

  @override
  void cancelByTag(Object tag) {
    // curl_easy_perform 阻塞当前线程，安全取消需要 curl_multi 接口
    // （在另一个线程驱动）。当前所有请求都在 worker isolate 内串行，
    // 取消等价于"不再发起新请求"；真正可中断的取消是 P1.5 的活。
  }

  // ---------- 请求组装 ----------

  List<String> _buildHeaderLines(
    SyncHttpRequest request,
    bool hasBody,
    String? impliedContentType,
  ) {
    final lines = <String>[];
    request.headers.forEach((k, v) => lines.add('$k: $v'));

    if (hasBody && impliedContentType != null) {
      final hasContentType = request.headers.keys
          .any((k) => k.toLowerCase() == 'content-type');
      if (!hasContentType) lines.add('Content-Type: $impliedContentType');
    }
    return lines;
  }

  ({List<int> body, String? contentType}) _buildBody(SyncHttpRequest request) {
    final data = request.data;
    final body = request.body;
    if (body != null) {
      return (body: utf8.encode(body), contentType: null);
    }
    if (data is Map) {
      switch (request.postType) {
        case HttpPostType.json:
          return (body: utf8.encode(jsonEncode(data)),
              contentType: 'application/json');
        case HttpPostType.form:
          return (
            body: utf8.encode(
              data.entries
                  .map((e) =>
                      '${Uri.encodeQueryComponent(e.key.toString())}'
                      '='
                      '${Uri.encodeQueryComponent(e.value.toString())}')
                  .join('&'),
            ),
            contentType: 'application/x-www-form-urlencoded',
          );
        case HttpPostType.formData:
          final boundary =
              '----tvbox-boundary-${DateTime.now().microsecondsSinceEpoch}';
          final sb = StringBuffer();
          data.forEach((k, v) {
            sb
              ..write('--$boundary\r\n')
              ..write('Content-Disposition: form-data; name="$k"\r\n\r\n')
              ..write(v)
              ..write('\r\n');
          });
          sb.write('--$boundary--\r\n');
          return (
            body: utf8.encode(sb.toString()),
            contentType: 'multipart/form-data; boundary=$boundary',
          );
      }
    }
    return (body: utf8.encode(data?.toString() ?? ''), contentType: null);
  }

  // ---------- 响应组装 ----------

  SyncHttpResponse _buildResponse(
    SyncHttpRequest request,
    CurlResponseBuffer buffer,
  ) {
    final bytes = buffer.body.takeBytes();
    final headers = _parseHeaders(buffer.headerBytes);
    return SyncHttpResponse(
      headers: headers,
      content: switch (request.buffer) {
        HttpBufferMode.text => _decodeText(bytes, headers, request),
        HttpBufferMode.bytes => bytes,
        HttpBufferMode.base64 => base64Encode(bytes),
      },
    );
  }

  /// 从原始响应头解析 `key: value`，跳过状态行与空行。
  Map<String, List<String>> _parseHeaders(List<int> raw) {
    final result = <String, List<String>>{};
    final text = utf8.decode(raw, allowMalformed: true);
    for (final line in text.split('\n')) {
      final l = line.trimRight();
      if (l.isEmpty || l.startsWith('HTTP/')) continue;
      final idx = l.indexOf(':');
      if (idx <= 0) continue;
      final key = l.substring(0, idx).trim();
      final value = l.substring(idx + 1).trim();
      (result[key] ??= []).add(value);
    }
    return result;
  }

  String _decodeText(
    List<int> bytes,
    Map<String, List<String>> headers,
    SyncHttpRequest request,
  ) {
    var charset = request.charset;
    if (charset == null) {
      final contentType = _firstHeader(headers, 'Content-Type');
      charset = _charsetFromContentType(contentType);
    }
    switch (charset.toLowerCase()) {
      case 'utf-8':
      case 'utf8':
        return utf8.decode(bytes, allowMalformed: true);
      case 'latin1':
      case 'iso-8859-1':
        return latin1.decode(bytes, allowInvalid: true);
      default:
        // gbk / gb2312 等需要字表（P1.5：接 assets/js/lib/gbk.js 同源字表）；
        // 先按 utf8 宽松解码，保证不抛异常。
        return utf8.decode(bytes, allowMalformed: true);
    }
  }

  static String? _firstHeader(Map<String, List<String>> headers, String name) {
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == name.toLowerCase() &&
          entry.value.isNotEmpty) {
        return entry.value.first;
      }
    }
    return null;
  }

  static String _charsetFromContentType(String? contentType) {
    if (contentType == null) return 'utf-8';
    for (final part in contentType.split(';')) {
      final p = part.trim().toLowerCase();
      if (p.startsWith('charset=')) {
        return p.substring('charset='.length).replaceAll('"', '').trim();
      }
    }
    return 'utf-8';
  }

  Object _emptyContent(HttpBufferMode mode) => switch (mode) {
        HttpBufferMode.text => '',
        HttpBufferMode.bytes => <int>[],
        HttpBufferMode.base64 => '',
      };

  Pointer<Uint8> _copyToNative(List<int> bytes) {
    final ptr = calloc<Uint8>(bytes.length);
    ptr.asTypedList(bytes.length).setAll(0, bytes);
    return ptr;
  }

  /// 释放回调表。实例销毁时必须调用（回调持有 isolate 上下文）。
  void dispose() {
    _onWrite?.close();
    _onHeader?.close();
    _onWrite = null;
    _onHeader = null;
  }
}
