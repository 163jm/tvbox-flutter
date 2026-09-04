import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:tvbox_core/tvbox_core.dart';

/// QuickJS 绑定一致性测试。
///
/// 两条绑定路线（自建 FFI / flutter_qjs_next）必须通过同一套用例，
/// 行为不一致的地方在切换实现时就会立刻暴露，而不是上线后某个站点
/// 莫名抓不到数据。
///
/// 用法（实现包的测试文件里）：
/// ```dart
/// import 'package:tvbox_core/conformance_suite.dart';
/// void main() => runJsConformanceSuite(MyEngineFactory());
/// ```
void runJsConformanceSuite(JsEngineFactory factory) {
  late JsEngine engine;

  setUp(() => engine = factory.create(const JsEngineConfig()));
  tearDown(() {
    if (!engine.isDisposed) engine.dispose();
  });

  test('implementationName 不为空', () {
    expect(engine.implementationName, isNotEmpty);
  });

  test('evaluate 基础运算与类型映射', () {
    final r = engine.evaluate('({sum: 1 + 2, text: "ok", flag: true})');
    expect(r, isA<Map>());
    final map = r! as Map;
    expect(map['sum'], 3);
    expect(map['text'], 'ok');
    expect(map['flag'], true);
  });

  test('宿主函数同步调用', () {
    engine.registerFunction('tvboxAdd', (args) {
      final a = args.isNotEmpty ? args[0] : 0;
      final b = args.length > 1 ? args[1] : 0;
      return (a as num).toInt() + (b as num).toInt();
    });
    expect(engine.evaluate('tvboxAdd(20, 22)'), 42);
  });

  test('宿主函数可返回 Map 并在 JS 侧访问', () {
    engine.registerFunction('tvboxCfg', (args) => {'name': 'tvbox', 'n': 3});
    expect(
      engine.evaluate('const c = tvboxCfg(); c.name + "-" + (c.n * 2)'),
      'tvbox-6',
    );
  });

  test('ES module：import 宿主提供的源码模块', () {
    engine.setModuleLoader(StaticModuleLoader({
      'dep.js': 'export const value = 7;\n'
          'export function double(x) { return x * 2; }',
    }));
    // module eval 返回 namespace 对象，default 导出在 ['default'] 下
    final r = engine.evaluateModule(
      "import { value, double } from 'dep.js';\n"
      'export default value + double(3);',
      fileName: 'main.js',
    ) as Map;
    expect(r['default'], 13);
  });

  test('bytecode 编译与执行往返', () {
    final bytecode = engine.compileModule(
      'export default 6 * 7;',
      fileName: 'answer.js',
    );
    expect(bytecode, isA<Uint8List>());
    final ns = engine.executeBytecode(bytecode, fileName: 'answer.js') as Map;
    expect(ns['default'], 42);
  });

  test('bytecode 加载器优先于源码', () {
    setPriorityLoaderBytecode(engine.compileModule(
      'export const v = 1;',
      fileName: 'both.js',
    ));
    engine.setModuleLoader(PriorityModuleLoader());
    final ns = engine.evaluateModule(
      "import { v } from 'both.js';\nexport default v;",
      fileName: 'main.js',
    ) as Map;
    expect(ns['default'], 1); // bytecode 里的值，而不是源码里的 2
  });

  test('Promise 需要排空微任务', () {
    engine.evaluate(
      'globalThis.__done = false;\n'
      'Promise.resolve().then(() => { globalThis.__done = true; });',
    );
    var drained = false;
    for (var i = 0; i < 10 && !drained; i++) {
      drained = !engine.executePendingJobs();
    }
    expect(drained, isTrue, reason: 'executePendingJobs 返回 true 表示队列已空');
    expect(engine.getGlobalProperty('__done'), true);
  });

  test('宿主函数内抛出的异常要能被 JS 捕获', () {
    engine.registerFunction('tvboxBoom', (args) => throw StateError('boom'));
    expect(
      engine.evaluate(
        'try { tvboxBoom(); "no"; } catch (e) { "caught"; }',
      ),
      'caught',
    );
  });

  test('stringify 与 parseJson 往返', () {
    final obj = engine.parseJson('{"a": [1, 2, 3], "b": "x"}');
    final json = engine.stringify(obj);
    expect(json, contains('"a"'));
    expect(json, contains('[1,2,3]'));
  });

  test('runGC 与 getMemoryUsage 不崩溃', () {
    engine.evaluate('const junk = new Array(10000).fill(0);');
    engine.runGC();
    expect(engine.getMemoryUsage(), isNotNull);
  });

  test('dispose 后再调用应安全失败', () {
    engine.dispose();
    expect(engine.isDisposed, isTrue);
    expect(() => engine.evaluate('1'), throwsA(anything));
  });
}

/// 只提供源码的加载器。
class StaticModuleLoader implements JsModuleLoader {
  StaticModuleLoader(this.modules);
  final Map<String, String> modules;

  @override
  Uint8List? getModuleBytecode(String moduleName) => null;

  @override
  String? getModuleSource(String moduleName) => modules[moduleName];

  @override
  String normalizeName(String moduleBaseName, String moduleName) => moduleName;
}

/// 同时提供 bytecode 与 source，用于验证优先级。
class PriorityModuleLoader implements JsModuleLoader {
  @override
  Uint8List? getModuleBytecode(String moduleName) {
    if (moduleName != 'both.js') return null;
    return _bothBytecode;
  }

  @override
  String? getModuleSource(String moduleName) =>
      moduleName == 'both.js' ? 'export const v = 2;' : null;

  @override
  String normalizeName(String moduleBaseName, String moduleName) => moduleName;
}

/// 测试入口由实现侧赋值（见各实现的测试文件说明）。
Uint8List? _bothBytecode;

/// 实现侧在测试里调用，注入预编译的 `export const v = 1;`。
void setPriorityLoaderBytecode(Uint8List bytecode) => _bothBytecode = bytecode;
