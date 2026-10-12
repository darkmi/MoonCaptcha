///|
/// get 完整生成流程（blockPuzzle）：选图 → 水印 → 随机坐标 → 抠图 → 双图编码 → 存储坐标。
/// 对齐 BlockPuzzleCaptchaServiceImpl#get + pictureTemplatesCut；
/// 与 Java 版的差异：底图输出 PNG 而非 JPG（体积稍大，见迁移设计 §6），
/// 干扰项（interference options）在 M5 实现。
///
/// - `font`：提供时在底图右下角烧录水印（对齐 AJ-Captcha）；None 或
///   `config.water_mark` 为空串则跳过
/// - 坐标与令牌经 block_puzzle_store 写入缓存（TTL 120s）
pub fn get_block_puzzle(
  config : CaptchaConfig,
  rng : @common.Rng,
  pool : @image.ImagePool,
  cache : &@cache.Cache,
  font : @image.Font?,
) -> Result[@protocol.GetResponse, String] {
  let bg_png = match pool.pick_original(rng) {
    Some(img) => img
    None => return Err("底图未初始化成功，请检查路径")
  }
  let tpl_png = match pool.pick_slider(rng) {
    Some(img) => img
    None => return Err("滑块模板未初始化成功，请检查路径")
  }
  let bg = @image.PixelBuffer::from_png_image(bg_png)
  // 水印在抠图前绘制（对齐 Java 顺序：水印会出现在凹槽与滑块小图中）
  match font {
    Some(f) => f.draw_watermark(bg, config.water_mark, config.han_zi_size)
    None => ()
  }
  let template = @image.PixelBuffer::from_png_image(tpl_png)
  // 标准底图（155 高）< 模板（310 高）→ y 恒为 5（前端硬编码 y:5.0 的约定）
  let point = generate_jigsaw_point(
    rng,
    bg.width,
    bg.height,
    template.width,
    template.height,
    config.aes_enabled,
  )
  let piece = @image.cut_by_template(bg, template, point.x(), 0)
  let token = rng.uuid()
  block_puzzle_store(config, cache, token, point)
  Ok({
    captcha_type: "blockPuzzle",
    original_image_base64: @common.base64_encode(
      @image.encode_png(bg.to_png_image()),
    ),
    jigsaw_image_base64: @common.base64_encode(
      @image.encode_png(piece.to_png_image()),
    ),
    word_list: None,
    token,
    secret_key: point.secret_key(),
  })
}

///|
/// get 完整生成流程（clickWord）：选底图 → 布点选字 → 文字烧录 → 水印 → 存储。
/// 文字（含干扰字）以随机颜色/旋转直接绘制到底图上（对齐 getImageData）；
/// `font` 为 None 时跳过绘制，返回未烧录的底图与坐标（demo 的 DOM 渲染
/// 模式），集成方应尽量提供字体以对齐 AJ-Captcha 行为。
pub fn get_click_word(
  config : CaptchaConfig,
  rng : @common.Rng,
  pool : @image.ImagePool,
  cache : &@cache.Cache,
  font : @image.Font?,
) -> Result[@protocol.GetResponse, String] {
  let bg_png = match pool.pick_click(rng) {
    Some(img) => img
    None => return Err("底图未初始化成功，请检查路径")
  }
  let data = generate_click_word_data(rng, bg_png.width, bg_png.height, config)
  let buf = @image.PixelBuffer::from_png_image(bg_png)
  match font {
    Some(f) => {
      for ch in data.chars {
        let _ = f.draw_text(
          buf,
          ch.word,
          ch.x,
          ch.y,
          config.han_zi_size,
          ch.color,
          ch.rotation.to_double(),
        )
      }
      f.draw_watermark(buf, config.water_mark, config.han_zi_size)
    }
    None => ()
  }
  let token = rng.uuid()
  click_word_store(config, cache, token, data.point_list)
  Ok({
    captcha_type: "clickWord",
    original_image_base64: @common.base64_encode(
      @image.encode_png(buf.to_png_image()),
    ),
    jigsaw_image_base64: "",
    word_list: Some(data.word_list),
    token,
    secret_key: data.secret_key,
  })
}
