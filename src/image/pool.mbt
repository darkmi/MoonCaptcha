///|
/// 底图资源池，对齐 AJ-Captcha 的 ImageUtils 资源缓存职责。
/// 三类资源：
/// - originals：滑动拼图底图（AJ-Captcha 标准 310×155 RGB）
/// - sliders：滑块模板（AJ-Captcha 标准 94×310 RGBA 透明画布，形状由 alpha 定义）
/// - clicks：点选文字底图（AJ-Captcha 标准 310×155 RGB）
///
/// 资源来源由集成层决定：运行时字节注册（add_original_png 等）或
/// 构建期嵌入（tools/gen-assets.js 将 PNG 目录转换为 MoonBit 源文件）。
/// 池内存放 PngImage（不可变），每次生成时复制像素，抠图不会污染池。
pub struct ImagePool {
  originals : Array[PngImage]
  sliders : Array[PngImage]
  clicks : Array[PngImage]
}

///|
pub fn ImagePool::new() -> ImagePool {
  { originals: [], sliders: [], clicks: [], }
}

///|
/// 直接注册解码后的图像。
pub fn ImagePool::add_original(self : ImagePool, img : PngImage) -> Unit {
  self.originals.push(img)
}

///|
pub fn ImagePool::add_slider(self : ImagePool, img : PngImage) -> Unit {
  self.sliders.push(img)
}

///|
pub fn ImagePool::add_click(self : ImagePool, img : PngImage) -> Unit {
  self.clicks.push(img)
}

///|
/// 从 PNG 字节流注册底图（解码失败返回 Err）。
pub fn ImagePool::add_original_png(
  self : ImagePool,
  bytes : FixedArray[Int],
) -> Result[Unit, String] {
  match decode_png(bytes) {
    Ok(img) => {
      self.add_original(img)
      Ok(())
    }
    Err(e) => Err(e)
  }
}

///|
pub fn ImagePool::add_slider_png(
  self : ImagePool,
  bytes : FixedArray[Int],
) -> Result[Unit, String] {
  match decode_png(bytes) {
    Ok(img) => {
      self.add_slider(img)
      Ok(())
    }
    Err(e) => Err(e)
  }
}

///|
pub fn ImagePool::add_click_png(
  self : ImagePool,
  bytes : FixedArray[Int],
) -> Result[Unit, String] {
  match decode_png(bytes) {
    Ok(img) => {
      self.add_click(img)
      Ok(())
    }
    Err(e) => Err(e)
  }
}

///|
/// 随机选取（调用方保证池非空时返回 Some；空池返回 None）。
pub fn ImagePool::pick_original(
  self : ImagePool,
  rng : @common.Rng,
) -> PngImage? {
  if self.originals.length() == 0 {
    return None
  }
  Some(self.originals[rng.next_bounded(self.originals.length())])
}

///|
pub fn ImagePool::pick_slider(self : ImagePool, rng : @common.Rng) -> PngImage? {
  if self.sliders.length() == 0 {
    return None
  }
  Some(self.sliders[rng.next_bounded(self.sliders.length())])
}

///|
pub fn ImagePool::pick_click(self : ImagePool, rng : @common.Rng) -> PngImage? {
  if self.clicks.length() == 0 {
    return None
  }
  Some(self.clicks[rng.next_bounded(self.clicks.length())])
}

///|
/// 各类资源数量（诊断用）。
pub fn ImagePool::counts(self : ImagePool) -> (Int, Int, Int) {
  (self.originals.length(), self.sliders.length(), self.clicks.length())
}
