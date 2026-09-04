/// tvbox_core：TVBox 跨平台核心层。
///
/// 纯 Dart 实现，**禁止** import `dart:ui`、Flutter 插件或任何平台专属包
/// ——这是它能被 desktop / mobile 两个 app 共享的前提。
/// JsEngine、PlatformBridge、SyncHttpClient 等抽象由 app 层注入实现。
library;

export 'src/config/tvbox_config.dart';
export 'src/host/crypto.dart';
export 'src/host/host_api.dart';
export 'src/host/html_rules.dart';
export 'src/host/storage.dart';
export 'src/host/sync_http.dart';
export 'src/host/text_converter.dart';
export 'src/js/js_engine.dart';
export 'src/model/source_bean.dart';
export 'src/player/play_params.dart';
export 'src/platform/platform_bridge.dart';
export 'src/spider/collect_spider.dart';
export 'src/spider/js_spider.dart';
export 'src/spider/module_source.dart';
export 'src/spider/spider.dart';
export 'src/spider/spider_runner.dart';
