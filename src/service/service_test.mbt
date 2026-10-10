///|
/// 可控假时钟（毫秒）。
priv struct FakeClock {
  mut now : Int64
}

///|
fn FakeClock::make() -> FakeClock {
  { now: 1_000_000L }
}

///|
fn FakeClock::now_ms(self : FakeClock) -> Int64 {
  self.now
}

///|
fn FakeClock::advance(self : FakeClock, seconds : Int64) -> Unit {
  self.now = self.now + seconds * 1000L
}

///|
fn make_service_cache(clock : FakeClock) -> @cache.MemoryCache {
  let c : @cache.MemoryCache = @cache.MemoryCache::new(fn() { clock.now_ms() })
  c
}

///|
test "generate_jigsaw_point standard background y is 5" {
  // 标准 310x155 底图 + 94x310 模板：y 恒为 5（前端硬编码 y:5.0 的由来）
  let rng = @common.Rng::new(1UL)
  for _i in 0..<100 {
    let p = @service.generate_jigsaw_point(rng, 310, 155, 94, 310, true)
    assert_true(p.y() == 5)
    assert_true(p.x() >= 200 && p.x() < 310 - 94 - 200 + 200)
    assert_true(p.secret_key().length() == 16)
  }
}

///|
test "generate_jigsaw_point aes disabled gives empty key" {
  let rng = @common.Rng::new(2UL)
  let p = @service.generate_jigsaw_point(rng, 310, 155, 94, 310, false)
  assert_true(p.secret_key() == "")
}

///|
test "generate_jigsaw_point tall background randomizes y" {
  let rng = @common.Rng::new(3UL)
  let mut saw_different_y = false
  let first_y = @service.generate_jigsaw_point(rng, 600, 400, 94, 310, false).y()
  for _i in 0..<50 {
    let y = @service.generate_jigsaw_point(rng, 600, 400, 94, 310, false).y()
    if y != first_y {
      saw_different_y = true
    }
    assert_true(y >= 5 && y < 400 - 310 + 5)
  }
  assert_true(saw_different_y)
}

///|
test "generate_jigsaw_point small width falls back to x=5" {
  // 修正项：Java 在 width <= jigsawWidth + 200 时会因 nextInt(负数) 抛异常
  let rng = @common.Rng::new(4UL)
  let p = @service.generate_jigsaw_point(rng, 250, 155, 94, 310, false)
  assert_true(p.x() == 5)
}

///|
test "block_puzzle full flow success" {
  let clock = FakeClock::make()
  let cache = make_service_cache(clock)
  let config = @service.CaptchaConfig::default()
  let rng = @common.Rng::new(5UL)
  let point = @service.generate_jigsaw_point(rng, 310, 155, 94, 310, true)
  let token = rng.uuid()
  @service.block_puzzle_store(config, cache, token, point)
  // 前端提交 AES(JSON.stringify({x: moveLeftDistance, y: 5.0}))，x 为实际坐标
  let user_json = "{\"x\": " + point.x().to_string() + ", \"y\": 5.0}"
  let point_json = match @crypto.aes_encrypt(user_json, point.secret_key()) {
    Some(v) => v
    None => abort("unreachable")
  }
  let resp = @service.block_puzzle_check(config, cache, token, point_json)
  assert_true(resp.is_success())
  // 二次校验通过
  let verification = match @crypto.aes_encrypt(token + "---" + user_json, point.secret_key()) {
    Some(v) => v
    None => abort("unreachable")
  }
  let vresp = @service.block_puzzle_verification(config, cache, verification)
  assert_true(vresp.is_success())
  // 防重放：二次校验凭证只能用一次
  let replay = @service.block_puzzle_verification(config, cache, verification)
  assert_true(replay.rep_code() == @protocol.ApiCaptchaInvalid.code())
}

///|
test "block_puzzle check x out of tolerance" {
  let clock = FakeClock::make()
  let cache = make_service_cache(clock)
  let config = @service.CaptchaConfig::default()
  let rng = @common.Rng::new(6UL)
  let point = @service.generate_jigsaw_point(rng, 310, 155, 94, 310, true)
  let token = rng.uuid()
  @service.block_puzzle_store(config, cache, token, point)
  // x 偏差 6 > 容差 5
  let actual_x = point.x()
  let user_json = "{\"x\": \{actual_x + 6}, \"y\": 5.0}"
  let point_json = match @crypto.aes_encrypt(user_json, point.secret_key()) {
    Some(v) => v
    None => abort("unreachable")
  }
  let resp = @service.block_puzzle_check(config, cache, token, point_json)
  assert_true(resp.rep_code() == @protocol.ApiCaptchaCoordinateError.code())
}

///|
test "block_puzzle check y must match exactly" {
  let clock = FakeClock::make()
  let cache = make_service_cache(clock)
  let config = @service.CaptchaConfig::default()
  let rng = @common.Rng::new(7UL)
  let point = @service.generate_jigsaw_point(rng, 310, 155, 94, 310, true)
  let token = rng.uuid()
  @service.block_puzzle_store(config, cache, token, point)
  let actual_x = point.x()
  let user_json = "{\"x\": \{actual_x}, \"y\": 6.0}"
  let point_json = match @crypto.aes_encrypt(user_json, point.secret_key()) {
    Some(v) => v
    None => abort("unreachable")
  }
  let resp = @service.block_puzzle_check(config, cache, token, point_json)
  assert_true(resp.rep_code() == @protocol.ApiCaptchaCoordinateError.code())
}

///|
test "block_puzzle check token single use" {
  let clock = FakeClock::make()
  let cache = make_service_cache(clock)
  let config = @service.CaptchaConfig::default()
  let rng = @common.Rng::new(8UL)
  let point = @service.generate_jigsaw_point(rng, 310, 155, 94, 310, true)
  let token = rng.uuid()
  @service.block_puzzle_store(config, cache, token, point)
  let actual_x = point.x()
  let user_json = "{\"x\": \{actual_x}, \"y\": 5.0}"
  let point_json = match @crypto.aes_encrypt(user_json, point.secret_key()) {
    Some(v) => v
    None => abort("unreachable")
  }
  let first = @service.block_puzzle_check(config, cache, token, point_json)
  assert_true(first.is_success())
  // 同一 token 第二次 check → 6110
  let second = @service.block_puzzle_check(config, cache, token, point_json)
  assert_true(second.rep_code() == @protocol.ApiCaptchaInvalid.code())
}

///|
test "block_puzzle check expired token" {
  let clock = FakeClock::make()
  let cache = make_service_cache(clock)
  let config = @service.CaptchaConfig::default()
  let rng = @common.Rng::new(9UL)
  let point = @service.generate_jigsaw_point(rng, 310, 155, 94, 310, true)
  let token = rng.uuid()
  @service.block_puzzle_store(config, cache, token, point)
  // 超过 120s TTL
  clock.advance(121L)
  let actual_x = point.x()
  let user_json = "{\"x\": \{actual_x}, \"y\": 5.0}"
  let point_json = match @crypto.aes_encrypt(user_json, point.secret_key()) {
    Some(v) => v
    None => abort("unreachable")
  }
  let resp = @service.block_puzzle_check(config, cache, token, point_json)
  assert_true(resp.rep_code() == @protocol.ApiCaptchaInvalid.code())
}

///|
test "block_puzzle check with wrong aes key fails" {
  let clock = FakeClock::make()
  let cache = make_service_cache(clock)
  let config = @service.CaptchaConfig::default()
  let rng = @common.Rng::new(10UL)
  let point = @service.generate_jigsaw_point(rng, 310, 155, 94, 310, true)
  let token = rng.uuid()
  @service.block_puzzle_store(config, cache, token, point)
  // 用错误密钥加密 → 解密失败 → 0001
  let point_json = match @crypto.aes_encrypt("{\"x\": 210, \"y\": 5.0}", "wrongkey12345678") {
    Some(v) => v
    None => abort("unreachable")
  }
  let resp = @service.block_puzzle_check(config, cache, token, point_json)
  assert_true(resp.rep_code() == @protocol.Error.code())
}

///|
test "block_puzzle check aes disabled passthrough" {
  let clock = FakeClock::make()
  let cache = make_service_cache(clock)
  let config : @service.CaptchaConfig = { ..@service.CaptchaConfig::default(), aes_enabled: false }
  let rng = @common.Rng::new(11UL)
  let point = @service.generate_jigsaw_point(rng, 310, 155, 94, 310, false)
  let token = rng.uuid()
  @service.block_puzzle_store(config, cache, token, point)
  let actual_x = point.x()
  let user_json = "{\"x\": \{actual_x}, \"y\": 5.0}"
  // 密钥为空 → 明文直通
  let resp = @service.block_puzzle_check(config, cache, token, user_json)
  assert_true(resp.is_success())
  // 二次校验凭证同样明文直通
  let vresp = @service.block_puzzle_verification(config, cache, token + "---" + user_json)
  assert_true(vresp.is_success())
}

///|
test "verification requires non-empty captchaVerification" {
  let clock = FakeClock::make()
  let cache = make_service_cache(clock)
  let resp = @service.verification(@service.CaptchaConfig::default(), cache, "")
  assert_true(resp.rep_code() == @protocol.BlankError.code())
}

///|
test "click word full flow success" {
  let clock = FakeClock::make()
  let cache = make_service_cache(clock)
  let config = @service.CaptchaConfig::default()
  let rng = @common.Rng::new(12UL)
  let (word_list, point_list) = @service.generate_click_word_data(rng, 310, 155, config)
  // 默认绘制 4 字、点击 3 字
  assert_true(word_list.length() == 3)
  assert_true(point_list.length() == 3)
  let token = rng.uuid()
  @service.click_word_store(config, cache, token, point_list)
  // 前端按顺序点击：提交坐标数组（模拟精确点击）
  let clicked : Array[@protocol.Point] = []
  for p in point_list {
    let p : @protocol.Point = @protocol.Point::make(p.x() + 2, p.y() - 3, "")
    clicked.push(p)
  }
  let clicked_json = @protocol.Point::list_to_captcha_json(clicked)
  let point_json = match @crypto.aes_encrypt(clicked_json, point_list[0].secret_key()) {
    Some(v) => v
    None => abort("unreachable")
  }
  let resp = @service.click_word_check(config, cache, token, point_json)
  assert_true(resp.is_success())
  // 二次校验
  let verification = match @crypto.aes_encrypt(token + "---" + clicked_json, point_list[0].secret_key()) {
    Some(v) => v
    None => abort("unreachable")
  }
  assert_true(@service.click_word_verification(config, cache, verification).is_success())
}

///|
test "click word wrong order fails" {
  let clock = FakeClock::make()
  let cache = make_service_cache(clock)
  let config = @service.CaptchaConfig::default()
  let rng = @common.Rng::new(13UL)
  let (_word_list, point_list) = @service.generate_click_word_data(rng, 310, 155, config)
  let token = rng.uuid()
  @service.click_word_store(config, cache, token, point_list)
  // 逆序点击
  let clicked : Array[@protocol.Point] = []
  for i in 0..<point_list.length() {
    let p = point_list[point_list.length() - 1 - i]
    clicked.push(@protocol.Point::make(p.x(), p.y(), ""))
  }
  let clicked_json = @protocol.Point::list_to_captcha_json(clicked)
  let point_json = match @crypto.aes_encrypt(clicked_json, point_list[0].secret_key()) {
    Some(v) => v
    None => abort("unreachable")
  }
  let resp = @service.click_word_check(config, cache, token, point_json)
  // 容差 25px 内逆序可能恰好命中（重合点），这里断言不通过或坐标错误
  assert_true(!resp.is_success())
}

///|
test "click word click count insufficient" {
  let clock = FakeClock::make()
  let cache = make_service_cache(clock)
  let config = @service.CaptchaConfig::default()
  let rng = @common.Rng::new(14UL)
  let (_word_list, point_list) = @service.generate_click_word_data(rng, 310, 155, config)
  let token = rng.uuid()
  @service.click_word_store(config, cache, token, point_list)
  // 只点了一个
  let clicked = [point_list[0]]
  let clicked_json = @protocol.Point::list_to_captcha_json(clicked)
  let point_json = match @crypto.aes_encrypt(clicked_json, point_list[0].secret_key()) {
    Some(v) => v
    None => abort("unreachable")
  }
  let resp = @service.click_word_check(config, cache, token, point_json)
  assert_true(resp.rep_code() == @protocol.Error.code())
}

///|
test "click word points stay in bounds and columns spread" {
  let rng = @common.Rng::new(15UL)
  let config = @service.CaptchaConfig::default()
  for _i in 0..<100 {
    let (_words, points) = @service.generate_click_word_data(rng, 310, 155, config)
    for j, p in points {
      assert_true(p.x() > 0 && p.x() < 310)
      assert_true(p.y() >= 25 && p.y() < 155 - 25)
      if j > 0 {
        // 分列布点：x 随列号递增区间
        assert_true(p.x() > points[j - 1].x())
      }
    }
  }
}

///|
test "click word tolerance boundary" {
  let clock = FakeClock::make()
  let cache = make_service_cache(clock)
  let config = @service.CaptchaConfig::default()
  let rng = @common.Rng::new(16UL)
  let (_word_list, point_list) = @service.generate_click_word_data(rng, 310, 155, config)
  let token = rng.uuid()
  @service.click_word_store(config, cache, token, point_list)
  // 恰好偏移容差 25px：边界可接受（Java 条件为严格大于才失败）
  let clicked : Array[@protocol.Point] = []
  for p in point_list {
    clicked.push(@protocol.Point::make(p.x() + 25, p.y() + 25, ""))
  }
  let clicked_json = @protocol.Point::list_to_captcha_json(clicked)
  let point_json = match @crypto.aes_encrypt(clicked_json, point_list[0].secret_key()) {
    Some(v) => v
    None => abort("unreachable")
  }
  let resp = @service.click_word_check(config, cache, token, point_json)
  assert_true(resp.is_success())
}
