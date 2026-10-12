///|
/// 最小 TTF 夹具（.tmp_gen_font.js 生成，勿手工编辑）：
/// upem=1000，gid1='O' 全宽正方形 (0,0)-(1000,1000)，gid2='I' 窄条 (200,0)-(400,1000)。
fn fixture_font() -> FixedArray[Int] {
  @common.fixed_from_array([
    0, 1, 0, 0, 0, 7, 0, 0, 0, 0, 0, 0, 99, 109, 97, 112, 0, 0, 0, 0,
    0, 0, 0, 124, 0, 0, 0, 52, 103, 108, 121, 102, 0, 0, 0, 0, 0, 0, 0, 176,
    0, 0, 0, 68, 104, 101, 97, 100, 0, 0, 0, 0, 0, 0, 0, 244, 0, 0, 0, 54,
    104, 104, 101, 97, 0, 0, 0, 0, 0, 0, 1, 44, 0, 0, 0, 36, 104, 109, 116, 120,
    0, 0, 0, 0, 0, 0, 1, 80, 0, 0, 0, 8, 108, 111, 99, 97, 0, 0, 0, 0,
    0, 0, 1, 88, 0, 0, 0, 8, 109, 97, 120, 112, 0, 0, 0, 0, 0, 0, 1, 96,
    0, 0, 0, 6, 0, 0, 0, 1, 0, 3, 0, 1, 0, 0, 0, 12, 0, 4, 0, 40,
    0, 0, 0, 6, 0, 0, 0, 0, 0, 0, 0, 73, 0, 79, 255, 255, 0, 0, 0, 73,
    0, 79, 255, 255, 255, 185, 255, 178, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0,
    0, 0, 3, 232, 3, 232, 0, 3, 0, 0, 1, 1, 1, 1, 0, 0, 3, 232, 0, 0,
    252, 24, 0, 0, 0, 0, 3, 232, 0, 0, 0, 1, 0, 200, 0, 0, 1, 144, 3, 232,
    0, 3, 0, 0, 1, 1, 1, 1, 0, 200, 0, 200, 0, 0, 255, 56, 0, 0, 0, 0,
    3, 232, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 95, 15, 60, 245,
    0, 0, 3, 232, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 1, 0, 0, 3, 32, 255, 56, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 3, 232, 0, 0,
    3, 232, 0, 0, 0, 0, 0, 0, 0, 17, 0, 34, 0, 1, 0, 0, 0, 3, 0, 0,
  ])
}

///|
test "font parse minimal ttf" {
  match Font::parse(fixture_font()) {
    Ok(f) => {
      assert_true(f.units_per_em == 1000)
      assert_true(f.num_glyphs == 3)
      assert_true(f.char_glyph('O') == 1)
      assert_true(f.char_glyph('I') == 2)
      assert_true(f.char_glyph('X') == -1)
      assert_true(f.glyph_advance(1) == 1000)
    }
    Err(e) => {
      println(e)
      assert_true(false)
    }
  }
}

///|
test "font draw square glyph exact coverage" {
  // 40×40 蓝底，size=20 在 (5,25) 画 'O'：正方形恰好覆盖像素列/行 [5, 25)
  let buf = PixelBuffer::make(40, 40, (0xFF << 24) | (0x00 << 16) | (0x00 << 8) | 0xFF)
  let f = match Font::parse(fixture_font()) {
    Ok(f) => f
    Err(_) => abort("unreachable")
  }
  let _ = f.draw_text(buf, "O", 5, 25, 20, (0xFF << 24) | (0xFF << 16), 0.0)
  // 内部像素 = 文字色（红），边界外 = 蓝色
  assert_true(buf.get_rgb(14, 14) == ((0xFF << 24) | (0xFF << 16)))
  assert_true(buf.get_rgb(4, 14) == ((0xFF << 24) | 0xFF))
  assert_true(buf.get_rgb(25, 14) == ((0xFF << 24) | 0xFF))
  // 统计红色像素数 = 20×20
  let mut red = 0
  for y in 0..<40 {
    for x in 0..<40 {
      if buf.get_rgb(x, y) == ((0xFF << 24) | (0xFF << 16)) {
        red = red + 1
      }
    }
  }
  assert_true(red == 400)
}

///|
test "font draw narrow glyph geometry" {
  // 'I' 窄条：x ∈ [200,400)/1000×20 = 4px 宽，即像素列 [9, 13)（锚点 x=5）
  let buf = PixelBuffer::make(40, 40, (0xFF << 24) | 0xFF)
  let f = match Font::parse(fixture_font()) {
    Ok(f) => f
    Err(_) => abort("unreachable")
  }
  let end_x = f.draw_text(buf, "I", 5, 25, 20, (0xFF << 24) | (0xFF << 16), 0.0)
  assert_true(end_x == 25)
  assert_true(buf.get_rgb(10, 14) == ((0xFF << 24) | (0xFF << 16)))
  assert_true(buf.get_rgb(8, 14) == ((0xFF << 24) | 0xFF))
  assert_true(buf.get_rgb(13, 14) == ((0xFF << 24) | 0xFF))
}

///|
test "font draw advances pen by glyph width" {
  let buf = PixelBuffer::make(60, 40, (0xFF << 24) | 0xFF)
  let f = match Font::parse(fixture_font()) {
    Ok(f) => f
    Err(_) => abort("unreachable")
  }
  let end_x = f.draw_text(buf, "OI", 5, 25, 20, (0xFF << 24) | (0xFF << 16), 0.0)
  assert_true(end_x == 45)
  // 'I' 在第二个字符位（pen=25）：像素列 [29, 33)
  assert_true(buf.get_rgb(30, 14) == ((0xFF << 24) | (0xFF << 16)))
  assert_true(buf.get_rgb(28, 14) == ((0xFF << 24) | 0xFF))
}

///|
test "font draw rotation smoke" {
  // 45° 旋转：正方形旋转后仍覆盖锚点附近区域（对角线略越界），冒烟断言
  let buf = PixelBuffer::make(60, 60, (0xFF << 24) | 0xFF)
  let f = match Font::parse(fixture_font()) {
    Ok(f) => f
    Err(_) => abort("unreachable")
  }
  let _ = f.draw_text(buf, "O", 20, 40, 20, (0xFF << 24) | (0xFF << 16), 45.0)
  let mut red = 0
  for y in 0..<60 {
    for x in 0..<60 {
      if buf.get_rgb(x, y) == ((0xFF << 24) | (0xFF << 16)) {
        red = red + 1
      }
    }
  }
  // 20×20=400px² 旋转不变；满覆盖 ≈ 面积-边界带（4×4 超采样），冒烟区间断言
  assert_true(red > 300 && red <= 400)
}

///|
test "estimate text width matches java formula" {
  assert_true(estimate_text_width("ab", 25) == 5 + 16)
  assert_true(estimate_text_width("的", 25) == 12 + 5)
  assert_true(estimate_text_width("的a", 25) == 12 + 5 + 8)
}
