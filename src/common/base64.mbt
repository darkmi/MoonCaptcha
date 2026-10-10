///|
/// 字节数组统一用 FixedArray[Int]（值域 0..255）表示，
/// 与 Java getRGB/setRGB、AES 教材式实现保持一致的位运算心智模型。

const B64_ALPHABET : String = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

///|
/// 标准 Base64 编码（RFC 4648，带 `=` 填充）。
pub fn base64_encode(data : FixedArray[Int]) -> String {
  let n = data.length()
  let buf = StringBuilder()
  let alphabet = B64_ALPHABET.to_array()
  let mut i = 0
  while i + 3 <= n {
    let v = (data[i] << 16) | (data[i + 1] << 8) | data[i + 2]
    buf.write_char(alphabet[(v >> 18) & 0x3F])
    buf.write_char(alphabet[(v >> 12) & 0x3F])
    buf.write_char(alphabet[(v >> 6) & 0x3F])
    buf.write_char(alphabet[v & 0x3F])
    i = i + 3
  }
  let remain = n - i
  if remain == 1 {
    let v = data[i] << 16
    buf.write_char(alphabet[(v >> 18) & 0x3F])
    buf.write_char(alphabet[(v >> 12) & 0x3F])
    buf.write_char('=')
    buf.write_char('=')
  } else if remain == 2 {
    let v = (data[i] << 16) | (data[i + 1] << 8)
    buf.write_char(alphabet[(v >> 18) & 0x3F])
    buf.write_char(alphabet[(v >> 12) & 0x3F])
    buf.write_char(alphabet[(v >> 6) & 0x3F])
    buf.write_char('=')
  }
  buf.to_string()
}

///|
fn b64_decode_char(c : Char) -> Int {
  if c >= 'A' && c <= 'Z' {
    return c.to_int() - 65
  }
  if c >= 'a' && c <= 'z' {
    return c.to_int() - 97 + 26
  }
  if c >= '0' && c <= '9' {
    return c.to_int() - 48 + 52
  }
  if c == '+' {
    return 62
  }
  if c == '/' {
    return 63
  }
  -1
}

///|
/// 标准 Base64 解码。非法输入返回 None。
pub fn base64_decode(text : String) -> FixedArray[Int]? {
  let chars = text.to_array()
  let data : Array[Int] = []
  let mut acc = 0
  let mut bits = 0
  let mut pad_seen = false
  for c in chars {
    if c == '=' {
      pad_seen = true
      continue
    }
    if pad_seen {
      // 填充后仍出现数据字符，非法
      return None
    }
    if c == '\n' || c == '\r' || c == ' ' || c == '\t' {
      continue
    }
    let v = b64_decode_char(c)
    if v < 0 {
      return None
    }
    acc = (acc << 6) | v
    bits = bits + 6
    if bits >= 8 {
      bits = bits - 8
      data.push((acc >> bits) & 0xFF)
    }
  }
  // 位组不成字节（如 4n+1 个字符）为非法输入
  if bits >= 6 {
    return None
  }
  let out : FixedArray[Int] = FixedArray::make(data.length(), 0)
  for i in 0..<data.length() {
    out[i] = data[i]
  }
  Some(out)
}
