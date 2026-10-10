///|
/// 应答码，与 AJ-Captcha 的 RepCodeEnum 一一对应。
pub(all) enum RepCode {
  Success
  Error
  Exception
  BlankError
  ApiCaptchaInvalid
  ApiCaptchaCoordinateError
  ApiCaptchaError
  ApiCaptchaBasemapNull
  ApiReqLimitGetError
  ApiReqLockGetError
  ApiReqLimitCheckError
  ApiReqLimitVerifyError
  ApiReqInvalid
}

///|
/// 应答码字符串，与 Java 版完全一致。
pub fn RepCode::code(self : RepCode) -> String {
  match self {
    Success => "0000"
    Error => "0001"
    Exception => "9999"
    BlankError => "0011"
    ApiCaptchaInvalid => "6110"
    ApiCaptchaCoordinateError => "6111"
    ApiCaptchaError => "6112"
    ApiCaptchaBasemapNull => "6113"
    ApiReqLimitGetError => "6201"
    ApiReqLockGetError => "6202"
    ApiReqLimitCheckError => "6204"
    ApiReqLimitVerifyError => "6205"
    ApiReqInvalid => "6206"
  }
}

///|
/// 默认描述文案（中文，与 Java 版一致）。
pub fn RepCode::message(self : RepCode) -> String {
  match self {
    Success => "成功"
    Error => "操作失败"
    Exception => "服务器内部异常"
    BlankError => "{0}不能为空"
    ApiCaptchaInvalid => "验证码已失效，请重新获取"
    ApiCaptchaCoordinateError => "验证失败"
    ApiCaptchaError => "获取验证码失败,请联系管理员"
    ApiCaptchaBasemapNull => "底图未初始化成功，请检查路径"
    ApiReqLimitGetError => "get接口请求次数超限，请稍后再试!"
    ApiReqLockGetError => "接口验证失败数过多，请稍后再试"
    ApiReqLimitCheckError => "check接口请求次数超限，请稍后再试!"
    ApiReqLimitVerifyError => "verify请求次数超限!"
    ApiReqInvalid => "无效请求，请重新获取验证码"
  }
}

///|
pub fn RepCode::is_success(self : RepCode) -> Bool {
  match self {
    Success => true
    _ => false
  }
}
