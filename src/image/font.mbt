///|
/// 字体渲染：字形轮廓 → 多边形（二次贝塞尔细分 + 仿射变换）→
/// 4×4 超采样 nonzero 扫描覆盖 → 按透明度混色到 PixelBuffer。
/// 锚点语义与 Java Graphics2D#drawString 一致：为基线左端点，
/// 旋转绕锚点（对齐 AJ-Captcha 点选文字的 deriveFont(rotate) 行为）。

///|
priv struct FPoint {
  x : Double
  y : Double
}

///|
fn fpoint(x : Double, y : Double) -> FPoint {
  { x, y, }
}

///|
/// 余弦（Taylor 展开，输入先归约到 ±2π；角度场景精度远超需要）。
fn dcos(a0 : Double) -> Double {
  let two_pi = 6.283185307179586
  let mut a = a0
  while a > two_pi {
    a = a - two_pi
  }
  while a < -two_pi {
    a = a + two_pi
  }
  let mut term = 1.0
  let mut sum = 1.0
  for k in [2, 4, 6, 8, 10, 12, 14, 16] {
    term = term * (-a * a) / ((k - 1) * k).to_double()
    sum = sum + term
  }
  sum
}

///|
fn dsin(a : Double) -> Double {
  dcos(a - 1.5707963267948966)
}

///|
/// 二次贝塞尔细分（固定 6 段，25px 字号下平滑足够）。
fn flatten_quad(
  out : Array[FPoint],
  p0 : FPoint,
  ctrl : FPoint,
  p1 : FPoint,
) -> Unit {
  let steps = 6
  for s in 1..<=steps {
    let t = s.to_double() / steps.to_double()
    let mt = 1.0 - t
    let x = mt * mt * p0.x + 2.0 * mt * t * ctrl.x + t * t * p1.x
    let y = mt * mt * p0.y + 2.0 * mt * t * ctrl.y + t * t * p1.y
    out.push(fpoint(x, y))
  }
}

///|
/// 字形 → 变换后的多边形集合（像素坐标，y 向下）。
/// 变换：像素 X = ax + scale*(x_f*cos - y_f*sin)；
///       像素 Y = ay - scale*(x_f*sin + y_f*cos)（字体 y 轴向上）。
fn Font::glyph_polygons(
  self : Font,
  gid : Int,
  size : Int,
  ax : Double,
  ay : Double,
  cos : Double,
  sin : Double,
) -> Array[Array[FPoint]] {
  let polygons : Array[Array[FPoint]] = []
  let outline = match self.glyph_outline(gid) {
    Ok(o) => o
    Err(_) => return polygons
  }
  let scale = size.to_double() / self.units_per_em.to_double()
  let transform = fn(x : Int, y : Int) -> FPoint {
    let xf = x.to_double() * scale
    let yf = y.to_double() * scale
    fpoint(ax + (xf * cos - yf * sin), ay - (xf * sin + yf * cos))
  }
  let mut c = 0
  while c < outline.contour_ends.length() {
    let end = outline.contour_ends[c]
    let start = if c == 0 { 0 } else { outline.contour_ends[c - 1] + 1 }
    c = c + 1
    if end <= start {
      continue
    }
    let pts = outline.points
    // 起点定位：第一个 on-curve 点；全部 off-curve 时取前两点中点
    let mut start_idx = -1
    for i in start..<=end {
      if pts[i].on_curve {
        start_idx = i
        break
      }
    }
    if start_idx < 0 {
      // 全 off-curve 起点：以首两点中点为虚拟起始锚点
      let m = transform(
        (pts[start].x + pts[start + 1].x) / 2,
        (pts[start].y + pts[start + 1].y) / 2,
      )
      let poly : Array[FPoint] = [m]
      walk_contour(pts, start, end, start + 1, m, transform, poly)
      polygons.push(poly)
      continue
    }
    let start_pt = transform(pts[start_idx].x, pts[start_idx].y)
    let poly : Array[FPoint] = [start_pt]
    walk_contour(pts, start, end, start_idx + 1, start_pt, transform, poly)
    polygons.push(poly)
  }
  polygons
}

///|
/// 沿轮廓游走：on→直线；off→二次贝塞尔（连续 off 取中点为隐式 on 点）。
fn walk_contour(
  pts : Array[GlyphPoint],
  start : Int,
  end : Int,
  first_i : Int,
  start_pt : FPoint,
  transform : (Int, Int) -> FPoint,
  poly : Array[FPoint],
) -> Unit {
  let n = end - start + 1
  let mut cur = start_pt
  let mut idx = first_i
  let mut count = 1
  while count <= n {
    let i = start + (idx - start) % n
    let p = pts[i]
    if p.on_curve {
      let v = transform(p.x, p.y)
      poly.push(v)
      cur = v
      idx = idx + 1
      count = count + 1
    } else {
      // 控制点
      let ctrl = transform(p.x, p.y)
      let next_i = start + (idx + 1 - start) % n
      let q = pts[next_i]
      if q.on_curve {
        let v = transform(q.x, q.y)
        flatten_quad(poly, cur, ctrl, v)
        cur = v
        idx = idx + 2
        count = count + 2
      } else {
        let mid_font_x = (p.x + q.x) / 2
        let mid_font_y = (p.y + q.y) / 2
        let v = transform(mid_font_x, mid_font_y)
        flatten_quad(poly, cur, ctrl, v)
        cur = v
        idx = idx + 1
        count = count + 1
      }
    }
  }
}

///|
/// 点在多边形集合内的 winding 数（nonzero 规则；字体镂空轮廓反向绕行）。
fn winding_at(
  edges : Array[(Double, Double, Double, Double)],
  px : Double,
  py : Double,
) -> Int {
  let mut w = 0
  for e in edges {
    let (x1, y1, x2, y2) = e
    if (y1 <= py) != (y2 <= py) {
      let xint = x1 + (py - y1) * (x2 - x1) / (y2 - y1)
      if xint > px {
        if y2 > y1 {
          w = w + 1
        } else {
          w = w - 1
        }
      }
    }
  }
  w
}

///|
/// 把字形按覆盖度混合到缓冲区。
fn paint_polygons(
  buf : PixelBuffer,
  polygons : Array[Array[FPoint]],
  color : Int,
) -> Unit {
  let edges : Array[(Double, Double, Double, Double)] = []
  let mut min_x = 1.0E9
  let mut max_x = -1.0E9
  let mut min_y = 1.0E9
  let mut max_y = -1.0E9
  for poly in polygons {
    let m = poly.length()
    if m >= 2 {
      for i in 0..<m {
        let a = poly[i]
        let b = poly[(i + 1) % m]
        edges.push((a.x, a.y, b.x, b.y))
        if a.x < min_x {
          min_x = a.x
        }
        if a.x > max_x {
          max_x = a.x
        }
        if a.y < min_y {
          min_y = a.y
        }
        if a.y > max_y {
          max_y = a.y
        }
      }
    }
  }
  if edges.length() == 0 {
    return
  }
  let fr = ((color >> 16) & 0xFF).to_double()
  let fg = ((color >> 8) & 0xFF).to_double()
  let fb = (color & 0xFF).to_double()
  let x0 = if (min_x - 1.0).to_int() > 0 { (min_x - 1.0).to_int() } else { 0 }
  let x1 = if (max_x + 1.0).to_int() < buf.width {
    (max_x + 1.0).to_int()
  } else {
    buf.width
  }
  let y0 = if (min_y - 1.0).to_int() > 0 { (min_y - 1.0).to_int() } else { 0 }
  let y1 = if (max_y + 1.0).to_int() < buf.height {
    (max_y + 1.0).to_int()
  } else {
    buf.height
  }
  for py in y0..<y1 {
    for px in x0..<x1 {
      let mut cov = 0
      for sy in 0..<4 {
        let s = py.to_double() + (sy.to_double() + 0.5) * 0.25
        for sx in 0..<4 {
          let t = px.to_double() + (sx.to_double() + 0.5) * 0.25
          if winding_at(edges, t, s) != 0 {
            cov = cov + 1
          }
        }
      }
      if cov > 0 {
        let c = cov.to_double() / 16.0
        let bg = buf.get_rgb(px, py)
        let nr = (((bg >> 16) & 0xFF).to_double() * (1.0 - c) + fr * c).to_int() &
          0xFF
        let ng = (((bg >> 8) & 0xFF).to_double() * (1.0 - c) + fg * c).to_int() &
          0xFF
        let nb = ((bg & 0xFF).to_double() * (1.0 - c) + fb * c).to_int() & 0xFF
        let na = (((bg >> 24) & 0xFF).to_double() * (1.0 - c) + 255.0 * c).to_int() &
          0xFF
        buf.set_rgb(px, py, (na << 24) | (nr << 16) | (ng << 8) | nb)
      }
    }
  }
}

///|
/// 绘制单个字符（内部使用）。
fn Font::draw_char(
  self : Font,
  buf : PixelBuffer,
  ch : Char,
  ax : Double,
  ay : Double,
  size : Int,
  color : Int,
  cos : Double,
  sin : Double,
) -> Int {
  let gid = self.char_glyph(ch)
  if gid < 0 {
    return 0
  }
  let polygons = self.glyph_polygons(gid, size, ax, ay, cos, sin)
  paint_polygons(buf, polygons, color)
  let scale = size.to_double() / self.units_per_em.to_double()
  (self.glyph_advance(gid).to_double() * scale).to_int()
}

///|
/// 绘制文本： 为基线左端点，rotation_deg 绕锚点旋转。
/// 返回结束位置的 x（供布局调用方使用）。
pub fn Font::draw_text(
  self : Font,
  buf : PixelBuffer,
  text : String,
  x : Int,
  y : Int,
  size : Int,
  color : Int,
  rotation_deg : Double,
) -> Int {
  let rad = rotation_deg * 0.017453292519943295
  let cos = dcos(rad)
  let sin = dsin(rad)
  let mut pen = x.to_double()
  for ch in text.iter() {
    let adv = self.draw_char(buf, ch, pen, y.to_double(), size, color, cos, sin)
    pen = pen + adv.to_double()
  }
  pen.to_int()
}

///|
/// 文本宽度估算，对齐 AbstractCaptchaService#getEnOrChLength：
/// 非 ASCII 字符按 han_zi_size/2 计（+5），ASCII 按 8 计。
pub fn estimate_text_width(text : String, han_zi_size : Int) -> Int {
  let mut ch_cnt = 0
  let mut en_cnt = 0
  for c in text.iter() {
    if c.to_int() > 0x7F {
      ch_cnt = ch_cnt + 1
    } else {
      en_cnt = en_cnt + 1
    }
  }
  han_zi_size / 2 * ch_cnt + 5 + en_cnt * 8
}

///|
/// 右下角白色水印，位置对齐 AJ-Captcha：x = width - 估算宽，y = height - 字号/2 + 7。
pub fn Font::draw_watermark(
  self : Font,
  buf : PixelBuffer,
  text : String,
  han_zi_size : Int,
) -> Unit {
  if text.length() == 0 {
    return
  }
  let size = han_zi_size / 2
  let tw = estimate_text_width(text, han_zi_size)
  let _ = self.draw_text(
    buf,
    text,
    buf.width - tw,
    buf.height - han_zi_size / 2 + 7,
    size,
    0xFFFFFFFF,
    0.0,
  )
}
