import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tvbox_core/tvbox_core.dart';
import 'package:tvbox_native/tvbox_native.dart';

/// 桌面端平台能力实现。
///
/// 分阶段落地，当前状态：
/// - ✅ 路径、存储、代理基址
/// - ✅ `SyncHttpClient`（libcurl FFI，已通过真实网络测试）
/// - ⏳ `HtmlRules`（P2，jsoup 规则移植）
/// - ⏳ `JsCrypto` / `TextConverter`（P1）
/// - ⏳ jar / python（P6，内嵌 JVM / libpython）
class DesktopPlatformBridge implements PlatformBridge {
  DesktopPlatformBridge({this.proxyPort = 9978});

  final int proxyPort;

  @override
  String get platformName => Platform.operatingSystem;

  // ---- 爬虫能力 ----

  /// P6：桌面端计划通过内嵌 JVM + dex→class 转换支持 jar 爬虫。
  @override
  bool get supportsJarSpider => false;

  /// P6：桌面端计划内嵌 libpython 支持 Python 爬虫。
  @override
  bool get supportsPySpider => false;

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

  // ---- 基础能力 ----

  late final SyncHttpClient _syncHttp = CurlSyncHttpClient();

  @override
  SyncHttpClient createSyncHttpClient() => _syncHttp;

  @override
  HtmlRules createHtmlRules() => throw UnimplementedError(
        'P2：需要移植 util/js/HtmlParser.java（jsoup 规则引擎）。',
      );

  @override
  JsCrypto createCrypto() => throw UnimplementedError(
        'P1：AES 用 pointycastle 可直接实现；RSA 分段逻辑需对照 '
        'util/js/rsa/RSAEncrypt.java 的 config/type/long/block 语义。',
      );

  @override
  TextConverter createTextConverter() => throw UnimplementedError(
        'P1：s2t/t2s 需要繁简字表，可参考原版 Trans.java 的映射数据。',
      );

  @override
  String get proxyBaseUrl => 'http://127.0.0.1:$proxyPort/';

  // ---- 路径 ----

  @override
  Future<String> getAppDataPath() async {
    final dir = await getApplicationSupportDirectory();
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir.path;
  }

  @override
  Future<String> getCachePath() async {
    final dir = await getApplicationCacheDirectory();
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir.path;
  }
}

/// 基于 shared_preferences 的 `local` 存储。
///
/// key 格式为 `jsRuntime_{id}_{key}`，与原版 Hawk 保持一致，
/// 否则不同站点的同名 key 会互相覆盖。
class SharedPrefsStore implements KeyValueStore {
  SharedPrefsStore(this._prefs);

  final SharedPreferences _prefs;

  static Future<SharedPrefsStore> create() async =>
      SharedPrefsStore(await SharedPreferences.getInstance());

  String _k(String id, String key) => 'jsRuntime_${id}_$key';

  @override
  String get(String id, String key, {String defaultValue = ''}) =>
      _prefs.getString(_k(id, key)) ?? defaultValue;

  @override
  void set(String id, String key, String value) =>
      _prefs.setString(_k(id, key), value);

  @override
  void delete(String id, String key) => _prefs.remove(_k(id, key));
}
