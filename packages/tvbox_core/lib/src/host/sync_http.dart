/// 响应体解码方式。对齐原版 `Req.buffer`：
/// 0=文本，1=字节数组，2=base64 字符串。
enum HttpBufferMode {
  text(0),
  bytes(1),
  base64(2);

  const HttpBufferMode(this.code);
  final int code;

  static HttpBufferMode from(int? v) => switch (v) {
        1 => HttpBufferMode.bytes,
        2 => HttpBufferMode.base64,
        _ => HttpBufferMode.text,
      };
}

/// POST 数据编码方式，对齐原版 `Req.postType`。
enum HttpPostType { json, form, formData }

/// 同步 HTTP 请求。字段对齐原版 `Req.java`。
class SyncHttpRequest {
  const SyncHttpRequest({
    required this.url,
    this.method = 'get',
    this.headers = const {},
    this.data,
    this.body,
    this.postType = HttpPostType.json,
    this.buffer = HttpBufferMode.text,
    this.timeoutMs = 10000,
    this.connectTimeoutMs = 5000,
    this.followRedirects = true,
    this.charset,
  });

  final String url;

  /// get / post / header。原版用 `header` 表示 HEAD 请求。
  final String method;

  final Map<String, String> headers;

  /// POST 数据，按 [postType] 编码。
  final Object? data;

  /// 原始请求体，与 [data] 二选一。
  final String? body;

  final HttpPostType postType;
  final HttpBufferMode buffer;
  final int timeoutMs;

  /// TCP 连接建立超时；总超时见 [timeoutMs]。
  final int connectTimeoutMs;
  final bool followRedirects;

  /// 强制指定字符集；不指定时按原版规则从 Content-Type 推断，默认 UTF-8。
  final String? charset;

  bool get isPost => method.toLowerCase() == 'post';

  bool get isHead => method.toLowerCase() == 'header';
}

/// 同步 HTTP 响应。对齐原版 `Connect.success()` 构造的对象结构。
class SyncHttpResponse {
  const SyncHttpResponse({
    required this.content,
    this.headers = const {},
  });

  /// 按 [SyncHttpRequest.buffer] 编码后的内容。
  /// bytes 模式下这里是 `List<int>`，其余模式是 String。
  final Object content;

  final Map<String, List<String>> headers;

  String get contentAsString =>
      content is String ? content as String : content.toString();
}

/// 同步 HTTP 客户端。
///
/// **这是整个项目的架构级决策点。** JS 爬虫大量使用同步请求：
/// ```js
/// let html = req(url).content;   // net.js: async:false → 同步返回
/// ```
/// 而 Dart 只有异步的 `HttpClient`，HTTPS 又必须走 native 的 TLS。
/// 因此实现只能是：
/// - 自建 FFI 路线：在 C shim 里用 libcurl 实现，JS 调用即同步返回；
/// - flutter_qjs_next 路线：在 worker isolate 里阻塞等待 native 结果。
///
/// 无论哪条路线，调用方（JS 引擎）都必须跑在独立 isolate 上，
/// 否则同步阻塞会卡死 UI——原版也是 `newSingleThreadExecutor()`。
abstract class SyncHttpClient {
  /// 同步执行请求。失败时返回空内容的响应，不抛异常（对齐原版 `Connect.error`）。
  SyncHttpResponse execute(SyncHttpRequest request);

  /// 取消打了同一 tag 的请求，对应原版 `Connect.cancelByTag("js_okhttp_tag")`。
  void cancelByTag(Object tag);
}
