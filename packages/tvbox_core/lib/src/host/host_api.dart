import 'dart:async';

import '../js/js_engine.dart';
import 'crypto.dart';
import 'html_rules.dart';
import 'storage.dart';
import 'sync_http.dart';
import 'text_converter.dart';

/// JS 宿主全局函数集合。
///
/// 这是**整个移植工程里最不能出错的一层**：现成的 JS 爬虫源码直接依赖
/// 这些全局函数名、参数顺序与返回结构。名字写错、参数顺序颠倒、默认值
/// 不一致，表现都是"某个站点抓不到数据"，排查成本极高。
///
/// 下面每个函数都标注了它在参考实现中的出处，改之前请先对照：
/// - `app/src/main/java/com/github/tvbox/osc/util/js/Global.java`
/// - `app/src/main/java/com/github/tvbox/osc/util/js/local.java`
/// - `app/src/main/assets/js/lib/net.js`
class JsHostApi {
  JsHostApi({
    required this.engine,
    required this.siteKey,
    required this.http,
    required this.html,
    required this.storage,
    required this.crypto,
    required this.textConverter,
    required this.proxyBaseUrl,
    this.localProxyBaseUrl,
    this.logger,
  });

  final JsEngine engine;

  /// 当前站点 key，用于 `local` 的命名空间与代理 URL 拼装。
  final String siteKey;

  final SyncHttpClient http;
  final HtmlRules html;
  final KeyValueStore storage;
  final JsCrypto crypto;
  final TextConverter textConverter;

  /// 本地代理基址，`getProxy` 与 `js2Proxy` 在此基础上拼装。
  ///
  /// 需要自带结尾斜杠，例如 `http://127.0.0.1:9978/`。
  final String proxyBaseUrl;

  /// 本地回环地址版本。`js2Proxy` 里 `dynamic` 为假时使用。
  /// 不提供则回退到 [proxyBaseUrl]。
  final String? localProxyBaseUrl;

  final void Function(String message)? logger;

  /// 把全部宿主函数注册到引擎的全局对象上。
  ///
  /// 必须在 evaluate 爬虫源码**之前**调用。
  void install() {
    // Global.java —— 解析类
    engine.registerFunction('joinUrl', _joinUrl);
    engine.registerFunction('pd', _pd);
    engine.registerFunction('pdfh', _pdfh);
    engine.registerFunction('pdfa', _pdfa);
    engine.registerFunction('pdfla', _pdfla);

    // Global.java —— 文本类
    engine.registerFunction('s2t', _s2t);
    engine.registerFunction('t2s', _t2s);

    // Global.java —— 加解密
    engine.registerFunction('aesX', _aesX);
    engine.registerFunction('rsaX', _rsaX);
    engine.registerFunction('rsaEncrypt', _rsaEncrypt);
    engine.registerFunction('rsaDecrypt', _rsaDecrypt);

    // Global.java —— 网络
    engine.registerFunction('_http', _http);

    // Global.java —— 代理
    engine.registerFunction('getProxy', _getProxy);
    engine.registerFunction('js2Proxy', _js2Proxy);

    // Global.java —— 定时器
    engine.registerFunction('setTimeout', _setTimeout);

    // local.java —— 存储
    engine.setGlobalProperty('local', <String, Object?>{
      'get': engine.registeredFunctionFor(_localGet),
      'set': engine.registeredFunctionFor(_localSet),
      'delete': engine.registeredFunctionFor(_localDelete),
    });
  }

  // ---------- 解析 ----------

  Object? _joinUrl(List<Object?> args) =>
      html.joinUrl(_str(args, 0), _str(args, 1));

  Object? _pdfh(List<Object?> args) =>
      html.pdfh(_str(args, 0), _str(args, 1));

  Object? _pd(List<Object?> args) =>
      html.pd(_str(args, 0), _str(args, 1), _str(args, 2));

  Object? _pdfa(List<Object?> args) =>
      html.pdfa(_str(args, 0), _str(args, 1));

  Object? _pdfla(List<Object?> args) => html.pdfla(
        _str(args, 0),
        _str(args, 1),
        _str(args, 2),
        _str(args, 3),
        _str(args, 4),
      );

  // ---------- 文本 ----------

  Object? _s2t(List<Object?> args) => textConverter.s2t(_str(args, 0));

  Object? _t2s(List<Object?> args) => textConverter.t2s(_str(args, 0));

  // ---------- 加解密 ----------

  Object? _aesX(List<Object?> args) => crypto.aes(
        _str(args, 0),
        _bool(args, 1),
        _str(args, 2),
        _bool(args, 3),
        _str(args, 4),
        _str(args, 5),
        _bool(args, 6),
      );

  Object? _rsaX(List<Object?> args) => crypto.rsa(
        _str(args, 0),
        _bool(args, 1),
        _bool(args, 2),
        _str(args, 3),
        _bool(args, 4),
        _str(args, 5),
        _bool(args, 6),
      );

  /// 原版有两个重载：`rsaEncrypt(data, key)` 与 `rsaEncrypt(data, key, options)`。
  /// JS 没有重载，因此这里按第三个参数是否存在来分派。
  Object? _rsaEncrypt(List<Object?> args) {
    final data = _str(args, 0);
    final key = _str(args, 1);
    final options = _map(args, 2);
    if (options == null) return crypto.rsaEncrypt(data, key);
    return crypto.rsaEncrypt(
      data,
      key,
      type: _intIn(options, 'type', 1),
      long: _intIn(options, 'long', 1),
      block: options['block'] as bool? ?? true,
      config: options['config'] as String?,
    );
  }

  Object? _rsaDecrypt(List<Object?> args) {
    final data = _str(args, 0);
    final key = _str(args, 1);
    final options = _map(args, 2);
    if (options == null) return crypto.rsaDecrypt(data, key);
    return crypto.rsaDecrypt(
      data,
      key,
      type: _intIn(options, 'type', 1),
      long: _intIn(options, 'long', 1),
      block: options['block'] as bool? ?? true,
      config: options['config'] as String?,
    );
  }

  // ---------- 网络 ----------

  /// 对齐 `Global._http`：
  /// - options 里没有 `complete` → 同步返回 `{headers, content}`
  /// - 有 `complete` → 请求完成后回调它，自身返回 null
  ///   （net.js 的 `http()` 会把这个回调包成 Promise）
  Object? _http(List<Object?> args) {
    final url = _str(args, 0);
    final options = _map(args, 1) ?? const {};
    final complete = options['complete'];

    final request = SyncHttpRequest(
      url: url,
      method: (options['method'] as String?) ?? 'get',
      headers: _stringMap(options['headers']),
      data: options['data'],
      body: options['body'] as String?,
      postType: _postType(options['postType']),
      buffer: HttpBufferMode.from(_asInt(options['buffer'])),
      timeoutMs: _asInt(options['timeout']) ?? 10000,
      followRedirects: (_asInt(options['redirect']) ?? 1) == 1,
    );

    if (complete == null) {
      return _toJsResponse(http.execute(request), request.buffer);
    }

    final response = http.execute(request);
    engine.callFunction(complete, [_toJsResponse(response, request.buffer)]);
    return null;
  }

  /// 对齐 `Connect.success`：只返回 headers 与 content 两个字段。
  Object? _toJsResponse(SyncHttpResponse res, HttpBufferMode buffer) => {
        'headers': res.headers.map(
          (k, v) => MapEntry<String, Object?>(k, v.length == 1 ? v.first : v),
        ),
        'content': buffer == HttpBufferMode.text
            ? res.contentAsString
            : res.content,
      };

  // ---------- 代理 ----------

  /// 对齐 `Global.getProxy`：`{base}proxy?do=js`。
  ///
  /// [local] 为 true 走本地回环地址，false 走局域网地址
  /// （对应原版 `ControlManager.get().getAddress(local)`）。
  /// [proxyBaseUrl] 与 [localProxyBaseUrl] 都需要自带结尾斜杠。
  String _proxyJsUrl(bool local) =>
      '${local ? (localProxyBaseUrl ?? proxyBaseUrl) : proxyBaseUrl}proxy?do=js';

  Object? _getProxy(List<Object?> args) => _proxyJsUrl(_bool(args, 0));

  /// 对齐 `Global.js2Proxy`，参数顺序与 URL 编码都必须一致：
  /// `&from=catvod&siteType=&siteKey=&header=&url=`
  Object? _js2Proxy(List<Object?> args) {
    // 原版：boolean local = dynamic == null || !dynamic;
    final dynamic_ = _bool(args, 0);
    final siteType = _str(args, 1);
    final siteKey = _str(args, 2);
    final url = _str(args, 3);
    final headers = _map(args, 4) ?? const {};

    final encodedHeaders = Uri.encodeComponent(_jsonOf(headers));
    final encodedUrl = Uri.encodeComponent(url);
    return '${_proxyJsUrl(!dynamic_)}'
        '&from=catvod'
        '&siteType=$siteType'
        '&siteKey=$siteKey'
        '&header=$encodedHeaders'
        '&url=$encodedUrl';
  }

  // ---------- 定时器 ----------

  /// 对齐 `Global.setTimeout`：注册的函数必须 hold 住，否则会被 GC 回收。
  Object? _setTimeout(List<Object?> args) {
    final fn = args.isNotEmpty ? args[0] : null;
    final delay = _asInt(args.length > 1 ? args[1] : null) ?? 0;
    if (fn == null) return null;
    Future<void>.delayed(Duration(milliseconds: delay), () {
      if (!engine.isDisposed) engine.callFunction(fn, const []);
    });
    return null;
  }

  // ---------- local ----------

  /// 对齐 `local.java`：key 前缀为 `jsRuntime_{id}_{key}`。
  Object? _localGet(List<Object?> args) =>
      storage.get(_str(args, 0), _str(args, 1));

  Object? _localSet(List<Object?> args) {
    storage.set(_str(args, 0), _str(args, 1), _str(args, 2));
    return null;
  }

  Object? _localDelete(List<Object?> args) {
    storage.delete(_str(args, 0), _str(args, 1));
    return null;
  }

  // ---------- 参数工具 ----------

  static String _str(List<Object?> args, int i) {
    final v = i < args.length ? args[i] : null;
    return v?.toString() ?? '';
  }

  static bool _bool(List<Object?> args, int i) {
    final v = i < args.length ? args[i] : null;
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) return v == 'true' || v == '1';
    return false;
  }

  static Map<String, Object?>? _map(List<Object?> args, int i) {
    final v = i < args.length ? args[i] : null;
    return v is Map ? v.cast<String, Object?>() : null;
  }

  static int? _asInt(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  static int _intIn(Map<String, Object?> m, String key, int fallback) =>
      _asInt(m[key]) ?? fallback;

  static Map<String, String> _stringMap(Object? v) {
    if (v is! Map) return const {};
    return v.map((k, val) => MapEntry(k.toString(), val?.toString() ?? ''));
  }

  static HttpPostType _postType(Object? v) => switch (v?.toString()) {
        'form' => HttpPostType.form,
        'form-data' => HttpPostType.formData,
        _ => HttpPostType.json,
      };

  String _jsonOf(Object? v) => engine.stringify(v);
}
