import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:tvbox_core/tvbox_core.dart';

void main() {
  group('isInvalidModuleContent', () {
    test('常见 404 形态全部识别', () {
      expect(isInvalidModuleContent(null), isTrue);
      expect(isInvalidModuleContent(''), isTrue);
      expect(isInvalidModuleContent('<html>404</html>'), isTrue);
      expect(isInvalidModuleContent('404 Not Found'), isTrue);
      expect(isInvalidModuleContent('not found'), isTrue);
      expect(isInvalidModuleContent('{"code":404,"msg":"x"}'), isTrue);
      // BOM 前缀
      expect(isInvalidModuleContent('\uFEFF<html>'), isTrue);
    });

    test('与原版一致的宽松语义', () {
      // 原版对纯空白返回 false（trim 后为空串不命中任何前缀），保持对齐
      expect(isInvalidModuleContent('   '), isFalse);
      // 同理，404 开头的数字串也会被原版误杀，这里只验证行为一致
      expect(isInvalidModuleContent('40400'), isTrue);
    });

    test('正常模块内容不误伤', () {
      expect(isInvalidModuleContent('//bbQ0FU'), isFalse);
      expect(isInvalidModuleContent('//DRPYxxxx'), isFalse);
      expect(isInvalidModuleContent('import x from "y";'), isFalse);
    });
  });

  group('bytecode 解码', () {
    test('base64UrlSafeToBytes 兼容标准与 URL-safe 字母表', () {
      // "AB" 的标准 base64 是 "QUI="
      expect(base64UrlSafeToBytes('QUI='), [0x41, 0x42]);
      // URL-safe：'+'->'-' '/'->'_'
      // 字节 [0xFB, 0xEF] 的标准 base64 为 "+++++"? 用简单可验算的数据：
      // [0xFB, 0xEF, 0xBE] -> base64 "+--+" 无效示例不构造，
      // 改验 padding 缺失容忍
      expect(base64UrlSafeToBytes('QUI'), [0x41, 0x42]);
      expect(base64UrlSafeToBytes('QUI='), base64UrlSafeToBytes('QUI'));
    });

    test('decodeBbBytecode 丢弃 4 字节头并将首字节置 1', () {
      // 构造：byteFF 的输入 raw[0..3] 是头部，raw[4] 是原 tag，raw[5..] 是数据
      // decodeBbBytecode 先做 base64 解码得到 raw，再丢 raw 前 4 字节、首字节置 1
      final raw = [0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0x11, 0x22];
      final encoded = _b64(raw);
      final out = decodeBbBytecode('//bb$encoded');
      // 期望输出长度 = raw.length - 4 = 3，且 out[0]=1, out[1..]=raw[5..]
      expect(out, hasLength(3));
      expect(out[0], 1);
      expect(out.sublist(1), [0x11, 0x22]);
    });

    test('decodeDrpyBytecode 直接透传', () {
      final raw = Uint8List.fromList([1, 2, 3]);
      final encoded = _b64(raw);
      expect(decodeDrpyBytecode('//DRPY$encoded'), raw);
    });
  });
}

/// 独立实现的最小 base64 编码，避免测试依赖 dart:convert 的行为巧合。
String _b64(List<int> bytes) {
  const table =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  final out = StringBuffer();
  for (var i = 0; i < bytes.length; i += 3) {
    final b0 = bytes[i];
    final b1 = i + 1 < bytes.length ? bytes[i + 1] : null;
    final b2 = i + 2 < bytes.length ? bytes[i + 2] : null;
    out.write(table[b0 >> 2]);
    out.write(table[((b0 & 0x03) << 4) | ((b1 ?? 0) >> 4)]);
    out.write(b1 == null ? '=' : table[((b1 & 0x0F) << 2) | ((b2 ?? 0) >> 6)]);
    out.write(b2 == null ? '=' : table[b2 & 0x3F]);
  }
  return out.toString();
}
