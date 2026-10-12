///|
/// 模板抠图，逐像素对照 BlockPuzzleCaptchaServiceImpl#cutByTemplate 移植。
///
/// 输入：
/// - `ori`：背景图（会被就地修改：内部像素模糊成凹槽、边缘像素白描边）
/// - `template`：模板图（形状由 alpha 定义，alpha=0 完全跳过）
/// - `x` / `y`：抠图原点（标准底图下 y=0）
///
/// 返回与模板同尺寸的滑块小图（未覆盖区域为透明黑 0）。
///
/// 像素规则（与 Java 完全一致）：
/// - alpha > 200（内部）：小图 = 背景像素 + 模板 alpha；
///   背景 = 邻域均值模糊（见 avg_matrix_around 的 6 邻域怪癖）
/// - 0 < alpha <= 200（边缘）：背景 = 白色按 alpha 比例混合（白描边）；
///   小图 = 白色 + 模板 alpha
pub fn cut_by_template(
  ori : PixelBuffer,
  template : PixelBuffer,
  x : Int,
  y : Int,
) -> PixelBuffer {
  let new_image = PixelBuffer::new(template.width, template.height)
  for i in 0..<template.width {
    for j in 0..<template.height {
      let template_rgb = template.get_rgb(i, j)
      let alpha = alpha_of(template_rgb)
      if alpha > 0 {
        let tx = x + i
        let ty = y + j
        // 合法输入（模板不透明区域落在背景内）不会越界；越界时跳过以保证不 panic
        if tx < 0 || ty < 0 || tx >= ori.width || ty >= ori.height {
          continue
        }
        let ori_rgb = ori.get_rgb(tx, ty)
        if alpha > 200 {
          // 完全内部像素：滑块抠背景色，底图凹槽模糊
          new_image.set_rgb(i, j, (alpha << 24) | (ori_rgb & 0x00FFFFFF))
          let blurred = avg_matrix_around(ori, tx, ty)
          ori.set_rgb(tx, ty, blurred)
        } else {
          // 边缘过渡像素：滑块与凹槽同一套白描边逻辑
          ori.set_rgb(tx, ty, blend_with_white(ori_rgb, alpha))
          new_image.set_rgb(i, j, (alpha << 24) | 0x00FFFFFF)
        }
      }
    }
  }
  new_image
}

///|
/// 干扰抠图处理（对齐 interferenceByTemplate）：只在背景上做模糊凹槽 + 白描边，
/// 不产出小图。干扰块不画描边（Java 注释如此，实际共用 blend 逻辑）。
pub fn interference_by_template(
  ori : PixelBuffer,
  template : PixelBuffer,
  x : Int,
  y : Int,
) -> Unit {
  for i in 0..<template.width {
    for j in 0..<template.height {
      let template_rgb = template.get_rgb(i, j)
      let alpha = alpha_of(template_rgb)
      if alpha > 0 {
        let tx = x + i
        let ty = y + j
        if tx < 0 || ty < 0 || tx >= ori.width || ty >= ori.height {
          continue
        }
        let ori_rgb = ori.get_rgb(tx, ty)
        if alpha > 200 {
          // 完全内部像素：模糊凹槽
          ori.set_rgb(tx, ty, avg_matrix_around(ori, tx, ty))
        } else {
          // 边缘过渡像素：白描边
          ori.set_rgb(tx, ty, blend_with_white(ori_rgb, alpha))
        }
      }
    }
  }
}

///|
/// 3×3 邻域均值（对齐 readPixel + fillMatrix + avgMatrix 的组合行为）。
///
/// ⚠️ 忠实移植 Java 的三处怪癖（勿"修正"，否则输出与 AJ-Captcha 不一致）：
/// 1. avgMatrix 跳过 `j == 1` 的整行——即跳过 y 行的全部 3 个像素，
///    实际参与求和的是上下两行的 6 个像素（不是常规的 8 邻域）；
/// 2. 求和 6 个像素后**仍除以 8**（Java avgMatrix 的除数硬编码 8），凹槽因此偏暗；
/// 3. readPixel 边界处理不对称：x 越界取绝对值（-1 → 1），y 越界用当前 y 代替。
fn avg_matrix_around(img : PixelBuffer, x : Int, y : Int) -> Int {
  let mut r = 0
  let mut g = 0
  let mut b = 0
  // 对齐 readPixel 的遍历顺序：i 为 X 轴（外层），j 为 Y 轴（内层），
  // fillMatrix 行-major 填入 3x3 后 avgMatrix 跳过 j==1 列 → 跳过 j(y)=y 的整行
  for di in -1..<2 {
    for dj in -1..<2 {
      // avgMatrix: if (j == 1) continue —— j 为列下标，对应 Y 方向中列
      if dj == 0 {
        continue
      }
      let tx = {
        let raw = x + di
        if raw < 0 {
          -raw
        } else if raw >= img.width {
          x
        } else {
          raw
        }
      }
      let ty = {
        let raw = y + dj
        if raw < 0 {
          -raw
        } else if raw >= img.height {
          y
        } else {
          raw
        }
      }
      let rgb = img.get_rgb(tx, ty)
      r = r + ((rgb >> 16) & 0xFF)
      g = g + ((rgb >> 8) & 0xFF)
      b = b + (rgb & 0xFF)
    }
  }
  // Java avgMatrix 除数硬编码 8（尽管只累加 6 个像素）
  (0xFF << 24) | ((r / 8) << 16) | ((g / 8) << 8) | (b / 8)
}
