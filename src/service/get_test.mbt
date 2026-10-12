///|
/// get 完整生成流程的集成测试（合成图像，确定性种子）。

///|
fn make_gradient_bg(w : Int, h : Int, seed : Int) -> @image.PngImage {
  let rgba : FixedArray[Int] = FixedArray::make(w * h * 4, 0)
  for y in 0..<h {
    for x in 0..<w {
      let i = (y * w + x) * 4
      rgba[i] = (x * 5 + seed) & 0xFF
      rgba[i + 1] = (y * 9 + seed * 3) & 0xFF
      rgba[i + 2] = ((x + y) * 3 + seed) & 0xFF
      rgba[i + 3] = 255
    }
  }
  { width: w, height: h, rgba }
}

///|
/// 合成滑块模板：94×310 透明画布，顶部区域内不透明块 + 半透明描边环。
fn make_slider_template() -> @image.PngImage {
  let w = 94
  let h = 310
  let rgba : FixedArray[Int] = FixedArray::make(w * h * 4, 0)
  for y in 20..<80 {
    for x in 20..<70 {
      let i = (y * w + x) * 4
      rgba[i] = 255
      rgba[i + 1] = 255
      rgba[i + 2] = 255
      rgba[i + 3] = if y < 23 || y >= 77 || x < 23 || x >= 67 { 100 } else { 255 }
    }
  }
  { width: w, height: h, rgba }
}

///|
fn make_pool() -> @image.ImagePool {
  let pool = @image.ImagePool::new()
  pool.add_original(make_gradient_bg(310, 155, 1))
  pool.add_original(make_gradient_bg(310, 155, 2))
  pool.add_slider(make_slider_template())
  pool
}

///|
test "get_block_puzzle produces decodable images with correct dims" {
  let clock = FakeClock::make()
  let cache = make_service_cache(clock)
  let config = @service.CaptchaConfig::default()
  let rng = @common.Rng::new(99UL)
  match @service.get_block_puzzle(config, rng, make_pool(), cache, None) {
    Ok(resp) => {
      assert_true(resp.captcha_type == "blockPuzzle")
      assert_true(resp.secret_key.length() == 16)
      assert_true(resp.token.length() == 32)
      // 底图：310×155
      match @common.base64_decode(resp.original_image_base64) {
        Some(bytes) =>
          match @image.decode_png(bytes) {
            Ok(img) => {
              assert_true(img.width == 310)
              assert_true(img.height == 155)
            }
            Err(e) => {
              println(e)
              assert_true(false)
            }
          }
        None => assert_true(false)
      }
      // 滑块小图：94×310
      match @common.base64_decode(resp.jigsaw_image_base64) {
        Some(bytes) =>
          match @image.decode_png(bytes) {
            Ok(img) => {
              assert_true(img.width == 94)
              assert_true(img.height == 310)
              // 小图包含不透明像素（抠出的图案）与半透明描边像素
              let mut opaque_cnt = 0
              let mut semi = 0
              for i in 0..<(img.width * img.height) {
                let a = @image.alpha_of(@image.PixelBuffer::from_png_image(img).get_rgb(
                  i % img.width,
                  i / img.width,
                ))
                if a == 255 {
                  opaque_cnt = opaque_cnt + 1
                } else if a > 0 {
                  semi = semi + 1
                }
              }
              assert_true(opaque_cnt > 0)
              assert_true(semi > 0)
            }
            Err(e) => {
              println(e)
              assert_true(false)
            }
          }
        None => assert_true(false)
      }
    }
    Err(e) => {
      println(e)
      assert_true(false)
    }
  }
}

///|
test "get then check then verify full chain" {
  let clock = FakeClock::make()
  let cache = make_service_cache(clock)
  let config = @service.CaptchaConfig::default()
  let rng = @common.Rng::new(123UL)
  let resp = match @service.get_block_puzzle(config, rng, make_pool(), cache, None) {
    Ok(r) => r
    Err(e) => {
      println(e)
      assert_true(false)
      abort("unreachable")
    }
  }
  // 坐标已入缓存；从缓存取出真实 x 模拟"用户拖到位"
  let stored = match cache.get(@service.captcha_key(resp.token)) {
    Some(s) => s
    None => {
      assert_true(false)
      abort("unreachable")
    }
  }
  let point = match @protocol.Point::parse_captcha_json(stored) {
    Ok(p) => p
    Err(_) => {
      assert_true(false)
      abort("unreachable")
    }
  }
  assert_true(point.y() == 5)
  let raw = "{\"x\": \{point.x()}, \"y\": 5.0}"
  let point_json = match @crypto.aes_encrypt(raw, resp.secret_key) {
    Some(v) => v
    None => abort("unreachable")
  }
  let check_resp = @service.block_puzzle_check(config, cache, resp.token, point_json)
  assert_true(check_resp.is_success())
  let verification = match @crypto.aes_encrypt(resp.token + "---" + raw, resp.secret_key) {
    Some(v) => v
    None => abort("unreachable")
  }
  assert_true(@service.block_puzzle_verification(config, cache, verification).is_success())
}

///|
test "get_block_puzzle background gets a notch" {
  let clock = FakeClock::make()
  let cache = make_service_cache(clock)
  let config = @service.CaptchaConfig::default()
  let rng = @common.Rng::new(7UL)
  let pool = make_pool()
  let resp = match @service.get_block_puzzle(config, rng, pool, cache, None) {
    Ok(r) => r
    Err(_) => abort("unreachable")
  }
  // 输出底图与池中原图相比必有差异（凹槽 + 白描边）
  let out = match @common.base64_decode(resp.original_image_base64) {
    Some(b) => b
    None => abort("unreachable")
  }
  let out_img = match @image.decode_png(out) {
    Ok(i) => i
    Err(_) => abort("unreachable")
  }
  let src = pool.pick_original(rng).unwrap()
  let mut diff = 0
  for i in 0..<(out_img.width * out_img.height * 4) {
    if out_img.rgba[i] != src.rgba[i] {
      diff = diff + 1
    }
  }
  assert_true(diff > 0)
}

///|
test "get_block_puzzle fails on empty pool" {
  let clock = FakeClock::make()
  let cache = make_service_cache(clock)
  let config = @service.CaptchaConfig::default()
  let rng = @common.Rng::new(3UL)
  match @service.get_block_puzzle(config, rng, @image.ImagePool::new(), cache, None) {
    Ok(_) => assert_true(false)
    Err(e) => assert_true(e.length() > 0)
  }
  // 只有底图没有滑块模板同样失败
  let pool = @image.ImagePool::new()
  pool.add_original(make_gradient_bg(310, 155, 1))
  match @service.get_block_puzzle(config, rng, pool, cache, None) {
    Ok(_) => assert_true(false)
    Err(_) => assert_true(true)
  }
}

///|
test "get_click_word returns words and stores three points" {
  let clock = FakeClock::make()
  let cache = make_service_cache(clock)
  let config = @service.CaptchaConfig::default()
  let rng = @common.Rng::new(55UL)
  let pool = @image.ImagePool::new()
  pool.add_click(make_gradient_bg(310, 155, 9))
  match @service.get_click_word(config, rng, pool, cache, None) {
    Ok(resp) => {
      assert_true(resp.captcha_type == "clickWord")
      match resp.word_list {
        Some(words) => assert_true(words.length() == 3)
        None => assert_true(false)
      }
      // 缓存中应存有 3 个校验点
      let stored = match cache.get(@service.captcha_key(resp.token)) {
        Some(s) => s
        None => {
          assert_true(false)
          abort("unreachable")
        }
      }
      match @protocol.Point::parse_captcha_json_array(stored) {
        Ok(points) => assert_true(points.length() == 3)
        Err(_) => assert_true(false)
      }
    }
    Err(e) => {
      println(e)
      assert_true(false)
    }
  }
}
