///|
test "avg_matrix_around skips middle row" {
  // 背景中心 (5,5) 周围构造不同颜色：上下两行红/蓝，中行绿
  let img = PixelBuffer::make(11, 11, (0xFF << 24) | (0xFF << 8)) // 全绿
  // 上面一行 (4..6, 4) 红，下面一行 (4..6, 6) 蓝
  for dx in 4..<7 {
    img.set_rgb(dx, 4, (0xFF << 24) | (0xFF << 16))
    img.set_rgb(dx, 6, (0xFF << 24) | 0xFF)
  }
  // avg(5,5)：参与的是 (4..6,4) 红 3 个 + (4..6,6) 蓝 3 个（中行被跳过），
  // 求和 6 像素后除以 8（Java 怪癖）：765 / 8 = 95
  let avg = avg_matrix_around(img, 5, 5)
  assert_true(((avg >> 16) & 0xFF) == 95)
  assert_true(((avg >> 8) & 0xFF) == 0)
  assert_true((avg & 0xFF) == 95)
}

///|
