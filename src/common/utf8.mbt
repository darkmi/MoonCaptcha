///|
/// String → UTF-8 字节序列（值域 0..255 的 FixedArray[Int]）。
pub fn utf8_encode(text : String) -> FixedArray[Int] {
  let out : Array[Int] = []
  for c in text.iter() {
    let cp = c.to_int()
    if cp < 0x80 {
      out.push(cp)
    } else if cp < 0x800 {
      out.push(0xC0 | (cp >> 6))
      out.push(0x80 | (cp & 0x3F))
    } else if cp < 0x10000 {
      out.push(0xE0 | (cp >> 12))
      out.push(0x80 | ((cp >> 6) & 0x3F))
      out.push(0x80 | (cp & 0x3F))
    } else {
      out.push(0xF0 | (cp >> 18))
      out.push(0x80 | ((cp >> 12) & 0x3F))
      out.push(0x80 | ((cp >> 6) & 0x3F))
      out.push(0x80 | (cp & 0x3F))
    }
  }
  fixed_from_array(out)
}

///|
/// UTF-8 字节序列 → String。非法字节以 U+FFFD 替换（不抛错）。
pub fn utf8_decode(bytes : FixedArray[Int]) -> String {
  let buf = StringBuilder()
  let n = bytes.length()
  let mut i = 0
  while i < n {
    let b = bytes[i]
    let mut cp = 0
    let mut width = 1
    if b < 0x80 {
      cp = b
      width = 1
    } else if b >= 0xC2 && b < 0xE0 && i + 1 < n && is_cont(bytes[i + 1]) {
      cp = ((b & 0x1F) << 6) | (bytes[i + 1] & 0x3F)
      width = 2
    } else if b >= 0xE0 &&
      b < 0xF0 &&
      i + 2 < n &&
      is_cont(bytes[i + 1]) &&
      is_cont(bytes[i + 2]) {
      cp = ((b & 0x0F) << 12) |
        ((bytes[i + 1] & 0x3F) << 6) |
        (bytes[i + 2] & 0x3F)
      width = 3
    } else if b >= 0xF0 &&
      b < 0xF5 &&
      i + 3 < n &&
      is_cont(bytes[i + 1]) &&
      is_cont(bytes[i + 2]) &&
      is_cont(bytes[i + 3]) {
      cp = ((b & 0x07) << 18) |
        ((bytes[i + 1] & 0x3F) << 12) |
        ((bytes[i + 2] & 0x3F) << 6) |
        (bytes[i + 3] & 0x3F)
      width = 4
    } else {
      cp = 0xFFFD
      width = 1
    }
    write_code_point(buf, cp)
    i = i + width
  }
  buf.to_string()
}

///|
fn is_cont(b : Int) -> Bool {
  b >= 0x80 && b < 0xC0
}

///|
/// Array[Int] → FixedArray[Int] 的收拢工具。
pub fn fixed_from_array(items : Array[Int]) -> FixedArray[Int] {
  let out : FixedArray[Int] = FixedArray::make(items.length(), 0)
  for i in 0..<items.length() {
    out[i] = items[i]
  }
  out
}
