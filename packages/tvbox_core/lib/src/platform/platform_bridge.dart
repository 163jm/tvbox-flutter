import 'dart:async';

import '../host/crypto.dart';
import '../host/html_rules.dart';
import '../host/sync_http.dart';
import '../host/text_converter.dart';
import '../model/source_bean.dart';
import '../spider/spider.dart';

/// 平台能力桥。
///
/// jar / python 爬虫、同步 HTTP、HTML 规则引擎、本地路径这些能力在
/// 不同平台上的实现完全不同（Android 有 DexClassLoader，桌面要么内嵌
/// JVM 要么放弃，iOS 因平台政策禁止动态代码执行）。
///
/// `core` 层只依赖这个抽象，由各 app 在启动时注入自己的实现。
abstract class PlatformBridge {
  /// 平台标识，用于日志与问题定位。
  String get platformName;

  // ---- 爬虫能力 ----

  /// 是否支持 jar 爬虫（DexClassLoader / 内嵌 JVM）。
  bool get supportsJarSpider;

  /// 是否支持 python 爬虫（ChaquoPy / 内嵌 libpython）。
  bool get supportsPySpider;

  /// 创建 jar 爬虫。平台不支持时返回 null。
  Spider? createJarSpider({
    required String key,
    required String api,
    String ext = '',
    String jar = '',
  });

  /// 创建 python 爬虫。平台不支持时返回 null。
  Spider? createPySpider({
    required String key,
    required String api,
    String ext = '',
  });

  // ---- 基础能力 ----

  /// 同步 HTTP 客户端。
  SyncHttpClient createSyncHttpClient();

  /// HTML 规则引擎。
  HtmlRules createHtmlRules();

  /// 加解密能力（aesX / rsaX / rsaEncrypt / rsaDecrypt / md5）。
  JsCrypto createCrypto();

  /// 繁简转换（s2t / t2s）。
  TextConverter createTextConverter();

  /// 本地代理服务基址，供 `getProxy` / `js2Proxy` 拼 URL。
  /// 爬虫返回的播放地址需要带 header 时，必须经由这个代理转发。
  String get proxyBaseUrl;

  // ---- 路径 ----

  Future<String> getAppDataPath();

  Future<String> getCachePath();

  /// 过滤掉当前平台不支持的站点。
  ///
  /// iOS 上 jar / py 站点会被移除，避免用户点了没反应。
  List<SourceBean> filterSupported(List<SourceBean> sources) => sources
      .where((s) => s.spiderKind?.isSupported(this) ?? true)
      .toList(growable: false);
}
