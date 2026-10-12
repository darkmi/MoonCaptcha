///|
/// 接口频控：对齐 AJ-Captcha 的 FrequencyLimitHandler.DefaultLimitHandler
/// 语义并修复其缺陷（设计决策见迁移设计 §4.6/§8.2）：
/// - get：每分钟 ≤ get_minute_limit 次（默认 120）
/// - check：每分钟 ≤ check_minute_limit 次（默认 600）
/// - verify：每分钟 ≤ verify_minute_limit 次（默认 600）
/// - check 失败累计 > fail_lock_threshold（默认 5）→ get 锁定 fail_lock_seconds（默认 300s）
/// 与 Java 版的差异：
/// - **默认开启**（类库分发安全底线；上限设为 ≤0 表示关闭该限制）
/// - 计数采用**滑动窗口**：每次请求都重设 TTL，修复 Java increment 键
///   永不过期导致计数残留的缺陷
/// - client_id 由集成层计算（如 MD5(ip+UA)），为空则不做限制（对齐 AJ）
pub(all) struct RateLimitConfig {
  get_minute_limit : Int
  check_minute_limit : Int
  verify_minute_limit : Int
  fail_lock_threshold : Int
  fail_lock_seconds : Int64
}

///|
pub fn RateLimitConfig::default() -> RateLimitConfig {
  {
    get_minute_limit: 120,
    check_minute_limit: 600,
    verify_minute_limit: 600,
    fail_lock_threshold: 5,
    fail_lock_seconds: 300L,
  }
}

///|
/// 频控命中的应答码（6201/6202/6204/6205），None 表示放行。
pub fn rate_limit_get(
  limits : RateLimitConfig,
  cache : &@cache.Cache,
  client_id : String,
) -> @protocol.RepCode? {
  if client_id.length() == 0 {
    return None
  }
  let lock_key = "MoonCaptcha:LIMIT:LOCK:" + client_id
  if cache.get(lock_key) is Some(_) {
    return Some(@protocol.ApiReqLockGetError)
  }
  if limits.get_minute_limit > 0 {
    let cnt = bump(cache, "MoonCaptcha:LIMIT:GET:" + client_id)
    if cnt > limits.get_minute_limit {
      return Some(@protocol.ApiReqLimitGetError)
    }
  }
  if limits.fail_lock_threshold > 0 {
    match cache.get("MoonCaptcha:LIMIT:FAIL:" + client_id) {
      Some(v) =>
        if parse_count(v) > limits.fail_lock_threshold {
          cache.set(lock_key, "1", limits.fail_lock_seconds)
          return Some(@protocol.ApiReqLockGetError)
        }
      None => ()
    }
  }
  None
}

///|
pub fn rate_limit_check(
  limits : RateLimitConfig,
  cache : &@cache.Cache,
  client_id : String,
) -> @protocol.RepCode? {
  if client_id.length() == 0 || limits.check_minute_limit <= 0 {
    return None
  }
  let cnt = bump(cache, "MoonCaptcha:LIMIT:CHECK:" + client_id)
  if cnt > limits.check_minute_limit {
    return Some(@protocol.ApiReqLimitCheckError)
  }
  None
}

///|
pub fn rate_limit_verify(
  limits : RateLimitConfig,
  cache : &@cache.Cache,
  client_id : String,
) -> @protocol.RepCode? {
  if client_id.length() == 0 || limits.verify_minute_limit <= 0 {
    return None
  }
  let cnt = bump(cache, "MoonCaptcha:LIMIT:VERIFY:" + client_id)
  if cnt > limits.verify_minute_limit {
    return Some(@protocol.ApiReqLimitVerifyError)
  }
  None
}

///|
/// check 失败后由门面调用，累计 60 秒滑动窗口内的失败次数。
pub fn rate_limit_record_fail(
  limits : RateLimitConfig,
  cache : &@cache.Cache,
  client_id : String,
) -> Unit {
  if client_id.length() == 0 || limits.fail_lock_threshold <= 0 {
    return
  }
  let _ = bump(cache, "MoonCaptcha:LIMIT:FAIL:" + client_id)
}

///|
/// 滑动窗口计数：每次访问都重置 TTL（窗口 = 自最近一次请求起 60 秒），
/// 修复 Java 版 increment 键永不过期的缺陷。
fn bump(cache : &@cache.Cache, key : String) -> Int {
  let cnt = match cache.get(key) {
    Some(v) => parse_count(v) + 1
    None => 1
  }
  cache.set(key, cnt.to_string(), 60L)
  cnt
}

///|
/// 十进制正整数解析（容错：非数字前缀按 0）。
fn parse_count(s : String) -> Int {
  let mut v = 0
  for c in s.iter() {
    if c >= '0' && c <= '9' {
      v = v * 10 + (c.to_int() - 48)
    } else {
      break
    }
  }
  v
}
