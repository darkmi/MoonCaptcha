///|
/// 安全随机源：封装跨平台熵源 moonbitlang/core/env#rand
/// （wasm → WASI random_get，js → crypto.getRandomValues，native → OS 熵源）。
/// 熵源不可用时提供时间混淆的降级路径（非密码学安全，仅保底可用性，
/// 会在返回 None 的 API 中显式暴露）。

///|
/// 取 n 个安全随机字节；熵源不可用返回 None。
pub fn secure_bytes(n : Int) -> FixedArray[Int]? {
  if n <= 0 {
    return Some(FixedArray::make(0, 0))
  }
  match @env.rand(n) {
    Some(bytes) => {
      let out : FixedArray[Int] = FixedArray::make(n, 0)
      for i in 0..<n {
        out[i] = bytes.at(i).to_int() & 0xFF
      }
      Some(out)
    }
    None => None
  }
}

///|
const KEY62_POOL : String = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"

///|
/// 16 字符随机密钥（62 字符池，拒绝采样消除模偏差），对齐 AESUtil.getKey()。
/// 熵源不可用返回 None（调用方应显式失败而非静默降级）。
pub fn secure_key16() -> String? {
  let pool = KEY62_POOL.to_array()
  let chars : Array[Char] = []
  while chars.length() < 16 {
    let bytes = match secure_bytes(24) {
      Some(bs) => bs
      None => return None
    }
    for b in bytes {
      // 248 = 62 * 4：拒绝最高 8 个值消除模偏差
      if chars.length() < 16 && b < 248 {
        chars.push(pool[b % 62])
      }
    }
  }
  let buf = StringBuilder()
  for c in chars {
    buf.write_char(c)
  }
  Some(buf.to_string())
}

///|
let hex_chars16 : Array[Char] = [
  '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e',
  'f',
]

///|
/// 32 位十六进制 UUID（128 位安全熵）；熵源不可用返回 None。
pub fn secure_uuid() -> String? {
  let bytes = match secure_bytes(16) {
    Some(bs) => bs
    None => return None
  }
  let buf = StringBuilder()
  for b in bytes {
    buf.write_char(hex_chars16[(b >> 4) & 0xF])
    buf.write_char(hex_chars16[b & 0xF])
  }
  Some(buf.to_string())
}

///|
/// 从安全熵派生 UInt64 种子；熵不可用时以时间混淆降级（非密码学安全）。
pub fn secure_seed() -> UInt64 {
  match secure_bytes(8) {
    Some(bs) => {
      let mut v : UInt64 = 0UL
      for b in bs {
        v = v * 256UL + b.to_uint64()
      }
      v
    }
    None => {
      let t = @env.now()
      let mixed = t ^ (t << 21) ^ (t >> 35) ^ (t << 4)
      if mixed == 0UL {
        0x9E3779B97F4A7C15UL
      } else {
        mixed
      }
    }
  }
}

///|
/// 安全种子的 Rng 构造（服务层默认随机源；测试请用 Rng::new(固定种子)）。
pub fn Rng::from_secure_source() -> Rng {
  Rng::new(secure_seed())
}
