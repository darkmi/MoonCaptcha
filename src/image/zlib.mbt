///|
/// zlib / DEFLATE 纯 MoonBit 实现（RFC 1950 / 1951），供 PNG 编解码使用。
/// - 解压：支持 stored / fixed Huffman / dynamic Huffman 三种块型
/// - 压缩：仅 stored 块（合法但未压缩，首版策略；后续可加 Huffman 编码）
/// 字节统一用 FixedArray[Int]（值域 0..255）。

///|
/// LSB-first 位读取器（RFC 1951 §3.1.1）。
priv struct BitReader {
  data : FixedArray[Int]
  mut byte_pos : Int
  mut bit_buf : Int
  mut bit_cnt : Int
}

///|
fn BitReader::new(data : FixedArray[Int]) -> BitReader {
  { data, byte_pos: 0, bit_buf: 0, bit_cnt: 0, }
}

///|
fn BitReader::read_bits(self : BitReader, n : Int) -> Result[Int, String] {
  while self.bit_cnt < n {
    if self.byte_pos >= self.data.length() {
      return Err("unexpected end of deflate data")
    }
    self.bit_buf = self.bit_buf | (self.data[self.byte_pos] << self.bit_cnt)
    self.byte_pos = self.byte_pos + 1
    self.bit_cnt = self.bit_cnt + 8
  }
  let v = self.bit_buf & ((1 << n) - 1)
  self.bit_buf = self.bit_buf >> n
  self.bit_cnt = self.bit_cnt - n
  Ok(v)
}

///|
/// 丢弃未对齐的剩余位（stored 块前调用）。
fn BitReader::align_byte(self : BitReader) -> Unit {
  self.bit_buf = 0
  self.bit_cnt = 0
}

///|
/// 规范 Huffman 解码表（RFC 1951 §3.2.2）。
priv struct HuffmanTable {
  /// counts[len] = 长度为 len 的码字数量（len 1..15）
  counts : FixedArray[Int]
  /// 按码长、符号值排序的符号表
  symbols : FixedArray[Int]
}

///|
/// 由码长表构建规范 Huffman 表；拒绝超载（over-subscribed）的码长集。
fn huffman_build(lengths : FixedArray[Int]) -> Result[HuffmanTable, String] {
  let counts : FixedArray[Int] = FixedArray::make(16, 0)
  for l in lengths {
    counts[l] = counts[l] + 1
  }
  counts[0] = 0
  // 超载检查：Kraft 不等式
  let mut left = 1
  for len in 1..<16 {
    left = (left << 1) - counts[len]
    if left < 0 {
      return Err("oversubscribed huffman code lengths")
    }
  }
  let offsets : FixedArray[Int] = FixedArray::make(16, 0)
  for len in 1..<16 {
    offsets[len] = offsets[len - 1] + counts[len - 1]
  }
  let symbols : FixedArray[Int] = FixedArray::make(lengths.length(), 0)
  for sym in 0..<lengths.length() {
    let l = lengths[sym]
    if l != 0 {
      symbols[offsets[l]] = sym
      offsets[l] = offsets[l] + 1
    }
  }
  Ok({ counts, symbols, })
}

///|
/// 解码单个符号（逐位下行，zlib puff 算法）。
fn HuffmanTable::decode(
  self : HuffmanTable,
  br : BitReader,
) -> Result[Int, String] {
  let mut code = 0
  let mut first = 0
  let mut index = 0
  for len in 1..<16 {
    let bit = match br.read_bits(1) {
      Ok(b) => b
      Err(e) => return Err(e)
    }
    code = code | bit
    let count = self.counts[len]
    if code - first < count {
      return Ok(self.symbols[index + code - first])
    }
    index = index + count
    first = (first + count) << 1
    code = code << 1
  }
  Err("invalid huffman code")
}

///|
let fixed_lit_table : HuffmanTable = build_fixed_lit_table()

///|
let fixed_dist_table : HuffmanTable = build_fixed_dist_table()

///|
fn build_fixed_lit_table() -> HuffmanTable {
  let lengths : FixedArray[Int] = FixedArray::make(288, 0)
  for i in 0..<144 {
    lengths[i] = 8
  }
  for i in 144..<256 {
    lengths[i] = 9
  }
  for i in 256..<280 {
    lengths[i] = 7
  }
  for i in 280..<288 {
    lengths[i] = 8
  }
  match huffman_build(lengths) {
    Ok(t) => t
    Err(_) => abort("unreachable")
  }
}

///|
fn build_fixed_dist_table() -> HuffmanTable {
  let lengths : FixedArray[Int] = FixedArray::make(32, 5)
  match huffman_build(lengths) {
    Ok(t) => t
    Err(_) => abort("unreachable")
  }
}

///|
/// 长度符号 257..285 的基础长度（RFC 1951 §3.2.5）。
let len_base : FixedArray[Int] = @common.fixed_from_array([
  3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83,
  99, 115, 131, 163, 195, 227, 258,
])

///|
let len_extra : FixedArray[Int] = @common.fixed_from_array([
  0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5,
  5, 0,
])

///|
/// 距离符号 0..29 的基础距离。
let dist_base : FixedArray[Int] = @common.fixed_from_array([
  1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769,
  1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577,
])

///|
let dist_extra : FixedArray[Int] = @common.fixed_from_array([
  0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11,
  12, 12, 13, 13,
])

///|
/// 读取 dynamic 块的码长并构建 lit/len 与 dist 两张 Huffman 表。
fn read_dynamic_tables(
  br : BitReader,
) -> Result[(HuffmanTable, HuffmanTable), String] {
  let hlit = match br.read_bits(5) {
    Ok(v) => 257 + v
    Err(e) => return Err(e)
  }
  let hdist = match br.read_bits(5) {
    Ok(v) => 1 + v
    Err(e) => return Err(e)
  }
  let hclen = match br.read_bits(4) {
    Ok(v) => 4 + v
    Err(e) => return Err(e)
  }
  let order : Array[Int] = [
    16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15,
  ]
  let cl_lengths : FixedArray[Int] = FixedArray::make(19, 0)
  for i in 0..<hclen {
    let v = match br.read_bits(3) {
      Ok(v) => v
      Err(e) => return Err(e)
    }
    cl_lengths[order[i]] = v
  }
  let cl_table = match huffman_build(cl_lengths) {
    Ok(t) => t
    Err(e) => return Err(e)
  }
  let lit_lengths : FixedArray[Int] = FixedArray::make(hlit, 0)
  let dist_lengths : FixedArray[Int] = FixedArray::make(hdist, 0)
  // 先读 lit/len 码长（16/17/18 的重复区间可跨入 dist 码长，但 PNG 数据中不会出现，
  // 这里按两段独立解码的简化处理——与 puff 一致的做法是合并解码，见下方循环）
  let all_lengths : FixedArray[Int] = FixedArray::make(hlit + hdist, 0)
  let mut i = 0
  let total = hlit + hdist
  let mut err : String = ""
  let mut failed = false
  while i < total && !failed {
    let sym = match cl_table.decode(br) {
      Ok(s) => s
      Err(e) => {
        err = e
        failed = true
        break
      }
    }
    if sym < 16 {
      all_lengths[i] = sym
      i = i + 1
    } else if sym == 16 {
      if i == 0 {
        err = "length repeat with no previous length"
        failed = true
        break
      }
      let prev = all_lengths[i - 1]
      let rep = match br.read_bits(2) {
        Ok(v) => 3 + v
        Err(e) => {
          err = e
          failed = true
          break
        }
      }
      for _k in 0..<rep {
        if i < total {
          all_lengths[i] = prev
          i = i + 1
        }
      }
    } else if sym == 17 {
      let rep = match br.read_bits(3) {
        Ok(v) => 3 + v
        Err(e) => {
          err = e
          failed = true
          break
        }
      }
      for _k in 0..<rep {
        if i < total {
          all_lengths[i] = 0
          i = i + 1
        }
      }
    } else {
      let rep = match br.read_bits(7) {
        Ok(v) => 11 + v
        Err(e) => {
          err = e
          failed = true
          break
        }
      }
      for _k in 0..<rep {
        if i < total {
          all_lengths[i] = 0
          i = i + 1
        }
      }
    }
  }
  if failed {
    return Err(err)
  }
  for j in 0..<hlit {
    lit_lengths[j] = all_lengths[j]
  }
  for j in 0..<hdist {
    dist_lengths[j] = all_lengths[hlit + j]
  }
  let lit_table = match huffman_build(lit_lengths) {
    Ok(t) => t
    Err(e) => return Err(e)
  }
  let dist_table = match huffman_build(dist_lengths) {
    Ok(t) => t
    Err(e) => return Err(e)
  }
  Ok((lit_table, dist_table))
}

///|
/// 解码一个 Huffman 块的所有符号到 out。
fn inflate_block(
  br : BitReader,
  out : Array[Int],
  lit_table : HuffmanTable,
  dist_table : HuffmanTable,
) -> Result[Unit, String] {
  while true {
    let sym = match lit_table.decode(br) {
      Ok(s) => s
      Err(e) => return Err(e)
    }
    if sym < 256 {
      out.push(sym)
    } else if sym == 256 {
      return Ok(())
    } else {
      let idx = sym - 257
      if idx >= len_base.length() {
        return Err("invalid length symbol")
      }
      let extra = match br.read_bits(len_extra[idx]) {
        Ok(v) => v
        Err(e) => return Err(e)
      }
      let length = len_base[idx] + extra
      let dsym = match dist_table.decode(br) {
        Ok(s) => s
        Err(e) => return Err(e)
      }
      if dsym >= dist_base.length() {
        return Err("invalid distance symbol")
      }
      let dextra = match br.read_bits(dist_extra[dsym]) {
        Ok(v) => v
        Err(e) => return Err(e)
      }
      let dist = dist_base[dsym] + dextra
      if dist > out.length() {
        return Err("distance too far back")
      }
      // 允许重叠引用：逐字节复制
      for _k in 0..<length {
        out.push(out[out.length() - dist])
      }
    }
  }
  Ok(())
}

///|
/// 原始 DEFLATE 解压（RFC 1951）。
fn inflate(data : FixedArray[Int]) -> Result[FixedArray[Int], String] {
  let br = BitReader::new(data)
  let out : Array[Int] = []
  let mut running = true
  let mut err : String = ""
  while running {
    let bfinal = match br.read_bits(1) {
      Ok(v) => v
      Err(e) => {
        err = e
        running = false
        break
      }
    }
    let btype = match br.read_bits(2) {
      Ok(v) => v
      Err(e) => {
        err = e
        running = false
        break
      }
    }
    let block_result : Result[Unit, String] = if btype == 0 {
      inflate_stored_block(br, out)
    } else if btype == 1 {
      inflate_block(br, out, fixed_lit_table, fixed_dist_table)
    } else if btype == 2 {
      match read_dynamic_tables(br) {
        Ok((lit, dist)) => inflate_block(br, out, lit, dist)
        Err(e) => Err(e)
      }
    } else {
      Err("invalid block type 3")
    }
    match block_result {
      Ok(_) => ()
      Err(e) => {
        err = e
        running = false
        break
      }
    }
    if bfinal == 1 {
      running = false
    }
  }
  if err != "" {
    return Err(err)
  }
  Ok(@common.fixed_from_array(out))
}

///|
fn inflate_stored_block(
  br : BitReader,
  out : Array[Int],
) -> Result[Unit, String] {
  br.align_byte()
  let len = match br.read_bits(16) {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let nlen = match br.read_bits(16) {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  if (len ^ 0xFFFF) != nlen {
    return Err("stored block LEN/NLEN mismatch")
  }
  for _k in 0..<len {
    let b = match br.read_bits(8) {
      Ok(v) => v
      Err(e) => return Err(e)
    }
    out.push(b)
  }
  Ok(())
}

///|
/// Adler-32（RFC 1950 §8）。
pub fn adler32(data : FixedArray[Int]) -> Int {
  let mut a = 1
  let mut b = 0
  for x in data {
    a = (a + x) % 65521
    b = (b + a) % 65521
  }
  (b << 16) | a
}

///|
/// zlib 解压（RFC 1950 包装 + 原始 DEFLATE），校验 adler32。
pub fn zlib_decompress(
  data : FixedArray[Int],
) -> Result[FixedArray[Int], String] {
  if data.length() < 6 {
    return Err("zlib data too short")
  }
  let cmf = data[0]
  let flg = data[1]
  if (cmf & 0x0F) != 8 {
    return Err("unsupported compression method")
  }
  if (cmf * 256 + flg) % 31 != 0 {
    return Err("bad zlib header check")
  }
  if (flg & 0x20) != 0 {
    return Err("preset dictionary not supported")
  }
  let payload = slice_bytes(data, 2, data.length() - 4)
  let out = match inflate(payload) {
    Ok(o) => o
    Err(e) => return Err(e)
  }
  let expect = (data[data.length() - 4] << 24) |
    (data[data.length() - 3] << 16) |
    (data[data.length() - 2] << 8) |
    data[data.length() - 1]
  if adler32(out) != expect {
    return Err("adler32 mismatch")
  }
  Ok(out)
}

///|
/// zlib 压缩（stored 块，未压缩但合法；支持任意大小，自动分块 ≤65535 字节）。
pub fn zlib_compress_stored(data : FixedArray[Int]) -> FixedArray[Int] {
  let out : Array[Int] = []
  out.push(0x78)
  out.push(0x01)
  let n = data.length()
  if n == 0 {
    out.push(0x01)
    out.push(0)
    out.push(0)
    out.push(0xFF)
    out.push(0xFF)
  } else {
    let mut off = 0
    while off < n {
      let chunk = if n - off > 65535 { 65535 } else { n - off }
      let bfinal = if off + chunk >= n { 1 } else { 0 }
      out.push(bfinal)
      out.push(chunk & 0xFF)
      out.push((chunk >> 8) & 0xFF)
      let nlen = 0xFFFF - chunk
      out.push(nlen & 0xFF)
      out.push((nlen >> 8) & 0xFF)
      for i in off..<(off + chunk) {
        out.push(data[i])
      }
      off = off + chunk
    }
  }
  let ad = adler32(data)
  out.push((ad >> 24) & 0xFF)
  out.push((ad >> 16) & 0xFF)
  out.push((ad >> 8) & 0xFF)
  out.push(ad & 0xFF)
  @common.fixed_from_array(out)
}

///|
fn slice_bytes(
  data : FixedArray[Int],
  start : Int,
  end : Int,
) -> FixedArray[Int] {
  let n = if end < start { 0 } else { end - start }
  let out : FixedArray[Int] = FixedArray::make(n, 0)
  for i in 0..<n {
    out[i] = data[start + i]
  }
  out
}
