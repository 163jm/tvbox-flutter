import 'dart:io';

import 'package:test/test.dart';
import 'package:tvbox_core/conformance_suite.dart';
import 'package:tvbox_core/tvbox_core.dart';
import 'package:tvbox_native/tvbox_native.dart';

/// QuickJS FFI 实现的一致性测试接线。
///
/// 需要 quickjs_bridge 动态库（quickjs-ng + native/quickjs_bridge.c）：
/// - 本机：设环境变量 `TVBOX_QJS_LIB=/path/to/libquickjs_bridge.dll`
/// - CI：见 .github/workflows/engine.yml（自动编译后注入）
///
/// 未设置环境变量时整体跳过——保证 `dart test` 在任何环境都能通过。
void main() {
  final libPath = Platform.environment['TVBOX_QJS_LIB'];
  if (libPath == null || libPath.isEmpty) {
    test('跳过：未提供 TVBOX_QJS_LIB（CI 会自动编译并注入）', () {
      markTestSkipped('需要 quickjs_bridge 动态库');
    });
    return;
  }

  runJsConformanceSuite(_QuickjsFactoryWithLib(libPath));
}

class _QuickjsFactoryWithLib implements JsEngineFactory {
  _QuickjsFactoryWithLib(this.libPath);
  final String libPath;

  @override
  String get name => 'quickjs-ffi';

  @override
  JsEngine create(JsEngineConfig config) =>
      QuickjsEngine.createWith(config, libPath: libPath);
}
