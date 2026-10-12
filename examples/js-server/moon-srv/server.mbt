///|
/// JS 目标 HTTP 服务派发层（examples/js-server 构建产物）。
/// Node 宿主通过构建脚本（tools/build-js-server.js）提取本包的
/// js_captcha_* 函数并挂到 module.exports，HTTP 路由只做 JSON ↔ 调用。

///|
/// 全局服务状态：进程内单例（内存缓存 + 内存频控），与 Node 单线程模型一致。
/// 分布式部署时应替换为共享缓存实现（实现 Cache trait，如 Redis）。
priv struct GlobalState {
  mut service : @service.CaptchaService?
  cache : @cache.MemoryCache
}

///|
/// 合成底图：渐变背景（示例免资源文件，开箱即用；
/// 生产请用 tools/gen-assets.js 嵌入真实底图）。
fn gradient_bg(w : Int, h : Int, seed : Int) -> @image.PngImage {
  let rgba : FixedArray[Int] = FixedArray::make(w * h * 4, 0)
  for y in 0..<h {
    for x in 0..<w {
      let i = (y * w + x) * 4
      rgba[i] = (x * 2 + seed * 30) & 0xFF
      rgba[i + 1] = (y * 2 + seed * 50) & 0xFF
      rgba[i + 2] = (seed * 90 + 60) & 0xFF
      rgba[i + 3] = 255
    }
  }
  { width: w, height: h, rgba }
}

///|
/// 合成滑块模板：94×310 透明画布，顶部矩形块（alpha 255）+ 半透明描边环。
fn rect_slider(x0 : Int, y0 : Int, x1 : Int, y1 : Int) -> @image.PngImage {
  let w = 94
  let h = 310
  let rgba : FixedArray[Int] = FixedArray::make(w * h * 4, 0)
  for y in y0..<y1 {
    for x in x0..<x1 {
      let i = (y * w + x) * 4
      rgba[i] = 255
      rgba[i + 1] = 255
      rgba[i + 2] = 255
      rgba[i + 3] = if y < y0 + 3 || y >= y1 - 3 || x < x0 + 3 || x >= x1 - 3 {
        100
      } else {
        255
      }
    }
  }
  { width: w, height: h, rgba }
}

///|
fn build_pool() -> @image.ImagePool {
  let pool = @image.ImagePool::new()
  pool.add_original(gradient_bg(310, 155, 1))
  pool.add_original(gradient_bg(310, 155, 2))
  pool.add_slider(rect_slider(24, 20, 70, 80))
  pool.add_slider(rect_slider(14, 30, 80, 100))
  pool.add_click(gradient_bg(310, 155, 3))
  pool
}

///|
let global_state : GlobalState = { service: None, cache: @cache.MemoryCache::new(fn() { @env.now().reinterpret_as_int64() }) }

///|
///|
fn state() -> GlobalState {
  global_state
}

///|
fn ensure_service(font_bytes : FixedArray[Int]?) -> Result[Unit, String] {
  let st = state()
  match st.service {
    Some(_) => {
      // 已初始化；仅当携带字体且当前无字体时热更新
      match font_bytes {
        Some(bytes) => {
          match @image.Font::parse(bytes) {
            Ok(f) => {
              match st.service {
                Some(s) => s.set_font(Some(f))
                None => ()
              }
              Ok(())
            }
            Err(e) => Err(e)
          }
        }
        None => Ok(())
      }
    }
    None => {
      let font : @image.Font? = match font_bytes {
        Some(bytes) =>
          match @image.Font::parse(bytes) {
            Ok(f) => Some(f)
            Err(e) => return Err(e)
          }
        None => None
      }
      st.service = Some(
        @service.CaptchaService::new(build_pool(), font~, limits=@service.RateLimitConfig::default()),
      )
      Ok(())
    }
  }
}

///|
/// 统一成功应答（repData 为已序列化 JSON 片段）。
fn ok_data(data : String) -> String {
  @protocol.ResponseModel::success_data(data).to_json()
}

///|
/// 请求字段读取。
fn req_str(req : @common.Value, key : String) -> String {
  req.field_str(key).unwrap_or("")
}

///|
/// 初始化（可选字体，Base64 编码的 TTF 字节）。
/// 由宿主在启动时调用一次；重复调用仅热更新字体。
pub fn js_captcha_init(font_b64 : String) -> String {
  let font_bytes : FixedArray[Int]? = if font_b64.length() == 0 {
    None
  } else {
    match @common.base64_decode(font_b64) {
      Some(b) => Some(b)
      None => return "ERR base64 decode failed"
    }
  }
  match ensure_service(font_bytes) {
    Ok(_) => "OK"
    Err(e) => "ERR " + e
  }
}

///|
/// GET /captcha/get。请求 JSON：{"kind":"blockPuzzle","clientId":""}
pub fn js_captcha_get(request : String) -> String {
  let req = match @common.parse_json(request) {
    Ok(v) => v
    Err(e) => return "ERR json: " + e
  }
  let kind = match @service.CaptchaKind::parse(req_str(req, "kind")) {
    Some(k) => k
    None => return "ERR unknown kind"
  }
  match state().service {
    None => "ERR service not initialized"
    Some(svc) =>
      match svc.get(state().cache, kind, client_id=req_str(req, "clientId")) {
        Ok(resp) => ok_data(resp.to_json())
        Err(e) => e.to_response().to_json()
      }
  }
}

///|
/// POST /captcha/check。请求 JSON：
/// {"kind":"blockPuzzle","clientId":"","token":"","pointJson":""}
pub fn js_captcha_check(request : String) -> String {
  let req = match @common.parse_json(request) {
    Ok(v) => v
    Err(e) => return "ERR json: " + e
  }
  let kind = match @service.CaptchaKind::parse(req_str(req, "kind")) {
    Some(k) => k
    None => return "ERR unknown kind"
  }
  match state().service {
    None => "ERR service not initialized"
    Some(svc) =>
      svc
        .check(
          state().cache,
          kind,
          client_id=req_str(req, "clientId"),
          token=req_str(req, "token"),
          point_json=req_str(req, "pointJson"),
        )
        .to_json()
  }
}

///|
/// POST /captcha/verify。请求 JSON：
/// {"clientId":"","captchaVerification":""}
pub fn js_captcha_verify(request : String) -> String {
  let req = match @common.parse_json(request) {
    Ok(v) => v
    Err(e) => return "ERR json: " + e
  }
  match state().service {
    None => "ERR service not initialized"
    Some(svc) =>
      svc
        .verify(
          state().cache,
          client_id=req_str(req, "clientId"),
          captcha_verification=req_str(req, "captchaVerification"),
        )
        .to_json()
  }
}

///|
fn main {
  // 预热：初始化全局服务，并实际调用各派发函数（带副作用，避免 JS 链接器
  // tree-shake 未从 main 可达的入口）；宿主构建脚本按 mangling 名提取挂载
  println("mooncaptcha js-server payload: init=" + js_captcha_init(""))
  let _warm_get = js_captcha_get("{\"kind\":\"blockPuzzle\"}")
  let _warm_check = js_captcha_check("{}")
  let _warm_verify = js_captcha_verify("{}")
  let _ = (_warm_get, _warm_check, _warm_verify)
  println("mooncaptcha js-server payload ready")
}
