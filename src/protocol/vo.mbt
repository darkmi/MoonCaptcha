///|
/// get 接口的 repData 组装（对齐 CaptchaVO 的序列化字段）。
pub(all) struct GetResponse {
  /// blockPuzzle / clickWord
  captcha_type : String
  /// 底图 Base64（blockPuzzle 为 JPG，clickWord 为 PNG）
  original_image_base64 : String
  /// 滑块小图 Base64（PNG，仅 blockPuzzle）
  jigsaw_image_base64 : String
  /// 需按序点击的文字（仅 clickWord）
  word_list : Array[String]?
  /// 验证码令牌（32 位无连字符 UUID）
  token : String
  /// AES 密钥（aes 关闭时为空串）
  secret_key : String
}

///|
pub fn GetResponse::to_json(self : GetResponse) -> String {
  let buf = StringBuilder()
  buf.write_string("{\"captchaType\":")
  buf.write_string(@common.json_escape_string(self.captcha_type))
  buf.write_string(",\"originalImageBase64\":")
  buf.write_string(@common.json_escape_string(self.original_image_base64))
  if self.captcha_type == "blockPuzzle" {
    buf.write_string(",\"jigsawImageBase64\":")
    buf.write_string(@common.json_escape_string(self.jigsaw_image_base64))
  }
  match self.word_list {
    Some(words) => {
      buf.write_string(",\"wordList\":[")
      for i, w in words {
        if i > 0 {
          buf.write_char(',')
        }
        buf.write_string(@common.json_escape_string(w))
      }
      buf.write_string("]")
    }
    None => ()
  }
  buf.write_string(",\"token\":")
  buf.write_string(@common.json_escape_string(self.token))
  buf.write_string(",\"secretKey\":")
  buf.write_string(@common.json_escape_string(self.secret_key))
  buf.write_string("}")
  buf.to_string()
}

///|
/// check 成功时的 repData（对齐 Java 返回的 captchaVO 片段）。
pub fn check_success_data(captcha_type : String, token : String) -> String {
  let buf = StringBuilder()
  buf.write_string("{\"captchaType\":")
  buf.write_string(@common.json_escape_string(captcha_type))
  buf.write_string(",\"token\":")
  buf.write_string(@common.json_escape_string(token))
  buf.write_string(",\"result\":true}")
  buf.to_string()
}
