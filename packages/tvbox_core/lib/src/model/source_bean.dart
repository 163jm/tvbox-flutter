import '../platform/platform_bridge.dart';

/// 站点类型。
///
/// 对齐原版 `SourceBean.type` 字段语义：
/// - 0 / 1：苹果 CMS 采集（0=videolist，1=detail），纯 HTTP + JSON
/// - 2：JSON 扩展（部分分支使用）
/// - 3：Spider 类爬虫，按 api 后缀再分 js / py / jar
/// - 4：XPath 采集，纯 HTTP + JSON
enum SourceType { xml, json, jsonExt, spider, xpath }

extension SourceTypeX on SourceType {
  int get code => switch (this) {
        SourceType.xml => 0,
        SourceType.json => 1,
        SourceType.jsonExt => 2,
        SourceType.spider => 3,
        SourceType.xpath => 4,
      };

  static SourceType from(int? v) => switch (v) {
        0 => SourceType.xml,
        1 => SourceType.json,
        2 => SourceType.jsonExt,
        3 => SourceType.spider,
        4 => SourceType.xpath,
        _ => SourceType.xml,
      };

  /// 采集站走 HTTP + JSON，不需要脚本引擎。
  bool get isCollect => this != SourceType.spider;
}

/// 爬虫种类，仅当 [SourceBean.type] 为 spider 时有意义。
///
/// 判定规则直接对齐原版 `ApiConfig.getCSP()`：
/// - api 以 `.js` 结尾（或含 `.js?`）→ js
/// - api 含 `.py` → py
/// - 其余（`.jar` 等）→ jar
enum SpiderKind { js, python, jar }

extension SpiderKindX on SpiderKind {
  /// 该种类在当前平台是否可用，由 [PlatformBridge] 决定。
  bool isSupported(PlatformBridge bridge) => switch (this) {
        SpiderKind.js => true,
        SpiderKind.python => bridge.supportsPySpider,
        SpiderKind.jar => bridge.supportsJarSpider,
      };
}

/// 站点配置。字段与原版 `bean/SourceBean.java` 一一对应。
class SourceBean {
  SourceBean({
    this.key = '',
    this.name = '',
    this.api = '',
    this.type = SourceType.xml,
    this.searchable = false,
    this.quickSearch = false,
    this.filterable = false,
    this.playerUrl = '',
    this.ext = '',
    this.jar = '',
    List<String>? categories,
    this.playerType = -1,
    this.timeout = 15,
    this.clickSelector = '',
    this.style = '',
  }) : categories = categories ?? const [];

  final String key;
  final String name;
  final String api;

  /// 见 [SourceType]。
  final SourceType type;

  final bool searchable;
  final bool quickSearch;
  final bool filterable;

  /// 站点解析地址（嗅探/解析用）。
  final String playerUrl;

  /// 扩展数据，会原样传给 spider 的 init。
  final String ext;

  /// 自定义 jar 地址（js 爬虫用它加载 jsapi 扩展）。
  final String jar;

  /// 分类与排序。
  final List<String> categories;

  /// 0=system 1=ijk 2=exo 10=mxplayer -1=跟随全局设置
  final int playerType;

  /// 播放信息获取超时，秒。
  final int timeout;

  /// 嗅探站点需要点击播放的 selector，形如 `ddrk.me;#id`。
  final String clickSelector;

  /// 展示风格。
  final String style;

  /// 仅 spider 类站点有意义；采集站返回 null。
  SpiderKind? get spiderKind {
    if (type != SourceType.spider) return null;
    if (api.endsWith('.js') || api.contains('.js?')) return SpiderKind.js;
    if (api.contains('.py')) return SpiderKind.python;
    return SpiderKind.jar;
  }
}
