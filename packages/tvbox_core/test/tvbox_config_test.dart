import 'package:test/test.dart';
import 'package:tvbox_core/tvbox_core.dart';

void main() {
  group('TvBoxConfig.fromJson', () {
    test('解析 sites 全字段', () {
      final config = TvBoxConfig.fromJson({
        'spider': 'https://example.com/spider.jar;md5;abc',
        'sites': [
          {
            'key': 'csp_A',
            'name': '站点A',
            'type': 3,
            'api': 'csp_A',
            'searchable': 1,
            'quickSearch': 0,
            'filterable': 1,
            'ext': {'from': 'test'},
            'jar': '',
            'categories': ['电影', '剧集'],
            'timeout': 20,
          },
          {'key': 'cms_b', 'name': '采集B', 'type': 1, 'api': 'https://b/api'},
          {'key': '', 'api': 'https://x'}, // 缺 key，应跳过
          'not-a-map', // 非对象，应跳过
        ],
      });

      expect(config.sites, hasLength(2));

      final a = config.sites[0];
      expect(a.key, 'csp_A');
      expect(a.type, SourceType.spider);
      expect(a.searchable, isTrue);
      expect(a.quickSearch, isFalse);
      expect(a.filterable, isTrue);
      expect(a.spiderKind, SpiderKind.jar); // api 不含 .js/.py
      expect(a.categories, ['电影', '剧集']);
      expect(a.timeout, 20);
      // ext 对象应序列化为 JSON 字符串
      expect(a.ext, '{"from":"test"}');

      final b = config.sites[1];
      expect(b.type, SourceType.json);
      expect(b.spiderKind, isNull); // 采集站没有 spiderKind
    });

    test('js / py 爬虫按 api 后缀判定', () {
      final config = TvBoxConfig.fromJson({
        'sites': [
          {'key': 'j', 'api': 'https://x/drpy.js', 'type': 3},
          {'key': 'p', 'api': 'https://x/spider.py?token=1', 'type': 3},
          {'key': 'q', 'api': 'https://x/spider.js?v=2', 'type': 3},
        ],
      });
      expect(config.sites[0].spiderKind, SpiderKind.js);
      expect(config.sites[1].spiderKind, SpiderKind.python);
      expect(config.sites[2].spiderKind, SpiderKind.js); // .js? 也要命中
    });

    test('解析 lives 多地址', () {
      final config = TvBoxConfig.fromJson({
        'lives': [
          {
            'name': '直播',
            'type': 0,
            'url': ['https://a/tv.txt', 'https://b/tv.txt'],
            'epg': 'https://epg/',
          },
        ],
      });
      expect(config.lives, hasLength(1));
      expect(config.lives.first.urls, hasLength(2));
    });
  });

  group('站点过滤', () {
    test('平台不支持 jar/py 时过滤对应站点', () {
      final sources = TvBoxConfig.fromJson({
        'sites': [
          {'key': 'j', 'api': 'a.js', 'type': 3},
          {'key': 'p', 'api': 'a.py', 'type': 3},
          {'key': 'r', 'api': 'a.jar', 'type': 3},
          {'key': 'c', 'api': 'https://c/api', 'type': 1},
        ],
      }).sites;

      final desktop = _FakeBridge(jar: false, py: false);
      final kept = desktop.filterSupported(sources);
      expect(kept.map((s) => s.key), ['j', 'c']);

      final androidLike = _FakeBridge(jar: true, py: true);
      expect(androidLike.filterSupported(sources), hasLength(4));
    });
  });
}

class _FakeBridge extends PlatformBridge {
  _FakeBridge({required bool jar, required bool py})
      : supportsJarSpider = jar,
        supportsPySpider = py;

  @override
  final bool supportsJarSpider;
  @override
  final bool supportsPySpider;

  @override
  String get platformName => 'test';
  @override
  String get proxyBaseUrl => 'http://127.0.0.1:1/';

  @override
  Spider? createJarSpider({
    required String key,
    required String api,
    String ext = '',
    String jar = '',
  }) =>
      null;
  @override
  Spider? createPySpider({
    required String key,
    required String api,
    String ext = '',
  }) =>
      null;
  @override
  SyncHttpClient createSyncHttpClient() => throw UnimplementedError();
  @override
  HtmlRules createHtmlRules() => throw UnimplementedError();
  @override
  JsCrypto createCrypto() => throw UnimplementedError();
  @override
  TextConverter createTextConverter() => throw UnimplementedError();
  @override
  Future<String> getAppDataPath() async => '';
  @override
  Future<String> getCachePath() async => '';
}
