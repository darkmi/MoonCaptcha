///|
fn make_bg(width : Int, height : Int) -> @image.PixelBuffer {
  // 灰蓝色底图 (0xFF << 24) | 0x336699
  @image.PixelBuffer::make(width, height, (0xFF << 24) | 0x336699)
}

///|
fn make_template(width : Int, height : Int) -> @image.PixelBuffer {
  // 中心 2x2 完全不透明（alpha=255），四边 alpha=100 的边缘像素
  let t = @image.PixelBuffer::new(width, height)
  let cx = width / 2
  let cy = height / 2
  for dx in -1..<2 {
    for dy in -1..<2 {
      t.set_rgb(cx + dx, cy + dy, (255 << 24) | 0x00FFFFFF)
    }
  }
  // 边缘：alpha = 100
  t.set_rgb(cx - 2, cy, (100 << 24) | 0x00FFFFFF)
  t.set_rgb(cx + 2, cy, (100 << 24) | 0x00FFFFFF)
  t
}

///|
test "pixel buffer get set" {
  let buf = @image.PixelBuffer::make(4, 4, (0xFF << 24) | 0x112233)
  assert_true(buf.get_rgb(2, 2) == ((0xFF << 24) | 0x112233))
  buf.set_rgb(0, 0, (0xFF << 24) | 0x445566)
  assert_true(buf.get_rgb(0, 0) == ((0xFF << 24) | 0x445566))
  // 越界安全
  assert_true(buf.get_rgb(-1, 0) == 0)
  assert_true(buf.get_rgb(4, 0) == 0)
}

///|
test "blend_with_white known values" {
  // alpha=0 → 原色
  assert_true(
    @image.blend_with_white((0xFF << 24) | 0x336699, 0) ==
    ((0xFF << 24) | 0x336699),
  )
  // alpha=255 → 纯白
  assert_true(
    @image.blend_with_white((0xFF << 24) | 0x336699, 255) ==
    ((0xFF << 24) | 0xFFFFFF),
  )
  // alpha=128 → 中间值：r = 0x33*(127/255) + 255*(128/255) ≈ 153
  let blended = @image.blend_with_white((0xFF << 24) | 0x336699, 128)
  assert_true(@image.alpha_of(blended) == 0xFF)
  let r = (blended >> 16) & 0xFF
  assert_true(r >= 150 && r <= 156)
}

///|
test "cut_by_template interior copies background with blur" {
  let ori = make_bg(20, 20)
  let template = @image.PixelBuffer::new(8, 8)
  for dx in -1..<2 {
    for dy in -1..<2 {
      template.set_rgb(4 + dx, 4 + dy, (255 << 24) | 0x00FFFFFF)
    }
  }
  let piece = @image.cut_by_template(ori, template, 5, 5)
  // 小图尺寸与模板一致
  assert_true(piece.width == 8)
  assert_true(piece.height == 8)
  // 内部像素（alpha=255）小图颜色 = 原背景色
  assert_true(@image.alpha_of(piece.get_rgb(4, 4)) == 0xFF)
  assert_true((piece.get_rgb(4, 4) & 0x00FFFFFF) == 0x336699)
  // 背景首个处理的内部像素 (8,8)（对应模板 (3,3)）：邻域尚为纯净均匀背景，
  // "6 像素求和 / 8" 的模糊除法使其变暗（Java 怪癖）：0x33=51→38, 0x66=102→76, 0x99=153→114
  // （后续像素因级联读到已模糊的邻域，不做精确断言）
  assert_true(
    (ori.get_rgb(8, 8) & 0x00FFFFFF) == ((38 << 16) | (76 << 8) | 114),
  )
}

///|
test "cut_by_template edge gets white stroke on background" {
  let ori = make_bg(20, 20)
  let template = make_template(8, 8)
  let _piece = @image.cut_by_template(ori, template, 5, 5)
  // 边缘像素（alpha=100）在背景上产生白描边：x=5+2=7, y=5+4=9（cy=4 → 9）
  // 中心 (9,9)，边缘点 (9±2, 9)
  let left_edge = ori.get_rgb(7, 9)
  assert_true(@image.alpha_of(left_edge) == 0xFF)
  assert_true((left_edge & 0xFF) > 0x99) // 蓝分量向白靠近
  // 小图边缘像素 = 白色 + 模板 alpha=100
  assert_true(@image.alpha_of(_piece.get_rgb(2, 4)) == 100)
  assert_true((_piece.get_rgb(2, 4) & 0x00FFFFFF) == 0xFFFFFF)
}

///|
test "cut_by_template skips transparent template pixels" {
  let ori = make_bg(10, 10)
  let template = @image.PixelBuffer::new(4, 4)
  template.set_rgb(1, 1, (255 << 24) | 0x00123456)
  let piece = @image.cut_by_template(ori, template, 3, 3)
  // alpha=0 的像素：背景不动、小图为透明黑
  assert_true(ori.get_rgb(0, 0) == ((0xFF << 24) | 0x336699))
  assert_true(piece.get_rgb(0, 0) == 0)
  // 小图取的是背景像素颜色（模板只提供 alpha）
  assert_true((piece.get_rgb(1, 1) & 0x00FFFFFF) == 0x336699)
}

///|
test "interference_by_template blurs without producing piece" {
  let ori = make_bg(20, 20)
  let template = make_template(8, 8)
  @image.interference_by_template(ori, template, 3, 3)
  // 内部像素被模糊（同色背景下颜色不变，但至少不 panic 且白描边生效）
  let edge = ori.get_rgb(5, 7) // 中心 (6,7)，左边缘 (4,7)
  assert_true(@image.alpha_of(edge) == 0xFF)
  assert_true((edge & 0xFF) > 0x99)
}
