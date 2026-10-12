///|
/// 坐标点，对齐 AJ-Captcha 的 PointVO。
/// 序列化格式字节级兼容：`{"secretKey":"..","x":5,"y":5}`。
/// 解析兼容前端 JSON.stringify 的浮点输出（如 {"x":111.09,"y":5}），数值截断为 int。
pub struct Point {
  secret_key : String
  x : Int
  y : Int
}

///|
pub fn Point::make(x : Int, y : Int, secret_key : String) -> Point {
  { secret_key, x, y, }
}

///|
pub fn Point::x(self : Point) -> Int {
  self.x
}

///|
pub fn Point::y(self : Point) -> Int {
  self.y
}

///|
pub fn Point::secret_key(self : Point) -> String {
  self.secret_key
}

///|
/// 序列化，格式与 PointVO.toJsonString() 一致（secretKey 为空时输出空字符串，
/// 修正 Java 版输出字符串 "null" 的缺陷，见 docs/migration-design.md §4.6）。
pub fn Point::to_captcha_json(self : Point) -> String {
  let buf = StringBuilder()
  buf.write_string("{\"secretKey\":")
  buf.write_string(@common.json_escape_string(self.secret_key))
  buf.write_string(",\"x\":")
  buf.write_string(self.x.to_string())
  buf.write_string(",\"y\":")
  buf.write_string(self.y.to_string())
  buf.write_string("}")
  buf.to_string()
}

///|
/// 解析单个坐标 JSON。缺省字段：secretKey=""、x=0、y=0（对齐 PointVO.parse）。
pub fn Point::parse_captcha_json(text : String) -> Result[Point, String] {
  match @common.parse_json(text) {
    Err(e) => Err(e)
    Ok(v) => Point::parse_captcha_json_value(v)
  }
}

///|
fn Point::parse_captcha_json_value(v : @common.Value) -> Result[Point, String] {
  match v {
    @common.JObject(_) => {
      let x = v.field_int("x").unwrap_or(0)
      let y = v.field_int("y").unwrap_or(0)
      let secret_key = v.field_str("secretKey").unwrap_or("")
      Ok(Point::make(x, y, secret_key))
    }
    _ => Err("expected json object")
  }
}

///|
/// 序列化坐标数组：`[{...},{...}]`（clickWord 存储格式）。
pub fn Point::list_to_captcha_json(points : Array[Point]) -> String {
  let buf = StringBuilder()
  buf.write_char('[')
  for i, p in points {
    if i > 0 {
      buf.write_char(',')
    }
    buf.write_string(p.to_captcha_json())
  }
  buf.write_char(']')
  buf.to_string()
}

///|
/// 解析坐标数组（兼容前端提交的点击坐标数组）。
pub fn Point::parse_captcha_json_array(
  text : String,
) -> Result[Array[Point], String] {
  match @common.parse_json(text) {
    Err(e) => Err(e)
    Ok(v) =>
      match v {
        @common.JArray(items) => {
          let points : Array[Point] = []
          for item in items {
            match Point::parse_captcha_json_value(item) {
              Ok(p) => points.push(p)
              Err(e) => return Err(e)
            }
          }
          Ok(points)
        }
        _ => Err("expected json array")
      }
  }
}
