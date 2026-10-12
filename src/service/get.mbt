///|
/// get 完整生成流程（blockPuzzle）：选图 → 随机坐标 → 抠图 → 双图编码 → 存储坐标。
/// 对齐 BlockPuzzleCaptchaServiceImpl#get + pictureTemplatesCut；
/// 与 Java 版的差异：底图输出 PNG 而非 JPG（体积稍大，见迁移设计 §6），
/// 干扰项（interference options）在 M5 实现。
///
/// 坐标与令牌经 block_puzzle_store 写入缓存（TTL 120s）；返回的 repData
/// 可直接作为 get 响应的 repData。
pub fn get_block_puzzle(
  config : CaptchaConfig,
  rng : @common.Rng,
  pool : @image.ImagePool,
  cache : &@cache.Cache,
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
    original_image_base64: @common.base64_encode(@image.encode_png(bg.to_png_image())),
    jigsaw_image_base64: @common.base64_encode(@image.encode_png(piece.to_png_image())),
    word_list: None,
    token,
    secret_key: point.secret_key(),
  })
}

///|
/// get 完整生成流程（clickWord，图像部分）：选底图 + 布点选字 + 存储。
/// 与 blockPuzzle 不同，文字绘制（颜色/旋转/光栅化）依赖 M3 字体模块；
/// M3 之前集成层需自行把 word_positions 绘制到展示图上（demo 的 DOM 渲染
/// 即此模式的参考实现），因此这里返回绘制坐标列表。
/// point_positions 与 word_list 一一对应（均不含干扰字）。
pub fn get_click_word(
  config : CaptchaConfig,
  rng : @common.Rng,
  pool : @image.ImagePool,
  cache : &@cache.Cache,
) -> Result[@protocol.GetResponse, String] {
  let bg_png = match pool.pick_click(rng) {
    Some(img) => img
    None => return Err("底图未初始化成功，请检查路径")
  }
  let (word_list, point_list) = generate_click_word_data(
    rng,
    bg_png.width,
    bg_png.height,
    config,
  )
  let token = rng.uuid()
  click_word_store(config, cache, token, point_list)
  Ok({
    captcha_type: "clickWord",
    original_image_base64: @common.base64_encode(@image.encode_png(bg_png)),
    jigsaw_image_base64: "",
    word_list: Some(word_list),
    token,
    secret_key: if point_list.length() > 0 {
      point_list[0].secret_key()
    } else {
      ""
    },
  })
}
