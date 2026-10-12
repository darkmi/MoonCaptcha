///|
/// M4 频控与门面测试。

///|
fn make_limit_cache(clock : FakeClock) -> @cache.MemoryCache {
  make_service_cache(clock)
}

///|
test "rate limit get exceeds per-minute cap" {
  let clock = FakeClock::make()
  let cache = make_limit_cache(clock)
  let limits = @service.RateLimitConfig::default()
  // 前 120 次放行
  for _i in 0..<120 {
    assert_true(@service.rate_limit_get(limits, cache, "client-a") is None)
  }
  // 第 121 次 → 6201
  assert_true(
    @service.rate_limit_get(limits, cache, "client-a")
    is Some(@protocol.ApiReqLimitGetError),
  )
  // 不同 client 互不影响
  assert_true(@service.rate_limit_get(limits, cache, "client-b") is None)
  // client_id 为空跳过限制（对齐 AJ）
  for _i in 0..<200 {
    assert_true(@service.rate_limit_get(limits, cache, "") is None)
  }
}

///|
test "rate limit window slides with ttl renewal" {
  let clock = FakeClock::make()
  let cache = make_limit_cache(clock)
  let limits = @service.RateLimitConfig::default()
  // 与 Java 缺陷的区别：TTL 每次请求重置，持续请求不会出现"首个窗口过期后计数残留"
  for _i in 0..<120 {
    let _ = @service.rate_limit_get(limits, cache, "slide")
  }
  assert_true(@service.rate_limit_get(limits, cache, "slide") is Some(_))
  // 停止请求 60 秒后计数过期，恢复放行
  clock.advance(61L)
  assert_true(@service.rate_limit_get(limits, cache, "slide") is None)
}

///|
test "rate limit check and verify caps" {
  let clock = FakeClock::make()
  let cache = make_limit_cache(clock)
  let limits = @service.RateLimitConfig::default()
  for _i in 0..<600 {
    let _ = @service.rate_limit_check(limits, cache, "c1")
    let _ = @service.rate_limit_verify(limits, cache, "c1")
  }
  assert_true(
    @service.rate_limit_check(limits, cache, "c1")
    is Some(@protocol.ApiReqLimitCheckError),
  )
  assert_true(
    @service.rate_limit_verify(limits, cache, "c1")
    is Some(@protocol.ApiReqLimitVerifyError),
  )
}

///|
test "rate limit fail lock and expiry" {
  let clock = FakeClock::make()
  let cache = make_limit_cache(clock)
  let limits = @service.RateLimitConfig::default()
  // 5 次失败累计（阈值 5，未超过时仍放行）
  for _i in 0..<5 {
    @service.rate_limit_record_fail(limits, cache, "attacker")
    assert_true(@service.rate_limit_get(limits, cache, "attacker") is None)
  }
  // 第 6 次失败 → 超阈值 → get 锁定
  @service.rate_limit_record_fail(limits, cache, "attacker")
  assert_true(
    @service.rate_limit_get(limits, cache, "attacker")
    is Some(@protocol.ApiReqLockGetError),
  )
  // 锁定 300 秒内持续拒绝
  clock.advance(299L)
  assert_true(@service.rate_limit_get(limits, cache, "attacker") is Some(_))
  // 300 秒后锁过期；失败计数（60s 窗口）也早已过期
  clock.advance(2L)
  assert_true(@service.rate_limit_get(limits, cache, "attacker") is None)
}

///|
test "facade full chain with rate limiting" {
  let clock = FakeClock::make()
  let cache = make_limit_cache(clock)
  let service = @service.CaptchaService::with_rng(
    make_pool(),
    @common.Rng::new(77UL),
  )
  // get：确定性种子下可重复生成
  let resp = match
    service.get(cache, @service.BlockPuzzle, client_id="user-1") {
    Ok(r) => r
    Err(e) => {
      println(e.message())
      assert_true(false)
      abort("unreachable")
    }
  }
  assert_true(resp.captcha_type == "blockPuzzle")
  // 从缓存取真实坐标模拟正确拖动
  let stored = match cache.get(@service.captcha_key(resp.token)) {
    Some(s) => s
    None => abort("unreachable")
  }
  let point = match @protocol.Point::parse_captcha_json(stored) {
    Ok(p) => p
    Err(_) => abort("unreachable")
  }
  let raw = "{\"x\": \{point.x()}, \"y\": 5.0}"
  let point_json = match @crypto.aes_encrypt(raw, resp.secret_key) {
    Some(v) => v
    None => abort("unreachable")
  }
  let check_resp = service.check(
    cache,
    @service.BlockPuzzle,
    client_id="user-1",
    token=resp.token,
    point_json~,
  )
  assert_true(check_resp.is_success())
  let verification = match
    @crypto.aes_encrypt(resp.token + "---" + raw, resp.secret_key) {
    Some(v) => v
    None => abort("unreachable")
  }
  assert_true(
    service
    .verify(cache, client_id="user-1", captcha_verification=verification)
    .is_success(),
  )
  // 防重放
  assert_true(
    !service
    .verify(cache, client_id="user-1", captcha_verification=verification)
    .is_success(),
  )
}

///|
test "facade get click word without font" {
  let clock = FakeClock::make()
  let cache = make_limit_cache(clock)
  // make_pool 只含 originals/sliders，点选底图需单独注册
  let pool = make_pool()
  pool.add_click(make_gradient_bg(310, 155, 42))
  let service = @service.CaptchaService::with_rng(pool, @common.Rng::new(78UL))
  match service.get(cache, @service.ClickWord, client_id="u2") {
    Ok(resp) => {
      assert_true(resp.captcha_type == "clickWord")
      match resp.word_list {
        Some(words) => assert_true(words.length() == 3)
        None => assert_true(false)
      }
    }
    Err(e) => {
      println(e.message())
      assert_true(false)
    }
  }
}

///|
test "facade get fails with empty pool" {
  let clock = FakeClock::make()
  let cache = make_limit_cache(clock)
  let service = @service.CaptchaService::with_rng(
    @image.ImagePool::new(),
    @common.Rng::new(79UL),
  )
  match service.get(cache, @service.BlockPuzzle, client_id="u3") {
    Ok(_) => assert_true(false)
    Err(e) => {
      assert_true(e.rep_code().code() == @protocol.ApiCaptchaBasemapNull.code())
      assert_true(!e.to_response().is_success())
    }
  }
}

///|
test "facade check failure records fail and locks get" {
  let clock = FakeClock::make()
  let cache = make_limit_cache(clock)
  let service = @service.CaptchaService::with_rng(
    make_pool(),
    @common.Rng::new(80UL),
  )
  // 连续 6 次错误坐标 → 触发失败锁定
  for i in 0..<6 {
    let resp = match service.get(cache, @service.BlockPuzzle, client_id="bad") {
      Ok(r) => r
      Err(e) => {
        println(e.message())
        assert_true(false)
        abort("unreachable")
      }
    }
    let point_json = match
      @crypto.aes_encrypt("{\"x\": 1, \"y\": 5.0}", resp.secret_key) {
      Some(v) => v
      None => abort("unreachable")
    }
    let check_resp = service.check(
      cache,
      @service.BlockPuzzle,
      client_id="bad",
      token=resp.token,
      point_json~,
    )
    assert_true(
      check_resp.rep_code() == @protocol.ApiCaptchaCoordinateError.code(),
    )
    let _ = i
  }
  // 第 7 次 get：失败数超阈值 → 锁定（6202）
  match service.get(cache, @service.BlockPuzzle, client_id="bad") {
    Ok(_) => assert_true(false)
    Err(e) =>
      assert_true(e.rep_code().code() == @protocol.ApiReqLockGetError.code())
  }
  // 其他 client 不受影响
  match service.get(cache, @service.BlockPuzzle, client_id="good") {
    Ok(_) => assert_true(true)
    Err(e) => {
      println(e.message())
      assert_true(false)
    }
  }
}

///|
test "facade kind parse" {
  assert_true(
    @service.CaptchaKind::parse("blockPuzzle") is Some(@service.BlockPuzzle),
  )
  assert_true(
    @service.CaptchaKind::parse("clickWord") is Some(@service.ClickWord),
  )
  assert_true(@service.CaptchaKind::parse("rotatePuzzle") is None)
}
