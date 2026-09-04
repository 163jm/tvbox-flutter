import 'dart:io';
import 'dart:typed_data';

import 'package:tvbox_core/tvbox_core.dart';

/// 桌面端模块来源：本地缓存目录。
///
/// 爬虫源码与依赖模块（cheerio、crypto-js、模板.js 等）在配置加载阶段
/// 由外层预取到缓存目录，[loadSync] 只读文件——它会被 JS 引擎的
/// import 回调同步调用，没有 await 的机会。
class DesktopModuleSource implements ModuleSource {
  DesktopModuleSource(this._cacheDir);

  final Directory _cacheDir;

  File _file(String name) {
    // 模块名可能带路径（lib/xxx.js），统一展平到缓存目录
    final safe = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    return File('${_cacheDir.path}${Platform.pathSeparator}$safe');
  }

  File _bcFile(String name) {
    final safe = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    return File('${_cacheDir.path}${Platform.pathSeparator}$safe.bc');
  }

  @override
  String? loadSync(String name) {
    final f = _file(name);
    if (!f.existsSync()) return null;
    try {
      return f.readAsStringSync();
    } on FileSystemException {
      return null;
    }
  }

  @override
  void save(String name, String content) {
    try {
      if (!_cacheDir.existsSync()) _cacheDir.createSync(recursive: true);
      _file(name).writeAsStringSync(content, flush: true);
    } on FileSystemException {
      // 缓存写失败不影响运行，下次重新下载
    }
  }

  @override
  void saveBytecode(String name, Uint8List bytecode) {
    try {
      if (!_cacheDir.existsSync()) _cacheDir.createSync(recursive: true);
      _bcFile(name).writeAsBytesSync(bytecode, flush: true);
    } on FileSystemException {
      // 同上
    }
  }

  @override
  Uint8List? loadBytecode(String name) {
    final f = _bcFile(name);
    if (!f.existsSync()) return null;
    try {
      return f.readAsBytesSync();
    } on FileSystemException {
      return null;
    }
  }
}
