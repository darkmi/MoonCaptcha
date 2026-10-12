///|
/// 滑动拼图（blockPuzzle）服务逻辑。
/// 逐条对照 BlockPuzzleCaptchaServiceImpl 移植，协议细节见 docs/aj-captcha-analysis.md §5。
/// 图像抠图见 image 包；本文件只负责坐标生成、校验与令牌生命周期。

///|
/// 随机生成拼图坐标，对齐 generateJigsawPoint：
/// - x ∈ [200, width - jigsawWidth - 200)
/// - y：height - jigsawHeight <= 0 时恒为 5（标准 155 高底图 + 310 高模板的既有约定，
///   前端组件硬编码提交 y=5.0）
/// - aes 开启时生成 16 位随机密钥
/// 修正：width 不足时 Java 会因 nextInt(负数) 抛异常，这里回退 x = 5。
pub fn generate_jigsaw_point(
  rng : @common.Rng,
  width : Int,
  height : Int,
  jigsaw_width : Int,
  jigsaw_height : Int,
  aes_enabled : Bool,
) -> @protocol.Point {
  let secret_key = if aes_enabled { rng.random_string(16) } else { "" }
  let x = if width - jigsaw_width <= 0 {
    5
  } else {
    let bound = width - jigsaw_width - 200
    if bound <= 0 {
      5
    } else {
      200 + rng.next_bounded(bound)
    }
  }
  let y = if height - jigsaw_height <= 0 {
    5
  } else {
    5 + rng.next_bounded(height - jigsaw_height)
  }
  @protocol.Point::make(x, y, secret_key)
}

///|
/// get 流程的存储步骤：图像由集成层生成后，把坐标写入缓存（TTL 120s）。
pub fn block_puzzle_store(
  config : CaptchaConfig,
  cache : &@cache.Cache,
  token : String,
  point : @protocol.Point,
) -> Unit {
  cache.set(
    captcha_key(token),
    point.to_captcha_json(),
    config.expires_in_seconds,
  )
}

///|
/// check 流程，对齐 BlockPuzzleCaptchaServiceImpl#check：
/// 1. token 查缓存，**取出后立即删除**（一次性）
/// 2. 用存储的 secretKey 解密前端 pointJson
/// 3. 比较：|Δx| ≤ slip_offset 且 y 严格相等（坐标均截断为 int）
/// 4. 通过后生成 captchaVerification = AES(token---pointJson) 存缓存（TTL 180s）
pub fn block_puzzle_check(
  config : CaptchaConfig,
  cache : &@cache.Cache,
  token : String,
  point_json : String,
) -> @protocol.ResponseModel {
  let key = captcha_key(token)
  let stored = match cache.get(key) {
    Some(s) => s
    None => return @protocol.ResponseModel::error(@protocol.ApiCaptchaInvalid)
  }
  // 验证码只用一次，即刻失效
  cache.delete(key)
  let point = match @protocol.Point::parse_captcha_json(stored) {
    Ok(p) => p
    Err(_) =>
      return @protocol.ResponseModel::error_msg(
        Error,
        "验证码坐标解析失败",
      )
  }
  let user_json = match @crypto.aes_decrypt(point_json, point.secret_key()) {
    Some(s) => s
    None =>
      return @protocol.ResponseModel::error_msg(
        Error,
        "验证码坐标解析失败",
      )
  }
  let user_point = match @protocol.Point::parse_captcha_json(user_json) {
    Ok(p) => p
    Err(_) =>
      return @protocol.ResponseModel::error_msg(
        Error,
        "验证码坐标解析失败",
      )
  }
  let offset = config.slip_offset
  if point.x() - offset > user_point.x() ||
    user_point.x() > point.x() + offset ||
    point.y() != user_point.y() {
    return @protocol.ResponseModel::error(@protocol.ApiCaptchaCoordinateError)
  }
  store_second_verification(
    config,
    cache,
    token,
    user_json,
    point.secret_key(),
    "blockPuzzle",
  )
}

///|
/// check 成功后的共用收尾：生成二次校验凭证并写入缓存，返回成功响应。
/// 明文为 token + "---" + 解密后的 pointJson 原串（不得重新序列化）。
fn store_second_verification(
  config : CaptchaConfig,
  cache : &@cache.Cache,
  token : String,
  point_json : String,
  secret_key : String,
  captcha_type : String,
) -> @protocol.ResponseModel {
  let verification = match
    @crypto.aes_encrypt(token + "---" + point_json, secret_key) {
    Some(v) => v
    None => return @protocol.ResponseModel::error_msg(Error, "AES加密失败")
  }
  cache.set(
    second_captcha_key(verification),
    token,
    config.second_expires_in_seconds,
  )
  @protocol.ResponseModel::success_data(
    @protocol.check_success_data(captcha_type, token),
  )
}

///|
/// verification 流程（业务后端二次校验），对齐 BlockPuzzleCaptchaServiceImpl#verification：
/// 凭证存在即通过，**取出后立即删除**（防重放）。
pub fn block_puzzle_verification(
  config : CaptchaConfig,
  cache : &@cache.Cache,
  captcha_verification : String,
) -> @protocol.ResponseModel {
  verification(config, cache, captcha_verification)
}

///|
/// verification 的共用实现（blockPuzzle 与 clickWord 完全一致）。
pub fn verification(
  config : CaptchaConfig,
  cache : &@cache.Cache,
  captcha_verification : String,
) -> @protocol.ResponseModel {
  let _ = config
  if captcha_verification.length() == 0 {
    return @protocol.ResponseModel::blank_error("captchaVerification")
  }
  let key = second_captcha_key(captcha_verification)
  if !cache.exists(key) {
    return @protocol.ResponseModel::error(@protocol.ApiCaptchaInvalid)
  }
  // 二次校验取值后，即刻失效
  cache.delete(key)
  @protocol.ResponseModel::success()
}
