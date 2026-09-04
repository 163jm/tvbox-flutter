import 'dart:typed_data';

import '../host/host_api.dart';
import '../js/js_engine.dart';
import 'module_source.dart';
import 'spider.dart';

/// 模块化加载器。
///
/// 对应原版 `JsSpider.createCtx()` 里的 `BytecodeModuleLoader`。
/// 爬虫 import 的每一个模块都会走这里：cheerio、crypto-js、gbk、
/// cat.js、utils.js、模板.js……命中不了就返回空模块，让 import 拿到
/// undefined 而不是抛错——这样缺依赖的站点还能部分可用。
class TvBoxModuleLoader implements JsModuleLoader {
  TvBoxModuleLoader(this._engine, this._modules, {this.logger});

  final JsEngine _engine;
  final ModuleSource _modules;
  final void Function(String message)? logger;

  Uint8List? _emptyBytecode;

  /// 预编译空模块。对应原版 `compileModule(EMPTY_MODULE_CODE, "empty.js")`。
  void prepare() {
    _emptyBytecode ??= _engine.compileModule(_emptyModuleCode, fileName: 'empty.js');
  }

  @override
  Uint8List? getModuleBytecode(String moduleName) {
    final cached = _modules.loadBytecode(moduleName);
    if (cached != null) return cached;

    final content = _modules.loadSync(moduleName);
    if (isInvalidModuleContent(content)) {
      logger?.call('模块缺失，返回空模块: $moduleName');
      return _emptyBytecode;
    }
    final source = content!;

    try {
      if (source.startsWith('//DRPY')) {
        return decodeDrpyBytecode(source);
      }
      if (source.startsWith('//bb')) {
        return decodeBbBytecode(source);
      }
      final compiled = _engine.compileModule(source, fileName: moduleName);
      // cheerio 与 crypto-js 体积大，编译一次缓存下来
      if (moduleName.contains('cheerio.min.js') ||
          moduleName.contains('crypto-js.js')) {
        _modules.saveBytecode(moduleName, compiled);
      }
      return compiled;
    } catch (e) {
      logger?.call('模块编译失败 $moduleName: $e');
      return _emptyBytecode;
    }
  }

  @override
  String? getModuleSource(String moduleName) {
    // 引擎应优先走 getModuleBytecode；这里只兜底返回纯源码模块，
    // //bb 与 //DRPY 前缀的内容对源码加载器无意义。
    final content = _modules.loadSync(moduleName);
    if (isInvalidModuleContent(content)) return null;
    if (content!.startsWith('//bb') || content.startsWith('//DRPY')) {
      return null;
    }
    return content;
  }

  @override
  String normalizeName(String moduleBaseName, String moduleName) {
    if (moduleName.startsWith('http://') || moduleName.startsWith('https://')) {
      return moduleName;
    }
    if (moduleName.startsWith('/')) return moduleName;
    final base = moduleBaseName;
    final idx = base.lastIndexOf('/');
    if (idx < 0) return moduleName;
    return '${base.substring(0, idx + 1)}$moduleName';
  }
}

/// JS 爬虫。
///
/// 对应原版 `util/js/JsSpider.java`。**必须在创建 [JsEngine] 的那个
/// isolate 里使用**，且方法都是同步的——因为 JS 侧大量依赖同步 HTTP。
/// UI 侧请通过 isolate 封装（见 `spider_runner.dart`）间接调用，
/// 否则同步请求会卡死界面。
class JsSpider implements Spider {
  JsSpider({
    required String siteKey,
    required this.api,
    required JsEngine engine,
    required ModuleSource modules,
    required JsHostApi host,
    this.logger,
  })  : siteKey = siteKey,
        key = 'J$siteKey',
        _engine = engine,
        _modules = modules,
        _host = host;

  @override
  final String siteKey;

  /// 全局对象上挂载 spider 时用的名字。
  /// 原版是 `"J" + MD5(siteKey)`，这里省去 md5——
  /// 每个爬虫一个独立引擎，名字只需要保证唯一，加 J 前缀便于日志辨认。
  final String key;

  /// 爬虫地址。
  final String api;

  final JsEngine _engine;
  final ModuleSource _modules;
  final JsHostApi _host;
  final void Function(String message)? logger;

  /// 是否为 `__jsEvalReturn` 风格的爬虫（原版里的 cat 模式）。
  bool _cat = false;

  Object? _spiderObject;
  bool _destroyed = false;

  /// 初始化。必须在 [JsHostApi.install] 之后调用。
  void initialize() {
    final loader = TvBoxModuleLoader(_engine, _modules, logger: logger);
    loader.prepare();
    _engine.setModuleLoader(loader);
    _engine.setConsoleSink(logger);
    _host.install();

    _evalNetJs();
    _preloadTemplate();

    final content = _modules.loadSync(api);
    if (isInvalidModuleContent(content)) {
      throw StateError('爬虫内容无效: $api');
    }

    if (content!.startsWith('//bb')) {
      _cat = true;
      _engine.executeBytecode(decodeBbBytecode(content), fileName: '$key.js');
      _evalSpiderRoot('$key.js');
    } else {
      var src = content;
      if (src.contains('__JS_SPIDER__')) {
        src = src.replaceAll(RegExp(r'__JS_SPIDER__\s*='), 'export default ');
      }
      if (src.contains('__jsEvalReturn') && !src.contains('export default')) {
        _cat = true;
      }
      _engine.evaluateModule(src, fileName: api);
      _evalSpiderRoot(api);
    }

    _spiderObject = _engine.getGlobalProperty(key);
    if (_spiderObject == null) {
      throw StateError('爬虫未在全局对象上导出 $key');
    }
  }

  /// net.js 定义了 `req` 与 `http`，是爬虫事实上的网络入口。
  void _evalNetJs() {
    final net = _modules.loadSync('net.js');
    if (isInvalidModuleContent(net)) {
      logger?.call('net.js 缺失，req/http 将不可用');
      return;
    }
    _engine.evaluate(net!, fileName: 'net.js');
  }

  /// 模板预加载，对应原版 `preloadTemplate`：
  /// 成功后 JS 侧可直接用 `muban` 与 `getMubans`。
  void _preloadTemplate() {
    try {
      _engine.evaluateModule(
        "import tpl from '模板.js';\n"
        'globalThis.muban = tpl.muban;\n'
        'globalThis.getMubans = tpl.getMubans;',
        fileName: 'tv_box_template.js',
      );
    } catch (e) {
      logger?.call('模板预加载失败: $e');
    }
  }

  void _evalSpiderRoot(String moduleName) {
    _engine.evaluateModule(
      _spiderStringCode(moduleName) + 'globalThis.$key = globalThis.__JS_SPIDER__;',
      fileName: 'tv_box_root.js',
    );
  }

  String _spiderStringCode(String moduleName) => "import * as spider from '$moduleName'\n"
      '\n'
      'if (!globalThis.__JS_SPIDER__) {\n'
      '    if (spider.__jsEvalReturn) {\n'
      '        globalThis.req = http\n'
      '        globalThis.__JS_SPIDER__ = spider.__jsEvalReturn()\n'
      "        globalThis.__JS_SPIDER__.is_cat = true\n"
      '    } else if (spider.default) {\n'
      '        globalThis.__JS_SPIDER__ = typeof spider.default === \'function\' '
      '? spider.default() : spider.default\n'
      '    }\n'
      '}\n';

  Object? _call(String func, List<Object?> args) {
    if (_destroyed || _spiderObject == null) return null;
    final fn = _property(func);
    if (fn == null) return null;
    try {
      return _engine.callFunction(fn, args);
    } catch (e) {
      logger?.call('调用 $func 失败: $e');
      return null;
    } finally {
      // 异步路径（http() 返回 Promise）需要排空微任务队列
      _engine.executePendingJobs();
    }
  }

  Object? _property(String name) {
    final obj = _spiderObject;
    if (obj is Map) return obj[name];
    return null;
  }

  // ---------- Spider ----------

  @override
  void init(String extend) {
    if (_cat) {
      final cfg = <String, Object?>{
        'stype': 3,
        'skey': key,
        'ext': _looksLikeJson(extend) ? _engine.parseJson(extend) : extend,
      };
      _call('init', [cfg]);
    } else {
      _call('init', [
        _looksLikeJson(extend) ? _engine.parseJson(extend) : extend,
      ]);
    }
  }

  @override
  String homeContent(bool filter) => _asString(_call('home', [filter]));

  @override
  String homeVideoContent() => _asString(_call('homeVod', const []));

  @override
  String categoryContent(
    String tid,
    String pg,
    bool filter,
    Map<String, String> extend,
  ) =>
      _asString(_call('category', [tid, pg, filter, extend]));

  @override
  String detailContent(List<String> ids) =>
      _asString(_call('detail', [ids.isNotEmpty ? ids.first : '']));

  @override
  String searchContent(String key, bool quick, [String? pg]) =>
      _asString(_call('search', pg == null ? [key, quick] : [key, quick, pg]));

  @override
  String playerContent(String flag, String id, List<String> vipFlags) =>
      _asString(_call('play', [flag, id, vipFlags]));

  @override
  String liveContent(String url) => _asString(_call('live', [url]));

  @override
  bool isVideoFormat(String url) => _call('isVideo', [url]) == true;

  @override
  bool manualVideoCheck() => _call('sniffer', const []) == true;

  @override
  String? action(String action) {
    final r = _call('action', [action]);
    return r?.toString();
  }

  @override
  Object? proxyLocal(Map<String, String> params) {
    final r = _call('proxy', [params]);
    if (r is List) return r;
    if (r is Map) {
      return [
        r[0] ?? r['code'],
        r[1] ?? r['type'],
        r[2] ?? r['content'],
        r[3] ?? r['headers'],
      ];
    }
    return null;
  }

  @override
  void cancelByTag() {
    // 由 SyncHttpClient 侧按 tag 取消，见 JsHostApi 注入的 client
  }

  @override
  void destroy() {
    if (_destroyed) return;
    _destroyed = true;
    _spiderObject = null;
    _engine.dispose();
  }

  static String _asString(Object? v) => v?.toString() ?? '';

  static bool _looksLikeJson(String s) {
    final t = s.trimLeft();
    return t.startsWith('{') || t.startsWith('[');
  }
}

/// 空模块。
///
/// 对应原版 `JsSpider.EMPTY_MODULE_CODE`，导出全部为 undefined，
/// 让依赖缺失的模块仍能完成 import。
const String _emptyModuleCode = 'const empty = null;\n'
    'export default empty;\n'
    'export const JSEncrypt = empty;\n'
    'export const NodeRSA = empty;\n'
    'export const pako = empty;\n'
    'export const JSON5 = empty;\n'
    'export const mb = empty;\n'
    'export const parse = empty;\n'
    'export const stringify = empty;\n'
    'export const inflate = empty;\n'
    'export const deflate = empty;\n'
    'export const gzip = empty;\n'
    'export const ungzip = empty;\n'
    'export const encrypt = empty;\n'
    'export const decrypt = empty;';
