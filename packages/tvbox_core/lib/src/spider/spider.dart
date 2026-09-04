/// 爬虫统一接口。
///
/// 方法签名对齐原版 `com.github.catvod.crawler.Spider`，
/// 去掉了 Android `Context` 参数（core 层不持有平台对象）。
/// 所有返回给 UI 的数据都是 JSON 字符串，与原版保持一致，
/// 便于直接复用原版的解析逻辑与测试用例。
abstract class Spider {
  /// 站点 key，用于日志与缓存隔离。
  String get siteKey;

  /// 初始化，[extend] 为站点配置的 ext 字段，原样传入。
  void init(String extend);

  /// 首页内容，[filter] 表示是否返回筛选配置。
  String homeContent(bool filter);

  /// 首页最近更新，homeContent 未包含时使用。
  String homeVideoContent();

  /// 分类内容。
  String categoryContent(
    String tid,
    String pg,
    bool filter,
    Map<String, String> extend,
  );

  /// 详情，[ids] 至少一个元素。
  String detailContent(List<String> ids);

  /// 搜索，[quick] 为快速搜索，[pg] 可为 null。
  String searchContent(String key, bool quick, [String? pg]);

  /// 播放信息，[vipFlags] 为需要解析的flag列表。
  String playerContent(String flag, String id, List<String> vipFlags);

  /// 直播内容。
  String liveContent(String url);

  /// 嗅探时判断 url 是否为视频。
  bool isVideoFormat(String url);

  /// 是否由 spider 自行判断视频（不走系统嗅探）。
  bool manualVideoCheck();

  /// 代理请求。返回 `[status, contentType, body, headers?]`。
  /// 对齐原版 `proxyLocal` 的四元组结构。
  Object? proxyLocal(Map<String, String> params);

  /// 自定义动作。
  String? action(String action);

  /// 取消本 spider 发起的所有请求。
  void cancelByTag();

  /// 释放资源。必须幂等。
  void destroy();
}
