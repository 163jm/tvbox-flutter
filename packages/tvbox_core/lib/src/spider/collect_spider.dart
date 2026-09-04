import '../host/sync_http.dart';
import '../model/source_bean.dart';
import 'spider.dart';

/// 采集站爬虫，对应 type 0 / 1 / 4。
///
/// 请求参数严格对齐原版 `SourceViewModel`：
/// - 列表：type 0 → `ac=videolist`，type 1 → `ac=detail&filter=true`
/// - 详情：`ac` 同样按 type 取值，参数为 `ids`
/// - 搜索：`wd` + `ac=detail`
/// - type 4（XPath）：`filter=true` + `extend`
///
/// 虽然是采集站，仍然走 [SyncHttpClient] 在 worker isolate 里同步执行，
/// 这样 [Spider] 接口保持统一，UI 侧不需要区分调用方式。
class CollectSpider implements Spider {
  CollectSpider({
    required this.bean,
    required this.http,
    this.timeoutMs = 15000,
    this.logger,
  }) : siteKey = bean.key;

  @override
  final String siteKey;

  final SourceBean bean;
  final SyncHttpClient http;
  final int timeoutMs;
  final void Function(String message)? logger;

  /// 列表接口动作名。type 0 走 videolist，其余走 detail。
  String get _listAction => bean.type == SourceType.xml ? 'videolist' : 'detail';

  /// 采集站无状态，init 只需接收 ext 以便子类扩展。
  @override
  void init(String extend) {}

  String _get(Map<String, String> params) {
    final uri = Uri.parse(bean.api).replace(queryParameters: {
      ...Uri.parse(bean.api).queryParameters,
      ...params,
    });
    final response = http.execute(
      SyncHttpRequest(url: uri.toString(), timeoutMs: timeoutMs),
    );
    return response.contentAsString;
  }

  @override
  String homeContent(bool filter) {
    if (bean.type == SourceType.xpath) {
      return _get(<String, String>{'filter': 'true'});
    }
    return _get(<String, String>{'ac': _listAction});
  }

  @override
  String homeVideoContent() => '';

  @override
  String categoryContent(
    String tid,
    String pg,
    bool filter,
    Map<String, String> extend,
  ) {
    if (bean.type == SourceType.xpath) {
      return _get(<String, String>{
        'filter': 'true',
        't': tid,
        'pg': pg,
        ...extend,
      });
    }
    return _get(<String, String>{
      'ac': _listAction,
      't': tid,
      'pg': pg,
      if (bean.type == SourceType.json) 'filter': 'true',
      ...extend,
    });
  }

  @override
  String detailContent(List<String> ids) => _get(<String, String>{
        'ac': _listAction,
        'ids': ids.join(','),
      });

  @override
  String searchContent(String key, bool quick, [String? pg]) => _get(
        <String, String>{
          'wd': key,
          'ac': 'detail',
          if (pg != null) 'pg': pg,
        },
      );

  @override
  String playerContent(String flag, String id, List<String> vipFlags) => '';

  @override
  String liveContent(String url) => '';

  @override
  bool isVideoFormat(String url) => false;

  @override
  bool manualVideoCheck() => false;

  @override
  String? action(String action) => null;

  @override
  Object? proxyLocal(Map<String, String> params) => null;

  @override
  void cancelByTag() {}

  @override
  void destroy() {}
}
