///|
/// splitmix64 伪随机数生成器。
/// 区间语义对齐 java.util.Random / AJ-Captcha 的 RandomUtils：[start, end) 左闭右开。
/// 核心逻辑要求可复现，熵源由集成层负责注入（见 docs/migration-design.md §4.2）。
pub struct Rng {
  mut state : UInt64
}

///|
pub fn Rng::new(seed : UInt64) -> Rng {
  { state: seed }
}

///|
/// 固定种子的便捷构造，供测试使用。
pub fn Rng::of(seed : Int) -> Rng {
  Rng::new(seed.to_uint64() * 2862933555777941757UL + 3037000493UL)
}

///|
fn Rng::next_u64(self : Rng) -> UInt64 {
  self.state = self.state + 0x9E3779B97F4A7C15UL
  let mut z = self.state
  z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9UL
  z = (z ^ (z >> 27)) * 0x94D049BB133111EBUL
  z ^ (z >> 31)
}

///|
/// 31 位非负随机数，等价于 java.util.Random#next(31) 的取值域 [0, 2^31)。
fn Rng::next31(self : Rng) -> Int {
  (self.next_u64() >> 33).to_int()
}

///|
/// [0, bound) 内的随机整数，bound 必须为正。
/// 采用拒绝采样消除模偏差（同 java.util.Random#nextInt(bound) 思路）。
pub fn Rng::next_bounded(self : Rng, bound : Int) -> Int {
  if bound <= 0 {
    abort("Rng::next_bounded: bound must be positive")
  }
  // 2^31 - 1 以下最大的、能被 bound 整除的数之上的拒绝线
  let limit = 2147483647 - (2147483647 % bound)
  let mut result = 0
  let mut found = false
  while !found {
    let r = self.next31()
    if r < limit {
      result = r % bound
      found = true
    }
  }
  result
}

///|
/// [start, end) 内的随机整数，语义同 RandomUtils.getRandomInt(start, end)。
/// start >= end 时返回 start（Java 会抛异常，这里降级为确定值）。
pub fn Rng::random_range(self : Rng, start : Int, end : Int) -> Int {
  if end <= start {
    return start
  }
  start + self.next_bounded(end - start)
}

///|
const RANDOM_STRING_POOL : String = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"

///|
/// 随机字符串（字母 + 数字），语义同 RandomUtils.getRandomString(length)。
/// 用于生成 16 位 AES 密钥。
pub fn Rng::random_string(self : Rng, length : Int) -> String {
  let pool = RANDOM_STRING_POOL.to_array()
  let buf = StringBuilder()
  for _i in 0..<length {
    let c = pool[self.next_bounded(pool.length())]
    buf.write_char(c)
  }
  buf.to_string()
}

///|
/// 32 位小写十六进制 UUID（无连字符），语义同 RandomUtils.getUUID()。
pub fn Rng::uuid(self : Rng) -> String {
  let hi = self.next_u64()
  let lo = self.next_u64()
  let buf = StringBuilder()
  for shift in 0..<16 {
    let nib = ((hi >> (60 - shift * 4)) & 0xFUL).to_int()
    buf.write_char(hex_chars[nib])
  }
  for shift in 0..<16 {
    let nib = ((lo >> (60 - shift * 4)) & 0xFUL).to_int()
    buf.write_char(hex_chars[nib])
  }
  buf.to_string()
}

///|
let hex_chars : Array[Char] = [
  '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f',
]

///|
/// 从汉字池中随机取一个字符（去重逻辑由调用方负责）。
pub fn Rng::random_char(self : Rng, pool : String) -> Char {
  let arr = pool.to_array()
  arr[self.next_bounded(arr.length())]
}
