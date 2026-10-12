///|
/// ARGB 像素缓冲，语义对齐 Java BufferedImage 的 getRGB / setRGB：
/// 每像素一个 int，布局 0xAARRGGBB。
pub(all) struct PixelBuffer {
  width : Int
  height : Int
  pixels : FixedArray[Int]
}

///|
pub fn PixelBuffer::new(width : Int, height : Int) -> PixelBuffer {
  { width, height, pixels: FixedArray::make(width * height, 0), }
}

///|
pub fn PixelBuffer::make(width : Int, height : Int, color : Int) -> PixelBuffer {
  { width, height, pixels: FixedArray::make(width * height, color), }
}

///|
/// 读取像素；越界返回 0（透明黑）。合法输入不会越界（Java 侧为抛异常）。
pub fn PixelBuffer::get_rgb(self : PixelBuffer, x : Int, y : Int) -> Int {
  if x < 0 || y < 0 || x >= self.width || y >= self.height {
    return 0
  }
  self.pixels[y * self.width + x]
}

///|
/// 写入像素；越界静默忽略。
pub fn PixelBuffer::set_rgb(
  self : PixelBuffer,
  x : Int,
  y : Int,
  argb : Int,
) -> Unit {
  if x < 0 || y < 0 || x >= self.width || y >= self.height {
    return
  }
  self.pixels[y * self.width + x] = argb
}

///|
/// 提取 alpha 分量（0..255）。
pub fn alpha_of(argb : Int) -> Int {
  (argb >> 24) & 0xFF
}

///|
/// 按 alpha 比例将原像素与白色混合，得到柔和的白描边（对齐 blendWithWhite）。
/// alpha 越大白色越浓，随模板边缘自然渐变；滑块与凹槽共用同一逻辑保证视觉统一。
pub fn blend_with_white(rgb : Int, alpha : Int) -> Int {
  let ratio = alpha.to_double() / 255.0
  let r = (rgb >> 16) & 0xFF
  let g = (rgb >> 8) & 0xFF
  let b = rgb & 0xFF
  let nr = (r.to_double() * (1.0 - ratio) + 255.0 * ratio).to_int()
  let ng = (g.to_double() * (1.0 - ratio) + 255.0 * ratio).to_int()
  let nb = (b.to_double() * (1.0 - ratio) + 255.0 * ratio).to_int()
  (0xFF << 24) | (nr << 16) | (ng << 8) | nb
}
