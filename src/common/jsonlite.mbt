///|
/// 极简 JSON：协议子集的解析（对象 / 数组 / 字符串 / 数字 / 布尔 / null）。
/// 序列化由 protocol 包按 AJ-Captcha 字节级格式拼装，不走本模块。
/// 设计对齐 docs/migration-design.md §4.4。

///|
pub(all) enum Value {
  JString(String)
  JNumber(Double)
  JBool(Bool)
  JNull
  JArray(Array[Value])
  JObject(Array[(String, Value)])
}

///|
/// 解析失败时返回 Err(描述)。
pub fn parse_json(input : String) -> Result[Value, String] {
  let src = input.to_array()
  let parser = { src, pos: 0, }
  parser.skip_ws()
  let value = parser.parse_value()
  match value {
    Ok(v) => {
      parser.skip_ws()
      if parser.pos < parser.src.length() {
        Err("trailing characters at offset \{parser.pos}")
      } else {
        Ok(v)
      }
    }
    Err(e) => Err(e)
  }
}

///|
priv struct Parser {
  src : Array[Char]
  mut pos : Int
}

///|
fn Parser::skip_ws(self : Parser) -> Unit {
  while self.pos < self.src.length() {
    let c = self.src[self.pos]
    if c == ' ' || c == '\t' || c == '\n' || c == '\r' {
      self.pos = self.pos + 1
    } else {
      break
    }
  }
}

///|
fn Parser::peek(self : Parser) -> Char? {
  if self.pos < self.src.length() {
    Some(self.src[self.pos])
  } else {
    None
  }
}

///|
fn Parser::parse_value(self : Parser) -> Result[Value, String] {
  match self.peek() {
    None => Err("unexpected end of input")
    Some('{') => self.parse_object()
    Some('[') => self.parse_array()
    Some('"') =>
      match self.parse_string() {
        Ok(s) => Ok(JString(s))
        Err(e) => Err(e)
      }
    Some('t') => self.parse_literal("true", JBool(true))
    Some('f') => self.parse_literal("false", JBool(false))
    Some('n') => self.parse_literal("null", JNull)
    Some(c) =>
      if c == '-' || (c >= '0' && c <= '9') {
        self.parse_number()
      } else {
        Err("unexpected character '\{c}' at offset \{self.pos}")
      }
  }
}

///|
fn Parser::parse_literal(
  self : Parser,
  text : String,
  value : Value,
) -> Result[Value, String] {
  let expected = text.to_array()
  if self.pos + expected.length() > self.src.length() {
    return Err("unexpected end of input at offset \{self.pos}")
  }
  for i in 0..<expected.length() {
    if self.src[self.pos + i] != expected[i] {
      return Err("invalid literal at offset \{self.pos}")
    }
  }
  self.pos = self.pos + expected.length()
  Ok(value)
}

///|
fn Parser::parse_object(self : Parser) -> Result[Value, String] {
  self.pos = self.pos + 1 // '{'
  let entries : Array[(String, Value)] = []
  self.skip_ws()
  match self.peek() {
    Some('}') => {
      self.pos = self.pos + 1
      return Ok(JObject(entries))
    }
    None => return Err("unexpected end of object")
    _ => ()
  }
  let mut done = false
  let mut result : Result[Value, String] = Err("unreachable")
  while !done {
    self.skip_ws()
    if !(self.peek() is Some('"')) {
      return Err("expected string key at offset \{self.pos}")
    }
    let key = match self.parse_string() {
      Ok(k) => k
      Err(e) => return Err(e)
    }
    self.skip_ws()
    match self.peek() {
      Some(':') => self.pos = self.pos + 1
      _ => return Err("expected ':' at offset \{self.pos}")
    }
    self.skip_ws()
    let value = match self.parse_value() {
      Ok(v) => v
      Err(e) => return Err(e)
    }
    entries.push((key, value))
    self.skip_ws()
    match self.peek() {
      Some(',') => self.pos = self.pos + 1
      Some('}') => {
        self.pos = self.pos + 1
        result = Ok(JObject(entries))
        done = true
      }
      _ => return Err("expected ',' or '}' at offset \{self.pos}")
    }
  }
  result
}

///|
fn Parser::parse_array(self : Parser) -> Result[Value, String] {
  self.pos = self.pos + 1 // '['
  let items : Array[Value] = []
  self.skip_ws()
  match self.peek() {
    Some(']') => {
      self.pos = self.pos + 1
      return Ok(JArray(items))
    }
    None => return Err("unexpected end of array")
    _ => ()
  }
  let mut done = false
  let mut result : Result[Value, String] = Err("unreachable")
  while !done {
    self.skip_ws()
    let value = match self.parse_value() {
      Ok(v) => v
      Err(e) => return Err(e)
    }
    items.push(value)
    self.skip_ws()
    match self.peek() {
      Some(',') => self.pos = self.pos + 1
      Some(']') => {
        self.pos = self.pos + 1
        result = Ok(JArray(items))
        done = true
      }
      _ => return Err("expected ',' or ']' at offset \{self.pos}")
    }
  }
  result
}

///|
fn Parser::parse_string(self : Parser) -> Result[String, String] {
  self.pos = self.pos + 1 // '"'
  let buf = StringBuilder()
  let mut done = false
  let mut result : Result[String, String] = Err("unreachable")
  while !done {
    if self.pos >= self.src.length() {
      return Err("unterminated string")
    }
    let c = self.src[self.pos]
    self.pos = self.pos + 1
    if c == '"' {
      result = Ok(buf.to_string())
      done = true
    } else if c == '\\' {
      if self.pos >= self.src.length() {
        return Err("unterminated escape")
      }
      let esc = self.src[self.pos]
      self.pos = self.pos + 1
      match esc {
        '"' => buf.write_char('"')
        '\\' => buf.write_char('\\')
        '/' => buf.write_char('/')
        'b' => buf.write_char('\u{0008}')
        'f' => buf.write_char('\u{000C}')
        'n' => buf.write_char('\n')
        'r' => buf.write_char('\r')
        't' => buf.write_char('\t')
        'u' => {
          let unit = match self.parse_hex4() {
            Ok(u) => u
            Err(e) => return Err(e)
          }
          if unit >= 0xD800 && unit <= 0xDBFF {
            // 高代理：尝试与后续 DC00-DFFF 合并成完整码点；无法合并则回退 U+FFFD
            if self.pos + 1 < self.src.length() &&
              self.src[self.pos].to_int() == 92 &&
              self.src[self.pos + 1].to_int() == 117 {
              let save = self.pos
              self.pos = self.pos + 2
              match self.parse_hex4() {
                Ok(low) =>
                  if low >= 0xDC00 && low <= 0xDFFF {
                    let combined = 0x10000 +
                      ((unit - 0xD800) << 10) +
                      (low - 0xDC00)
                    write_code_point(buf, combined)
                  } else {
                    write_code_point(buf, unit)
                    write_code_point(buf, low)
                  }
                Err(_) => {
                  self.pos = save
                  write_code_point(buf, unit)
                }
              }
            } else {
              write_code_point(buf, unit)
            }
          } else {
            write_code_point(buf, unit)
          }
        }
        _ => return Err("invalid escape '\\\{esc}'")
      }
    } else {
      buf.write_char(c)
    }
  }
  result
}

///|
fn Parser::parse_hex4(self : Parser) -> Result[Int, String] {
  if self.pos + 4 > self.src.length() {
    return Err("unterminated \\u escape")
  }
  let mut v = 0
  for _i in 0..<4 {
    let c = self.src[self.pos]
    let d = hex_digit(c)
    match d {
      Some(d) => v = v * 16 + d
      None => return Err("invalid hex digit '\{c}'")
    }
    self.pos = self.pos + 1
  }
  Ok(v)
}

///|
fn hex_digit(c : Char) -> Int? {
  if c >= '0' && c <= '9' {
    return Some(c.to_int() - 48)
  }
  if c >= 'a' && c <= 'f' {
    return Some(c.to_int() - 97 + 10)
  }
  if c >= 'A' && c <= 'F' {
    return Some(c.to_int() - 65 + 10)
  }
  None
}

///|
fn Parser::parse_number(self : Parser) -> Result[Value, String] {
  let start = self.pos
  if self.peek() is Some('-') {
    self.pos = self.pos + 1
  }
  while self.pos < self.src.length() &&
        self.src[self.pos] >= '0' &&
        self.src[self.pos] <= '9' {
    self.pos = self.pos + 1
  }
  if self.pos < self.src.length() && self.src[self.pos] == '.' {
    self.pos = self.pos + 1
    while self.pos < self.src.length() &&
          self.src[self.pos] >= '0' &&
          self.src[self.pos] <= '9' {
      self.pos = self.pos + 1
    }
  }
  if self.pos < self.src.length() &&
    (self.src[self.pos] == 'e' || self.src[self.pos] == 'E') {
    self.pos = self.pos + 1
    if self.pos < self.src.length() &&
      (self.src[self.pos] == '+' || self.src[self.pos] == '-') {
      self.pos = self.pos + 1
    }
    while self.pos < self.src.length() &&
          self.src[self.pos] >= '0' &&
          self.src[self.pos] <= '9' {
      self.pos = self.pos + 1
    }
  }
  if self.pos == start || (self.pos == start + 1 && self.src[start] == '-') {
    return Err("invalid number at offset \{start}")
  }
  // 手工组装 double：整数部分 + 小数部分 + 指数（坐标数值范围内精度足够）
  let text = substring_chars(self.src, start, self.pos)
  match parse_double(text) {
    Some(d) => Ok(JNumber(d))
    None => Err("invalid number '\{text}'")
  }
}

///|
fn substring_chars(src : Array[Char], start : Int, end : Int) -> String {
  let buf = StringBuilder()
  for i in start..<end {
    buf.write_char(src[i])
  }
  buf.to_string()
}

///|
/// 手工解析十进制浮点数（含小数与 10 进制指数）。
pub fn parse_double(text : String) -> Double? {
  let chars = text.to_array()
  let n = chars.length()
  if n == 0 {
    return None
  }
  let mut i = 0
  let mut negative = false
  if chars[i] == '-' {
    negative = true
    i = i + 1
  } else if chars[i] == '+' {
    i = i + 1
  }
  let mut mantissa = 0.0
  let mut digits = 0
  while i < n && chars[i] >= '0' && chars[i] <= '9' {
    mantissa = mantissa * 10.0 + (chars[i].to_int() - 48).to_double()
    digits = digits + 1
    i = i + 1
  }
  if i < n && chars[i] == '.' {
    i = i + 1
    let mut scale = 0.1
    while i < n && chars[i] >= '0' && chars[i] <= '9' {
      mantissa = mantissa + (chars[i].to_int() - 48).to_double() * scale
      scale = scale * 0.1
      digits = digits + 1
      i = i + 1
    }
  }
  if digits == 0 {
    return None
  }
  let mut exponent = 0
  if i < n && (chars[i] == 'e' || chars[i] == 'E') {
    i = i + 1
    let mut exp_negative = false
    if i < n && (chars[i] == '+' || chars[i] == '-') {
      exp_negative = chars[i] == '-'
      i = i + 1
    }
    if i >= n {
      return None
    }
    while i < n && chars[i] >= '0' && chars[i] <= '9' {
      exponent = exponent * 10 + (chars[i].to_int() - 48)
      i = i + 1
    }
    if exp_negative {
      exponent = -exponent
    }
  }
  if i != n {
    return None
  }
  let mut value = mantissa
  if exponent > 0 {
    for _k in 0..<exponent {
      value = value * 10.0
    }
  } else if exponent < 0 {
    for _k in 0..<-exponent {
      value = value / 10.0
    }
  }
  Some(if negative { -value } else { value })
}

///|
/// JSON 字符串字面量转义（用于 protocol 包的序列化）。
pub fn json_escape_string(text : String) -> String {
  let buf = StringBuilder()
  buf.write_char('"')
  for c in text.iter() {
    match c {
      '"' => buf.write_string("\\\"")
      '\\' => buf.write_string("\\\\")
      '\n' => buf.write_string("\\n")
      '\r' => buf.write_string("\\r")
      '\t' => buf.write_string("\\t")
      c =>
        if c.to_int() < 0x20 {
          buf.write_string("\\u")
          let v = c.to_int()
          for shift in 0..<4 {
            let nib = (v >> (12 - shift * 4)) & 0xF
            buf.write_char(hex_chars[nib])
          }
        } else {
          buf.write_char(c)
        }
    }
  }
  buf.write_char('"')
  buf.to_string()
}

///|
/// 取对象字段的整数值（数值截断为 int），不存在返回 None。
pub fn Value::field_int(self : Value, key : String) -> Int? {
  match self {
    JObject(entries) =>
      match Value::lookup(entries, key) {
        Some(JNumber(v)) => Some(v.to_int())
        _ => None
      }
    _ => None
  }
}

///|
/// 取对象字段的字符串值，不存在返回 None。
pub fn Value::field_str(self : Value, key : String) -> String? {
  match self {
    JObject(entries) =>
      match Value::lookup(entries, key) {
        Some(JString(s)) => Some(s)
        _ => None
      }
    _ => None
  }
}

///|
/// 取对象字段，不存在返回 None。
pub fn Value::field(self : Value, key : String) -> Value? {
  match self {
    JObject(entries) => Value::lookup(entries, key)
    _ => None
  }
}

///|
pub fn Value::lookup(entries : Array[(String, Value)], key : String) -> Value? {
  for entry in entries {
    if entry.0 == key {
      return Some(entry.1)
    }
  }
  None
}

///|
/// 写入一个 Unicode 码点；无效码点（如未配对代理项）回退为 U+FFFD。
fn write_code_point(buf : StringBuilder, cp : Int) -> Unit {
  match cp.to_char() {
    Some(c) => buf.write_char(c)
    None => buf.write_char((65533).to_char().unwrap())
  }
}
