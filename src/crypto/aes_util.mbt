///|
/// 字符串级 AES 工具，对齐 AJ-Captcha 的 AESUtil：
/// - AES/ECB/PKCS5Padding（PKCS5 与 PKCS7 在 16 字节块下等价）
/// - 密钥为 16 字符 UTF-8 串（AJ-Captcha 生成 16 位字母数字随机串）
/// - 密钥为空时明文直通（对应 captcha.aes.status=false）
/// - 输出/输入为标准 Base64
/// 失败一律返回 None（Java 侧为抛异常，服务层统一按校验失败处理）。

///|
/// AES 加密并 Base64 编码。key 为空 → 原文直通；密钥非法 → None。
pub fn aes_encrypt(content : String, key : String) -> String? {
  if key.length() == 0 {
    return Some(content)
  }
  let key_bytes = @common.utf8_encode(key)
  let content_bytes = @common.utf8_encode(content)
  match aes128_ecb_encrypt(content_bytes, key_bytes) {
    Some(encrypted) => Some(@common.base64_encode(encrypted))
    None => None
  }
}

///|
/// Base64 解码并 AES 解密。key 为空 → 原文直通；任一环节失败 → None。
pub fn aes_decrypt(encrypted : String, key : String) -> String? {
  if key.length() == 0 {
    return Some(encrypted)
  }
  let data = match @common.base64_decode(encrypted) {
    Some(d) => d
    None => return None
  }
  let key_bytes = @common.utf8_encode(key)
  match aes128_ecb_decrypt(data, key_bytes) {
    Some(plain) => Some(@common.utf8_decode(plain))
    None => None
  }
}
