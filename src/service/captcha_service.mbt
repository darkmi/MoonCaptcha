///|
/// 验证码类型。
pub(all) enum CaptchaKind {
  BlockPuzzle
  ClickWord
}

///|
pub fn CaptchaKind::parse(text : String) -> CaptchaKind? {
  match text {
    "blockPuzzle" => Some(BlockPuzzle)
    "clickWord" => Some(ClickWord)
    _ => None
  }
}

///|
pub fn CaptchaKind::code(self : CaptchaKind) -> String {
  match self {
    BlockPuzzle => "blockPuzzle"
    ClickWord => "clickWord"
  }
}

///|
/// 门面层错误。get 阶段的结构化失败；check/verify 走协议层 ResponseModel。
pub enum CaptchaError {
  /// 底图/滑块模板/点选底图未就绪（6113）
  BasemapMissing
  /// 频控命中（6201/6202/6204/6205），携带具体应答码与文案
  RateLimited(@protocol.RepCode)
}

///|
pub fn CaptchaError::rep_code(self : CaptchaError) -> @protocol.RepCode {
  match self {
    BasemapMissing => @protocol.ApiCaptchaBasemapNull
    RateLimited(code) => code
  }
}

///|
pub fn CaptchaError::message(self : CaptchaError) -> String {
  self.rep_code().message()
}

///|
/// 转为协议响应（集成层可直接作为 HTTP 应答体）。
pub fn CaptchaError::to_response(
  self : CaptchaError,
) -> @protocol.ResponseModel {
  @protocol.ResponseModel::error(self.rep_code())
}

///|
/// 验证码服务门面：收拢配置/资源池/字体/随机源/频控配置，
/// 与 AJ-Captcha 的 CaptchaService 接口同名同构（get / check / verification）。
///
/// - 随机源默认取自安全熵（common#secure_seed，跨平台 CSPRNG；熵不可用
///   时时间混淆降级）；确定性测试用 `with_rng` 注入固定种子
/// - 频控默认开启（RateLimitConfig::default，120/600/600、失败 5 次锁 300s），
///   上限设为 ≤0 关闭对应限制；client_id 为空跳过限制（对齐 AJ）
/// - client_id 建议由集成层以服务端可得的稳定标识计算（如 MD5(ip+UA)）；
///   库内不引入 MD5 依赖，故不代算
pub struct CaptchaService {
  config : CaptchaConfig
  pool : @image.ImagePool
  mut font : @image.Font?
  rng : @common.Rng
  limits : RateLimitConfig
}

///|
/// 以安全随机源构造（生产推荐）。
pub fn CaptchaService::new(
  pool : @image.ImagePool,
  config? : CaptchaConfig = CaptchaConfig::default(),
  font? : @image.Font? = None,
  limits? : RateLimitConfig = RateLimitConfig::default(),
) -> CaptchaService {
  CaptchaService::with_rng(
    pool,
    @common.Rng::from_secure_source(),
    config~,
    font~,
    limits~,
  )
}

///|
/// 注入确定性随机源（测试/可复现场景）。
pub fn CaptchaService::with_rng(
  pool : @image.ImagePool,
  rng : @common.Rng,
  config? : CaptchaConfig = CaptchaConfig::default(),
  font? : @image.Font? = None,
  limits? : RateLimitConfig = RateLimitConfig::default(),
) -> CaptchaService {
  { config, pool, font, rng, limits, }
}

///|
/// 更新字体（热替换）。
pub fn CaptchaService::set_font(
  self : CaptchaService,
  font : @image.Font?,
) -> Unit {
  self.font = font
}

///|
/// 获取验证码。频控通过后按类型分发生成；client_id 为空跳过频控。
pub fn CaptchaService::get(
  self : CaptchaService,
  cache : &@cache.Cache,
  kind : CaptchaKind,
  client_id? : String = "",
) -> Result[@protocol.GetResponse, CaptchaError] {
  match rate_limit_get(self.limits, cache, client_id) {
    Some(code) => return Err(CaptchaError::RateLimited(code))
    None => ()
  }
  match kind {
    BlockPuzzle =>
      match
        get_block_puzzle(self.config, self.rng, self.pool, cache, self.font) {
        Ok(resp) => Ok(resp)
        Err(_) => Err(CaptchaError::BasemapMissing)
      }
    ClickWord =>
      match get_click_word(self.config, self.rng, self.pool, cache, self.font) {
        Ok(resp) => Ok(resp)
        Err(_) => Err(CaptchaError::BasemapMissing)
      }
  }
}

///|
/// 核对验证码（前端交互提交）。坐标不匹配时自动累计失败次数
/// （滑动窗口内超过阈值将锁定 get）。
pub fn CaptchaService::check(
  self : CaptchaService,
  cache : &@cache.Cache,
  kind : CaptchaKind,
  client_id? : String = "",
  token? : String = "",
  point_json? : String = "",
) -> @protocol.ResponseModel {
  match rate_limit_check(self.limits, cache, client_id) {
    Some(code) => return @protocol.ResponseModel::error(code)
    None => ()
  }
  let resp = match kind {
    BlockPuzzle => block_puzzle_check(self.config, cache, token, point_json)
    ClickWord => click_word_check(self.config, cache, token, point_json)
  }
  if resp.rep_code() == @protocol.ApiCaptchaCoordinateError.code() {
    rate_limit_record_fail(self.limits, cache, client_id)
  }
  resp
}

///|
/// 二次校验（业务后端调用；凭证一次性，防重放）。
pub fn CaptchaService::verify(
  self : CaptchaService,
  cache : &@cache.Cache,
  client_id? : String = "",
  captcha_verification? : String = "",
) -> @protocol.ResponseModel {
  match rate_limit_verify(self.limits, cache, client_id) {
    Some(code) => return @protocol.ResponseModel::error(code)
    None => ()
  }
  verification(self.config, cache, captcha_verification)
}
