import 'dart:convert';

import '../model/source_bean.dart';

/// TVBox 配置文档。
///
/// 对应原版 `api/ApiConfig.java` 解析的配置 JSON。只保留核心字段，
/// parses / flags / rules 等解析器相关配置在 P3 接入 UI 时补充。
///
/// 典型结构：
/// ```json
/// {
///   "spider": "https://..../spider.jar;md5;xxxx",
///   "wallpaper": "https://...",
///   "sites": [
///     { "key": "csp_XXX", "name": "XXX", "type": 3, "api": "csp_XXX",
///       "searchable": 1, "quickSearch": 1, "filterable": 1,
///       "ext": "...", "jar": "..." }
///   ],
///   "lives": [ { "name": "...", "type": 0, "url": "..." } ]
/// }
/// ```
class TvBoxConfig {
  const TvBoxConfig({
    this.spider = '',
    this.wallpaper = '',
    this.sites = const [],
    this.lives = const [],
  });

  /// 全局爬虫 jar 地址，可带 `;md5;xxx` 校验段。
  final String spider;

  final String wallpaper;

  final List<SourceBean> sites;

  final List<LiveInfo> lives;

  factory TvBoxConfig.fromJson(Map<String, Object?> json) {
    return TvBoxConfig(
      spider: json['spider']?.toString() ?? '',
      wallpaper: json['wallpaper']?.toString() ?? '',
      sites: _parseSites(json['sites']),
      lives: _parseLives(json['lives']),
    );
  }

  static List<SourceBean> _parseSites(Object? raw) {
    if (raw is! List) return const [];
    final result = <SourceBean>[];
    for (final item in raw) {
      // 原版允许 sites 里混入纯字符串形式的简写（视为无效，跳过）
      if (item is! Map) continue;
      final site = _parseSite(item.cast<String, Object?>());
      if (site != null) result.add(site);
    }
    return result;
  }

  /// 单个站点解析，字段与原版 `ApiConfig` 的一致。
  static SourceBean? _parseSite(Map<String, Object?> m) {
    final key = m['key']?.toString() ?? '';
    final api = m['api']?.toString() ?? '';
    if (key.isEmpty || api.isEmpty) return null;

    return SourceBean(
      key: key,
      name: m['name']?.toString() ?? key,
      api: api,
      type: SourceTypeX.from(_asInt(m['type'])),
      searchable: _asInt(m['searchable']) != 0,
      quickSearch: _asInt(m['quickSearch']) != 0,
      filterable: _asInt(m['filterable']) != 0,
      playerUrl: m['playerUrl']?.toString() ?? '',
      ext: _parseExt(m['ext']),
      jar: m['jar']?.toString() ?? '',
      categories: (m['categories'] as List?)
          ?.map((e) => e.toString())
          .toList(growable: false),
      playerType: _asInt(m['playerType']) ?? -1,
      timeout: _asInt(m['timeout']) ?? 15,
      clickSelector: m['click']?.toString() ?? '',
      style: m['style']?.toString() ?? '',
    );
  }

  /// ext 字段兼容处理。
  ///
  /// 原版允许三种形态：字符串原样、JSON 对象（序列化成字符串）、
  /// base64（交给具体爬虫自己解）。这里统一成字符串，
  /// 解码留给 JsSpider / 爬虫源码，行为与原版一致。
  static String _parseExt(Object? ext) {
    if (ext == null) return '';
    if (ext is Map || ext is List) return jsonEncode(ext);
    return ext.toString();
  }

  static List<LiveInfo> _parseLives(Object? raw) {
    if (raw is! List) return const [];
    final result = <LiveInfo>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final m = item.cast<String, Object?>();
      // 原版 lives 支持 group 数组与单 url 两种写法，这里取并集
      final urls = <String>[];
      final rawUrl = m['url'];
      if (rawUrl is List) {
        urls.addAll(rawUrl.map((e) => e.toString()));
      } else if (rawUrl != null) {
        urls.add(rawUrl.toString());
      }
      if (urls.isEmpty) continue;
      result.add(LiveInfo(
        name: m['name']?.toString() ?? '',
        type: _asInt(m['type']) ?? 0,
        urls: urls,
        epg: m['epg']?.toString() ?? '',
        logo: m['logo']?.toString() ?? '',
      ));
    }
    return result;
  }

  static int? _asInt(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }
}

/// 直播源配置。
class LiveInfo {
  const LiveInfo({
    this.name = '',
    this.type = 0,
    this.urls = const [],
    this.epg = '',
    this.logo = '',
  });

  final String name;

  /// 0=普通 1=聚合 2=代理 3=Spider
  final int type;

  /// 支持多地址（原版的 group 写法展开后就是多个 url）。
  final List<String> urls;

  final String epg;
  final String logo;
}
