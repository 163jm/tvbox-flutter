import 'dart:typed_data';

/// 爬虫模块来源。
///
/// 对应原版 `FileUtils.loadModule`。**这个接口必须是同步的**：
/// 模块加载发生在 JS 引擎的 import 回调里，引擎在等待返回值，
/// 没有 await 的机会。因此网络下载必须在引擎初始化之前由外层完成，
/// 这里只负责读本地缓存 / assets。
abstract class ModuleSource {
  /// 返回模块内容。可能是源码，也可能是 `//bb` 或 `//DRPY` 前缀的
  /// base64 bytecode；不存在时返回 null。
  String? loadSync(String name);

  /// 保存模块内容，供下次直接命中缓存。
  void save(String name, String content);

  /// 缓存已编译的字节码，避免每次启动都重新编译 cheerio（680KB）。
  void saveBytecode(String name, Uint8List bytecode);

  Uint8List? loadBytecode(String name);
}

/// 模块内容有效性判定。
///
/// 严格对齐原版 `JsSpider.isInvalidModuleContent`：站点把 404 页面当
/// 模块返回是家常便饭，不做这层判定会在引擎里抛出难以理解的语法错误。
bool isInvalidModuleContent(String? content) {
  if (content == null || content.isEmpty) return true;
  var trim = content.trim();
  // 去掉 UTF-8 BOM
  if (trim.startsWith('\uFEFF')) trim = trim.substring(1).trim();
  final lower = trim.toLowerCase();
  return lower.startsWith('<') ||
      lower.startsWith('{"code":404') ||
      lower.startsWith('404') ||
      lower.startsWith('not found');
}

/// 把 `//bb` 编码的 bytecode 转成引擎可直接读取的格式。
///
/// 对齐原版 `JsSpider.byteFF`：丢弃前 4 个字节的头部，
/// 首字节置 1（JS_READ_OBJ_BYTECODE 标志）。
Uint8List decodeBbBytecode(String content) {
  final raw = content.replaceFirst('//bb', '');
  return _byteFF(base64UrlSafeToBytes(raw));
}

/// 把 `//DRPY` 编码的 bytecode 转成引擎可读格式（已是完整 bytecode）。
Uint8List decodeDrpyBytecode(String content) =>
    base64UrlSafeToBytes(content.replaceFirst('//DRPY', ''));

Uint8List _byteFF(List<int> bytes) {
  final out = Uint8List(bytes.length - 4);
  out[0] = 1;
  out.setRange(1, out.length, bytes, 5);
  return out;
}

/// base64 解码，兼容标准与 URL-safe 两种字母表，并容忍缺失 padding。
Uint8List base64UrlSafeToBytes(String input) {
  var s = input.replaceAll(RegExp(r'\s'), '').replaceAll('-', '+').replaceAll('_', '/');
  final remainder = s.length % 4;
  if (remainder != 0) s += '=' * (4 - remainder);
  const table =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  final out = <int>[];
  var buffer = 0;
  var bits = 0;
  for (var i = 0; i < s.length; i++) {
    final c = s[i];
    if (c == '=') break;
    final v = table.indexOf(c);
    if (v < 0) continue;
    buffer = (buffer << 6) | v;
    bits += 6;
    if (bits >= 8) {
      bits -= 8;
      out.add((buffer >> bits) & 0xFF);
    }
  }
  return Uint8List.fromList(out);
}
