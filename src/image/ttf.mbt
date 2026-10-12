///|
/// TrueType 字体解析（sfnt 容器，glyf 二次贝塞尔轮廓）。
/// 支持：表目录定位、head/maxp/hhea/hmtx、cmap format 4（BMP 子表）、
/// loca（短/长格式）、glyf 简单轮廓与复合轮廓（平移/缩放分量）。
/// 按需惰性解析字形——字体文件可达数 MB，全部常驻字节缓冲即可。

///|
/// 字形轮廓点：字体单位，y 轴向上；on_curve 标记二次贝塞尔锚点/控制点。
pub(all) struct GlyphPoint {
  x : Int
  y : Int
  on_curve : Bool
}

///|
/// 解析出的字形：完整轮廓点序列 + 每条闭合轮廓的终点下标 + 步进宽度。
pub(all) struct GlyphOutline {
  points : Array[GlyphPoint]
  contour_ends : Array[Int]
  advance : Int
}

///|
pub struct Font {
  data : FixedArray[Int]
  glyf_off : Int
  loca_off : Int
  loca_long : Bool
  cmap_off : Int
  hmtx_off : Int
  num_glyphs : Int
  num_h_metrics : Int
  units_per_em : Int
}

///|
fn read_u16(data : FixedArray[Int], off : Int) -> Int {
  (data[off] << 8) | data[off + 1]
}

///|
fn read_i16(data : FixedArray[Int], off : Int) -> Int {
  let v = read_u16(data, off)
  if v >= 0x8000 {
    v - 0x10000
  } else {
    v
  }
}

///|
fn read_u32(data : FixedArray[Int], off : Int) -> Int {
  (data[off] << 24) |
  (data[off + 1] << 16) |
  (data[off + 2] << 8) |
  data[off + 3]
}

///|
fn tag_code(data : FixedArray[Int], off : Int) -> Int {
  read_u32(data, off)
}

///|
/// 解析字体文件。仅要求 sfnt 0x00010000 版本（TrueType outlines）；
/// CFF（PostScript outlines，常见于 .otf）不受支持。
pub fn Font::parse(bytes : FixedArray[Int]) -> Result[Font, String] {
  if bytes.length() < 12 {
    return Err("font data too short")
  }
  if read_u32(bytes, 0) != 0x00010000 {
    return Err("unsupported sfnt version (only TrueType glyf)")
  }
  let num_tables = read_u16(bytes, 4)
  let mut head_off = -1
  let mut maxp_off = -1
  let mut hhea_off = -1
  let mut cmap_off = -1
  let mut loca_off = -1
  let mut glyf_off = -1
  let mut hmtx_off = -1
  let mut i = 0
  while i < num_tables {
    let rec = 12 + i * 16
    if rec + 16 > bytes.length() {
      return Err("truncated table directory")
    }
    let tag = tag_code(bytes, rec)
    let off = read_u32(bytes, rec + 8)
    match tag {
      0x68656164 => head_off = off // "head"
      0x6D617870 => maxp_off = off // "maxp"
      0x68686561 => hhea_off = off // "hhea"
      0x636D6170 => cmap_off = off // "cmap"
      0x6C6F6361 => loca_off = off // "loca"
      0x676C7966 => glyf_off = off // "glyf"
      0x686D7478 => hmtx_off = off // "hmtx"
      _ => ()
    }
    i = i + 1
  }
  if head_off < 0 ||
    maxp_off < 0 ||
    hhea_off < 0 ||
    cmap_off < 0 ||
    loca_off < 0 ||
    glyf_off < 0 ||
    hmtx_off < 0 {
    return Err("missing required table")
  }
  if head_off + 54 > bytes.length() {
    return Err("truncated head table")
  }
  let units_per_em = read_u16(bytes, head_off + 18)
  let loca_long = read_i16(bytes, head_off + 50) != 0
  if units_per_em <= 0 {
    return Err("invalid unitsPerEm")
  }
  if maxp_off + 6 > bytes.length() {
    return Err("truncated maxp table")
  }
  let num_glyphs = read_u16(bytes, maxp_off + 4)
  if hhea_off + 36 > bytes.length() {
    return Err("truncated hhea table")
  }
  let num_h_metrics = read_u16(bytes, hhea_off + 34)
  if num_glyphs <= 0 || num_h_metrics <= 0 {
    return Err("invalid glyph counts")
  }
  // cmap：优先 (3,1) Windows Unicode BMP，其次 (0,x) Unicode，最后第一个子表
  if cmap_off + 4 > bytes.length() {
    return Err("truncated cmap table")
  }
  let cmap_num = read_u16(bytes, cmap_off + 2)
  let mut sub_off = -1
  let mut fallback_off = -1
  let mut k = 0
  while k < cmap_num {
    let rec = cmap_off + 4 + k * 8
    if rec + 8 > bytes.length() {
      return Err("truncated cmap subtable record")
    }
    let platform = read_u16(bytes, rec)
    let encoding = read_u16(bytes, rec + 2)
    let off = read_u32(bytes, rec + 4)
    if sub_off < 0 {
      fallback_off = cmap_off + off
    }
    if (platform == 3 && encoding == 1) || platform == 0 {
      sub_off = cmap_off + off
    }
    k = k + 1
  }
  if sub_off < 0 {
    sub_off = fallback_off
  }
  if sub_off < 0 || sub_off + 2 > bytes.length() {
    return Err("no usable cmap subtable")
  }
  if read_u16(bytes, sub_off) != 4 {
    return Err("only cmap format 4 supported")
  }
  Ok({
    data: bytes,
    glyf_off,
    loca_off,
    loca_long,
    cmap_off: sub_off,
    hmtx_off,
    num_glyphs,
    num_h_metrics,
    units_per_em,
  })
}

///|
/// 字符 → 字形下标（cmap format 4 查找）；未映射返回 -1。
pub fn Font::char_glyph(self : Font, ch : Char) -> Int {
  let data = self.data
  let base = self.cmap_off
  let seg_count_x2 = read_u16(data, base + 6)
  let seg_count = seg_count_x2 / 2
  let end_base = base + 14
  let start_base = end_base + seg_count_x2 + 2
  let delta_base = start_base + seg_count_x2
  let range_base = delta_base + seg_count_x2
  let code = ch.to_int()
  // 二分找第一个 endCode >= code 的段
  let mut lo = 0
  let mut hi = seg_count - 1
  let mut found = -1
  while lo <= hi {
    let mid = (lo + hi) / 2
    if read_u16(data, end_base + mid * 2) >= code {
      found = mid
      hi = mid - 1
    } else {
      lo = mid + 1
    }
  }
  if found < 0 {
    return -1
  }
  let start = read_u16(data, start_base + found * 2)
  if code < start {
    return -1
  }
  let range_offset = read_u16(data, range_base + found * 2)
  if range_offset == 0 {
    let gid = (code + read_i16(data, delta_base + found * 2)) & 0xFFFF
    gid
  } else {
    // idRangeOffset 间接寻址（跨段映射，如符号区）
    let addr = range_base + found * 2 + range_offset + (code - start) * 2
    if addr + 1 >= data.length() {
      return -1
    }
    read_u16(data, addr)
  }
}

///|
/// 字形步进宽度（像素前的字体单位）。
pub fn Font::glyph_advance(self : Font, gid : Int) -> Int {
  if gid < 0 || gid >= self.num_h_metrics {
    let last = self.hmtx_off + (self.num_h_metrics - 1) * 4
    if last + 1 < self.data.length() {
      return read_u16(self.data, last)
    }
    return 0
  }
  read_u16(self.data, self.hmtx_off + gid * 4)
}

///|
fn Font::loca_entry(self : Font, gid : Int) -> Int {
  if gid > self.num_glyphs {
    return 0
  }
  if self.loca_long {
    read_u32(self.data, self.loca_off + gid * 4)
  } else {
    read_u16(self.data, self.loca_off + gid * 2) * 2
  }
}

///|
/// 解析字形轮廓（复合字形递归展开，深度限 4）。
pub fn Font::glyph_outline(
  self : Font,
  gid : Int,
) -> Result[GlyphOutline, String] {
  self.glyph_outline_inner(gid, 0)
}

///|
fn Font::glyph_outline_inner(
  self : Font,
  gid : Int,
  depth : Int,
) -> Result[GlyphOutline, String] {
  if gid < 0 || gid >= self.num_glyphs {
    return Err("glyph id out of range")
  }
  if depth > 4 {
    return Err("composite glyph nesting too deep")
  }
  let advance = self.glyph_advance(gid)
  let start = self.loca_entry(gid)
  let end = self.loca_entry(gid + 1)
  if end <= start {
    return Ok({ points: [], contour_ends: [], advance, })
  }
  let g = self.glyf_off + start
  if g + 10 > self.data.length() {
    return Err("truncated glyph")
  }
  let num_contours = read_i16(self.data, g)
  if num_contours >= 0 {
    self.parse_simple_glyph(g, num_contours, advance)
  } else {
    self.parse_composite_glyph(g, advance, depth)
  }
}

///|
fn Font::parse_simple_glyph(
  self : Font,
  g : Int,
  num_contours : Int,
  advance : Int,
) -> Result[GlyphOutline, String] {
  let data = self.data
  let n = read_u16(data, g + 10 + num_contours * 2 - 2) + 1
  let instr_len = read_u16(data, g + 10 + num_contours * 2)
  let flags_base = g + 10 + num_contours * 2 + 2 + instr_len
  // 解析 flags（bit3 repeat 展开）
  let flags : Array[Int] = []
  let mut fp = flags_base
  while flags.length() < n {
    if fp >= data.length() {
      return Err("truncated glyph flags")
    }
    let f = data[fp]
    fp = fp + 1
    flags.push(f)
    if (f & 0x08) != 0 {
      if fp >= data.length() {
        return Err("truncated glyph flag repeat")
      }
      let rep = data[fp]
      fp = fp + 1
      for _k in 0..<rep {
        if flags.length() < n {
          flags.push(f)
        }
      }
    }
  }
  // x 坐标增量
  let xs : Array[Int] = []
  let mut x = 0
  for f in flags {
    if (f & 0x02) != 0 {
      if fp >= data.length() {
        return Err("truncated x coords")
      }
      let d = data[fp]
      fp = fp + 1
      x = x + (if (f & 0x10) != 0 { d } else { -d })
    } else if (f & 0x10) == 0 {
      if fp + 1 >= data.length() {
        return Err("truncated x coords")
      }
      x = x + read_i16(data, fp)
      fp = fp + 2
    }
    xs.push(x)
  }
  // y 坐标增量
  let ys : Array[Int] = []
  let mut y = 0
  for f in flags {
    if (f & 0x04) != 0 {
      if fp >= data.length() {
        return Err("truncated y coords")
      }
      let d = data[fp]
      fp = fp + 1
      y = y + (if (f & 0x20) != 0 { d } else { -d })
    } else if (f & 0x20) == 0 {
      if fp + 1 >= data.length() {
        return Err("truncated y coords")
      }
      y = y + read_i16(data, fp)
      fp = fp + 2
    }
    ys.push(y)
  }
  let points : Array[GlyphPoint] = []
  for i in 0..<n {
    points.push({ x: xs[i], y: ys[i], on_curve: (flags[i] & 0x01) != 0, })
  }
  let contour_ends : Array[Int] = []
  for c in 0..<num_contours {
    contour_ends.push(read_u16(data, g + 10 + c * 2))
  }
  Ok({ points, contour_ends, advance, })
}

///|
/// 复合字形：ARGS_ARE_XY_VALUES 平移 + 线性缩放分量（F2Dot14）。
fn Font::parse_composite_glyph(
  self : Font,
  g : Int,
  advance : Int,
  depth : Int,
) -> Result[GlyphOutline, String] {
  let data = self.data
  let points : Array[GlyphPoint] = []
  let contour_ends : Array[Int] = []
  let mut p = g + 10
  let mut more = true
  while more {
    if p + 4 > data.length() {
      return Err("truncated composite glyph")
    }
    let flags = read_u16(data, p)
    let child_gid = read_u16(data, p + 2)
    p = p + 4
    let words = (flags & 0x0001) != 0
    let arg_size = if words { 4 } else { 2 }
    if p + arg_size > data.length() {
      return Err("truncated composite args")
    }
    let dx = if words {
      read_i16(data, p)
    } else {
      data[p] | ((data[p] & 0x80) * 0xFE)
    }
    let dy = if words {
      read_i16(data, p + 2)
    } else {
      data[p + 1] | ((data[p + 1] & 0x80) * 0xFE)
    }
    p = p + arg_size
    // 线性变换：默认单位阵
    let mut a = 16384
    let mut b = 0
    let mut c = 0
    let mut d = 16384
    if (flags & 0x0008) != 0 {
      // WE_HAVE_A_SCALE
      a = read_i16(data, p)
      d = a
      p = p + 2
    } else if (flags & 0x0040) != 0 {
      // WE_HAVE_AN_X_AND_Y_SCALE
      a = read_i16(data, p)
      d = read_i16(data, p + 2)
      p = p + 4
    } else if (flags & 0x0080) != 0 {
      // WE_HAVE_A_TWO_BY_TWO
      a = read_i16(data, p)
      b = read_i16(data, p + 2)
      c = read_i16(data, p + 4)
      d = read_i16(data, p + 6)
      p = p + 8
    }
    if !((flags & 0x0002) != 0) {
      return Err("composite glyph without XY value args not supported")
    }
    let child = match self.glyph_outline_inner(child_gid, depth + 1) {
      Ok(o) => o
      Err(e) => return Err(e)
    }
    let base = points.length()
    for pt in child.points {
      let nx = dx + (a * pt.x + b * pt.y) / 16384
      let ny = dy + (c * pt.x + d * pt.y) / 16384
      points.push({ x: nx, y: ny, on_curve: pt.on_curve, })
    }
    for e in child.contour_ends {
      contour_ends.push(e + base)
    }
    more = (flags & 0x0020) != 0
  }
  Ok({ points, contour_ends, advance, })
}
