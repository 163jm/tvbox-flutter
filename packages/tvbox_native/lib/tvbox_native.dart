/// tvbox_native：dart:ffi 实现的原生能力层。
///
/// 依赖 tvbox_core 的抽象并为其提供实现；不依赖 Flutter。
library;

export 'src/curl/curl_bindings.dart';
export 'src/curl/curl_sync_http.dart';
export 'src/quickjs/qjs_bindings.dart';
export 'src/quickjs/quickjs_engine.dart';
