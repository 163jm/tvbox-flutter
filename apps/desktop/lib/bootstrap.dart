import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:tvbox_core/tvbox_core.dart';

import 'platform/desktop_bridge.dart';
import 'spider/desktop_module_source.dart';

/// 应用组装层：把 bridge、配置、爬虫运行时串起来。
class AppBootstrap {
  AppBootstrap._(this.bridge, this.store, this.cacheDir);

  final DesktopPlatformBridge bridge;
  final SharedPrefsStore store;
  final Directory cacheDir;

  static Future<AppBootstrap> create() async {
    final bridge = DesktopPlatformBridge();
    final store = await SharedPrefsStore.create();
    final cache = Directory(await bridge.getCachePath());
    return AppBootstrap._(bridge, store, cache);
  }

  /// 模块缓存目录：爬虫源码与依赖模块的本地落点。
  Directory get moduleCacheDir {
    final dir = Directory(
      '${cacheDir.path}${Platform.pathSeparator}catvod_modules',
    );
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  /// 加载 TVBox 配置，支持 http(s) 链接与本地文件。
  ///
  /// 原版还支持 base64 编码的配置体与 `;md5;` 校验段，解析器按需扩展。
  Future<TvBoxConfig> loadConfig(String source) async {
    var text = '';
    if (source.startsWith('http://') || source.startsWith('https://')) {
      final client = HttpClient();
      try {
        final request = await client.getUrl(Uri.parse(source));
        final response =
            await request.close().timeout(const Duration(seconds: 15));
        text = await response.transform(utf8.decoder).join();
      } finally {
        client.close(force: true);
      }
    } else {
      text = await File(source).readAsString();
    }

    // 与原版一致：容忍配置前后多余空白与 BOM
    text = text.trim();
    if (text.startsWith('\uFEFF')) text = text.substring(1);

    return TvBoxConfig.fromJson(
      jsonDecode(text) as Map<String, Object?>,
    );
  }

  /// 在**当前 isolate** 创建 JS 爬虫。
  ///
  /// 只允许在 spider worker isolate 里调用（见 [spiderWorkerMain]），
  /// 主 isolate 调用会因同步 HTTP 阻塞界面。
  JsSpider createJsSpider(String key, String api, String ext) {
    final engine = JsEngine.create();
    final host = JsHostApi(
      engine: engine,
      siteKey: key,
      http: bridge.createSyncHttpClient(),
      html: bridge.createHtmlRules(),
      storage: store,
      crypto: bridge.createCrypto(),
      textConverter: bridge.createTextConverter(),
      proxyBaseUrl: bridge.proxyBaseUrl,
      logger: _log,
    );
    return JsSpider(
      siteKey: key,
      api: api,
      engine: engine,
      modules: DesktopModuleSource(moduleCacheDir),
      host: host,
      logger: _log,
    )..initialize();
  }

  void _log(String message) {
    // P3 接入正式日志系统后替换；isolate 内 print 会带 isolate 前缀输出
    // ignore: avoid_print
    print('[spider] $message');
  }

  /// 按 PlatformBridge 过滤当前平台可用的站点。
  List<SourceBean> supportedSites(TvBoxConfig config) =>
      bridge.filterSupported(config.sites);
}

/// spider worker isolate 的入口。
///
/// 用法：
/// ```dart
/// final runner = await SpiderRunner.spawn(spiderWorkerMain);
/// ```
///
/// **注意**：[AppBootstrap.createJsSpider] 依赖的 SyncHttpClient /
/// HtmlRules / Crypto 尚未实现（P1/P2），此入口目前仅作为骨架存在，
/// 在依赖就绪前调用会在创建爬虫时抛 UnimplementedError。
@pragma('vm:entry-point')
Future<void> spiderWorkerMain(SendPort sendPort) async {
  // isolate 与主 isolate 不共享状态，这里必须重新组装依赖。
  final bootstrap = await AppBootstrap.create();
  runSpiderWorker(
    sendPort,
    (key, api, ext) => bootstrap.createJsSpider(key, api, ext),
  );
}
