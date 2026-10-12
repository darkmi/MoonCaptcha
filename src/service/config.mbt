///|
/// 验证码配置，默认值对齐 AJ-Captcha 的 AjCaptchaProperties / AbstractCaptchaService。
pub(all) struct CaptchaConfig {
  /// 滑动 x 容差（aj.captcha.slip-offset，默认 5）
  slip_offset : Int
  /// AES 加密开关（aj.captcha.aes-status，默认 true）
  aes_enabled : Bool
  /// 验证码坐标缓存 TTL（默认 120 秒）
  expires_in_seconds : Int64
  /// 二次校验凭证缓存 TTL（默认 180 秒）
  second_expires_in_seconds : Int64
  /// 点选字号，同时是点击容差（aj.captcha.font-size，默认 25）
  han_zi_size : Int
  /// 点选绘制字数，点击字数 = word_total_count - 1（aj.captcha.word-count，默认 4）
  word_total_count : Int
  /// 滑动干扰项 0/1/2（aj.captcha.interference-options，默认 0；M5 起生效）
  interference_options : Int
  /// 右下角水印文字（aj.captcha.water-mark，默认"我的水印"；空串关闭）
  water_mark : String
}

///|
pub fn CaptchaConfig::default() -> CaptchaConfig {
  {
    slip_offset: 5,
    aes_enabled: true,
    expires_in_seconds: 120L,
    second_expires_in_seconds: 180L,
    han_zi_size: 25,
    word_total_count: 4,
    interference_options: 0,
    water_mark: "我的水印",
  }
}

///|
/// check 阶段验证码缓存 key：RUNNING:CAPTCHA:{token}
pub fn captcha_key(token : String) -> String {
  "RUNNING:CAPTCHA:" + token
}

///|
/// verification 阶段二次校验缓存 key：RUNNING:CAPTCHA:second-{captchaVerification}
pub fn second_captcha_key(captcha_verification : String) -> String {
  "RUNNING:CAPTCHA:second-" + captcha_verification
}
