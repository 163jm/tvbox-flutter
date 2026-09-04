/// JS 侧加解密能力，对应原版 `util/js/Crypto.java` 与 `util/js/rsa/RSAEncrypt.java`。
///
/// 这些函数是爬虫做签名、破解接口加密的常用手段，参数必须与参考实现
/// 严格对齐——尤其是 base64 进出与分段的默认值，差一个参数结果就完全不同。
abstract class JsCrypto {
  /// AES。对应 `aesX(mode, encrypt, input, inBase64, key, iv, outBase64)`。
  ///
  /// [mode] 形如 `CBC` / `ECB` / `CTR`；
  /// [inBase64] / [outBase64] 控制输入输出是否为 base64。
  String aes(
    String mode,
    bool encrypt,
    String input,
    bool inBase64,
    String key,
    String iv,
    bool outBase64,
  );

  /// RSA。对应 `rsaX(mode, pub, encrypt, input, inBase64, key, outBase64)`。
  String rsa(
    String mode,
    bool pub,
    bool encrypt,
    String input,
    bool inBase64,
    String key,
    bool outBase64,
  );

  /// RSA 加密，对应 `rsaEncrypt(data, key, options)`。
  ///
  /// [type] 1=公钥加密私钥解密，2=私钥加密公钥解密；
  /// [long] 1=普通，2=分段；
  /// [block] 为 true 时分段长度自动，为 false 时固定 117；
  /// [config] 默认 `RSA/ECB/PKCS1Padding`。
  String rsaEncrypt(
    String data,
    String key, {
    int type = 1,
    int long = 1,
    bool block = true,
    String? config,
  });

  /// RSA 解密，对应 `rsaDecrypt(data, key, options)`。
  /// [block] 为 false 时分段长度固定 128。
  String rsaDecrypt(
    String data,
    String key, {
    int type = 1,
    int long = 1,
    bool block = true,
    String? config,
  });

  /// MD5，原版 `MD5.encode` 在部分爬虫里被直接调用。
  String md5(String input);
}
