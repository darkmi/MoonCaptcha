///|
/// PNG 编解码（8-bit、colorType 2 RGB / 6 RGBA、非隔行）。
/// 解码端支持全部 5 种行滤波（None/Sub/Up/Average/Paeth）；
/// 编码端固定 RGBA + filter 0 + zlib stored 块（合法但未压缩，见 zlib.mbt）。

///|
/// 解码出的 PNG 图像：RGBA 字节序（每像素 4 字节，值域 0..255）。
pub(all) struct PngImage {
  width : Int
  height : Int
  rgba : FixedArray[Int]
}

///|
fn type_code(a : Int, b : Int, c : Int, d : Int) -> Int {
  (a << 24) | (b << 16) | (c << 8) | d
}

///|
let t_ihdr : Int = type_code(73, 72, 68, 82)

///|
let t_idat : Int = type_code(73, 68, 65, 84)

///|
let t_iend : Int = type_code(73, 69, 78, 68)

///|
let crc_table : FixedArray[UInt] = build_crc_table()

///|
fn build_crc_table() -> FixedArray[UInt] {
  let t : FixedArray[UInt] = FixedArray::make(256, 0U)
  for n in 0..<256 {
    let mut c : UInt = n.reinterpret_as_uint()
    for _k in 0..<8 {
      let low = c & 1U
      c = c >> 1
      if low == 1U {
        c = c ^ 0xEDB88320U
      }
    }
    t[n] = c
  }
  t
}

///|
/// CRC-32（IEEE 802.3，PNG chunk 校验用）。
pub fn crc32(data : FixedArray[Int]) -> Int {
  let mut c : UInt = 0xFFFFFFFFU
  for b in data {
    let idx = ((c ^ b.reinterpret_as_uint()) & 0xFFU).reinterpret_as_int()
    c = crc_table[idx] ^ (c >> 8)
  }
  (c ^ 0xFFFFFFFFU).reinterpret_as_int()
}

///|
fn crc32_update(c0 : UInt, data : FixedArray[Int], start : Int, end : Int) -> UInt {
  let mut c : UInt = c0
  for i in start..<end {
    let idx = ((c ^ data[i].reinterpret_as_uint()) & 0xFFU).reinterpret_as_int()
    c = crc_table[idx] ^ (c >> 8)
  }
  c
}

///|
fn read_u32be(data : FixedArray[Int], off : Int) -> Int {
  (data[off] << 24) | (data[off + 1] << 16) | (data[off + 2] << 8) | data[off + 3]
}

///|
fn push_u32be(out : Array[Int], v : Int) -> Unit {
  out.push((v >> 24) & 0xFF)
  out.push((v >> 16) & 0xFF)
  out.push((v >> 8) & 0xFF)
  out.push(v & 0xFF)
}

///|
fn push_chunk(out : Array[Int], t : Int, data : FixedArray[Int]) -> Unit {
  push_u32be(out, data.length())
  out.push((t >> 24) & 0xFF)
  out.push((t >> 16) & 0xFF)
  out.push((t >> 8) & 0xFF)
  out.push(t & 0xFF)
  for b in data {
    out.push(b)
  }
  // CRC 覆盖 type + data
  let mut c : UInt = 0xFFFFFFFFU
  let type_and_data : FixedArray[Int] = FixedArray::make(4 + data.length(), 0)
  type_and_data[0] = (t >> 24) & 0xFF
  type_and_data[1] = (t >> 16) & 0xFF
  type_and_data[2] = (t >> 8) & 0xFF
  type_and_data[3] = t & 0xFF
  for i in 0..<data.length() {
    type_and_data[4 + i] = data[i]
  }
  c = crc32_update(c, type_and_data, 0, type_and_data.length())
  let crc = (c ^ 0xFFFFFFFFU).reinterpret_as_int()
  push_u32be(out, crc)
}

///|
/// Paeth 预测器（PNG 规范滤波类型 4）。
fn paeth_predict(a : Int, b : Int, c : Int) -> Int {
  let p = a + b - c
  let pa = if p - a < 0 { a - p } else { p - a }
  let pb = if p - b < 0 { b - p } else { p - b }
  let pc = if p - c < 0 { c - p } else { p - c }
  if pa <= pb && pa <= pc {
    a
  } else if pb <= pc {
    b
  } else {
    c
  }
}

///|
/// 解码 PNG → PngImage。
/// 说明：解码端不校验 chunk CRC（宽容策略，编码端保证 CRC 正确）。
pub fn decode_png(bytes : FixedArray[Int]) -> Result[PngImage, String] {
  let signature : Array[Int] = [137, 80, 78, 71, 13, 10, 26, 10]
  if bytes.length() < 8 {
    return Err("not a png")
  }
  for i in 0..<8 {
    if bytes[i] != signature[i] {
      return Err("not a png")
    }
  }
  let mut pos = 8
  let mut width = 0
  let mut height = 0
  let mut bit_depth = 0
  let mut color_type = 0
  let mut interlace = 0
  let mut ihdr_seen = false
  let idat : Array[Int] = []
  let mut finished = false
  let mut err : String = ""
  while !finished {
    if pos + 12 > bytes.length() {
      err = "truncated chunk"
      finished = true
      break
    }
    let len = read_u32be(bytes, pos)
    let ctype = read_u32be(bytes, pos + 4)
    if len < 0 || pos + 12 + len > bytes.length() {
      err = "truncated chunk data"
      finished = true
      break
    }
    if ctype == t_ihdr {
      if len != 13 {
        err = "invalid IHDR length"
        finished = true
        break
      }
      width = read_u32be(bytes, pos + 8)
      height = read_u32be(bytes, pos + 12)
      bit_depth = bytes[pos + 16]
      color_type = bytes[pos + 17]
      interlace = bytes[pos + 20]
      ihdr_seen = true
    } else if ctype == t_idat {
      for i in 0..<len {
        idat.push(bytes[pos + 8 + i])
      }
    } else if ctype == t_iend {
      finished = true
      break
    }
    pos = pos + 12 + len
  }
  if err != "" {
    return Err(err)
  }
  if !ihdr_seen {
    return Err("missing IHDR")
  }
  if idat.length() == 0 {
    return Err("missing IDAT")
  }
  if width <= 0 || height <= 0 {
    return Err("invalid dimensions")
  }
  if bit_depth != 8 {
    return Err("unsupported bit depth \{bit_depth}")
  }
  if color_type != 2 && color_type != 6 {
    return Err("unsupported color type \{color_type}")
  }
  if interlace != 0 {
    return Err("interlaced png not supported")
  }
  let raw = match zlib_decompress(@common.fixed_from_array(idat)) {
    Ok(d) => d
    Err(e) => return Err(e)
  }
  let bpp = if color_type == 6 { 4 } else { 3 }
  let stride = width * bpp
  if raw.length() != (stride + 1) * height {
    return Err("corrupt pixel data")
  }
  // 逆滤波（PNG 规范 §6）
  let recon : FixedArray[Int] = FixedArray::make(stride * height, 0)
  for y in 0..<height {
    let filter = raw[y * (stride + 1)]
    let row_start = y * stride
    for x in 0..<stride {
      let a = if x >= bpp { recon[row_start + x - bpp] } else { 0 }
      let b = if y > 0 { recon[row_start - stride + x] } else { 0 }
      let c = if y > 0 && x >= bpp {
        recon[row_start - stride + x - bpp]
      } else {
        0
      }
      let v0 = raw[y * (stride + 1) + 1 + x]
      let v = match filter {
        0 => v0
        1 => v0 + a
        2 => v0 + b
        3 => v0 + ((a + b) >> 1)
        4 => v0 + paeth_predict(a, b, c)
        _ => -1
      }
      if v < 0 {
        return Err("invalid filter type \{filter}")
      }
      recon[row_start + x] = v & 0xFF
    }
  }
  // 展开 RGBA
  let rgba : FixedArray[Int] = FixedArray::make(width * height * 4, 0)
  for i in 0..<(width * height) {
    if color_type == 6 {
      rgba[i * 4] = recon[i * 4]
      rgba[i * 4 + 1] = recon[i * 4 + 1]
      rgba[i * 4 + 2] = recon[i * 4 + 2]
      rgba[i * 4 + 3] = recon[i * 4 + 3]
    } else {
      rgba[i * 4] = recon[i * 3]
      rgba[i * 4 + 1] = recon[i * 3 + 1]
      rgba[i * 4 + 2] = recon[i * 3 + 2]
      rgba[i * 4 + 3] = 255
    }
  }
  Ok({ width, height, rgba })
}

///|
/// 将 PngImage 编码为 PNG 字节流（RGBA + filter 0 + zlib stored）。
pub fn encode_png(img : PngImage) -> FixedArray[Int] {
  let out : Array[Int] = [137, 80, 78, 71, 13, 10, 26, 10]
  let ihdr : FixedArray[Int] = FixedArray::make(13, 0)
  ihdr[0] = (img.width >> 24) & 0xFF
  ihdr[1] = (img.width >> 16) & 0xFF
  ihdr[2] = (img.width >> 8) & 0xFF
  ihdr[3] = img.width & 0xFF
  ihdr[4] = (img.height >> 24) & 0xFF
  ihdr[5] = (img.height >> 16) & 0xFF
  ihdr[6] = (img.height >> 8) & 0xFF
  ihdr[7] = img.height & 0xFF
  ihdr[8] = 8
  ihdr[9] = 6
  ihdr[10] = 0
  ihdr[11] = 0
  ihdr[12] = 0
  push_chunk(out, t_ihdr, ihdr)
  let stride = img.width * 4
  let raw : FixedArray[Int] = FixedArray::make((stride + 1) * img.height, 0)
  for y in 0..<img.height {
    raw[y * (stride + 1)] = 0
    for x in 0..<stride {
      raw[y * (stride + 1) + 1 + x] = img.rgba[y * stride + x]
    }
  }
  push_chunk(out, t_idat, zlib_compress_stored(raw))
  push_chunk(out, t_iend, FixedArray::make(0, 0))
  @common.fixed_from_array(out)
}

///|
/// RGBA 字节序 → ARGB 打包（PixelBuffer 布局）。
pub fn PixelBuffer::from_png_image(img : PngImage) -> PixelBuffer {
  let buf = PixelBuffer::new(img.width, img.height)
  for i in 0..<(img.width * img.height) {
    let r = img.rgba[i * 4]
    let g = img.rgba[i * 4 + 1]
    let b = img.rgba[i * 4 + 2]
    let a = img.rgba[i * 4 + 3]
    buf.pixels[i] = ((a & 0xFF) << 24) | ((r & 0xFF) << 16) | ((g & 0xFF) << 8) | (b & 0xFF)
  }
  buf
}

///|
/// ARGB 打包 → RGBA 字节序。
pub fn PixelBuffer::to_png_image(self : PixelBuffer) -> PngImage {
  let n = self.width * self.height
  let rgba : FixedArray[Int] = FixedArray::make(n * 4, 0)
  for i in 0..<n {
    let p = self.pixels[i]
    rgba[i * 4] = (p >> 16) & 0xFF
    rgba[i * 4 + 1] = (p >> 8) & 0xFF
    rgba[i * 4 + 2] = p & 0xFF
    rgba[i * 4 + 3] = (p >> 24) & 0xFF
  }
  { width: self.width, height: self.height, rgba }
}
