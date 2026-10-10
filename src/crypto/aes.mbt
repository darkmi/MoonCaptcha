///|
/// AES-128 块密码（FIPS-197）。
/// S 盒由 GF(2^8) 求逆 + 仿射变换程序化生成，避免手抄 256 项查找表出错。
/// 字节统一用 FixedArray[Int]（值域 0..255）表示。
/// 模式与填充由上层组合：ECB + PKCS7（对齐 AJ-Captcha 的 AES/ECB/PKCS5Padding）。

///|
/// GF(2^8) 乘法，模多项式 x^8 + x^4 + x^3 + x + 1 (0x11B)。
fn gmul(a0 : Int, b0 : Int) -> Int {
  let mut a = a0
  let mut b = b0
  let mut p = 0
  for _i in 0..<8 {
    if (b & 1) != 0 {
      p = p ^ a
    }
    let hi = a & 0x80
    a = (a << 1) & 0xFF
    if hi != 0 {
      a = a ^ 0x1B
    }
    b = b >> 1
  }
  p
}

///|
fn rotl8(b : Int, n : Int) -> Int {
  ((b << n) | (b >> (8 - n))) & 0xFF
}

///|
let aes_sbox : FixedArray[Int] = build_sbox()

///|
let aes_inv_sbox : FixedArray[Int] = build_inv_sbox()

///|
fn build_sbox() -> FixedArray[Int] {
  let inv : FixedArray[Int] = FixedArray::make(256, 0)
  for i in 1..<256 {
    for j in 1..<256 {
      if gmul(i, j) == 1 {
        inv[i] = j
        break
      }
    }
  }
  let sbox : FixedArray[Int] = FixedArray::make(256, 0)
  for i in 0..<256 {
    let b = inv[i]
    // 仿射变换：s = b ^ rotl(b,1) ^ rotl(b,2) ^ rotl(b,3) ^ rotl(b,4) ^ 0x63
    sbox[i] = b ^ rotl8(b, 1) ^ rotl8(b, 2) ^ rotl8(b, 3) ^ rotl8(b, 4) ^ 0x63
  }
  sbox
}

///|
fn build_inv_sbox() -> FixedArray[Int] {
  let inv : FixedArray[Int] = FixedArray::make(256, 0)
  for i in 0..<256 {
    inv[aes_sbox[i]] = i
  }
  inv
}

///|
/// 128 位密钥扩展：16 字节 → 44 个 32 位字。
fn expand_key(key : FixedArray[Int]) -> FixedArray[Int] {
  let w : FixedArray[Int] = FixedArray::make(44, 0)
  for i in 0..<4 {
    w[i] = (key[4 * i] << 24) | (key[4 * i + 1] << 16) | (key[4 * i + 2] << 8) | key[4 * i + 3]
  }
  // 轮常量：rcon[i] = xtime^{i-1}(1)
  let mut rc = 1
  for round in 1..<11 {
    let rcon = rc << 24
    rc = xtime(rc)
    let i = round * 4
    let temp = sub_word(rot_word(w[i - 1])) ^ rcon
    w[i] = w[i - 4] ^ temp
    for k in 1..<4 {
      w[i + k] = w[i + k - 4] ^ w[i + k - 1]
    }
  }
  w
}

///|
fn xtime(b : Int) -> Int {
  let hi = b & 0x80
  let doubled = (b << 1) & 0xFF
  if hi != 0 {
    doubled ^ 0x1B
  } else {
    doubled
  }
}

///|
fn sub_word(word : Int) -> Int {
  (aes_sbox[(word >> 24) & 0xFF] << 24) |
  (aes_sbox[(word >> 16) & 0xFF] << 16) |
  (aes_sbox[(word >> 8) & 0xFF] << 8) |
  aes_sbox[word & 0xFF]
}

///|
fn rot_word(word : Int) -> Int {
  ((word << 8) & 0xFFFFFFFF) | ((word >> 24) & 0xFF)
}

///|
/// state 布局：state[4c + r] 为第 c 列第 r 行（与 AES 输入列填充顺序一致）。
fn add_round_key(state : FixedArray[Int], w : FixedArray[Int], round : Int) -> Unit {
  for c in 0..<4 {
    let word = w[round * 4 + c]
    state[4 * c] = state[4 * c] ^ ((word >> 24) & 0xFF)
    state[4 * c + 1] = state[4 * c + 1] ^ ((word >> 16) & 0xFF)
    state[4 * c + 2] = state[4 * c + 2] ^ ((word >> 8) & 0xFF)
    state[4 * c + 3] = state[4 * c + 3] ^ (word & 0xFF)
  }
}

///|
fn sub_bytes(state : FixedArray[Int], inv : Bool) -> Unit {
  for i in 0..<16 {
    if inv {
      state[i] = aes_inv_sbox[state[i]]
    } else {
      state[i] = aes_sbox[state[i]]
    }
  }
}

///|
fn shift_rows(state : FixedArray[Int], inv : Bool) -> Unit {
  for r in 1..<4 {
    let row : FixedArray[Int] = FixedArray::make(4, 0)
    for c in 0..<4 {
      row[c] = state[4 * c + r]
    }
    for c in 0..<4 {
      // 加密：行 r 左移 r（new[c] = old[(c+r)%4]）；解密反向
      let src = if inv {
        (c - r + 4) % 4
      } else {
        (c + r) % 4
      }
      state[4 * c + r] = row[src]
    }
  }
}

///|
fn mix_columns(state : FixedArray[Int], inv : Bool) -> Unit {
  for c in 0..<4 {
    let i = 4 * c
    let s0 = state[i]
    let s1 = state[i + 1]
    let s2 = state[i + 2]
    let s3 = state[i + 3]
    if inv {
      state[i] = gmul(s0, 14) ^ gmul(s1, 11) ^ gmul(s2, 13) ^ gmul(s3, 9)
      state[i + 1] = gmul(s0, 9) ^ gmul(s1, 14) ^ gmul(s2, 11) ^ gmul(s3, 13)
      state[i + 2] = gmul(s0, 13) ^ gmul(s1, 9) ^ gmul(s2, 14) ^ gmul(s3, 11)
      state[i + 3] = gmul(s0, 11) ^ gmul(s1, 13) ^ gmul(s2, 9) ^ gmul(s3, 14)
    } else {
      state[i] = gmul(s0, 2) ^ gmul(s1, 3) ^ s2 ^ s3
      state[i + 1] = s0 ^ gmul(s1, 2) ^ gmul(s2, 3) ^ s3
      state[i + 2] = s0 ^ s1 ^ gmul(s2, 2) ^ gmul(s3, 3)
      state[i + 3] = gmul(s0, 3) ^ s1 ^ s2 ^ gmul(s3, 2)
    }
  }
}

///|
/// 加密单个 16 字节块（原地写回 block）。
fn encrypt_block(block : FixedArray[Int], w : FixedArray[Int]) -> Unit {
  add_round_key(block, w, 0)
  for round in 1..<10 {
    sub_bytes(block, false)
    shift_rows(block, false)
    mix_columns(block, false)
    add_round_key(block, w, round)
  }
  sub_bytes(block, false)
  shift_rows(block, false)
  add_round_key(block, w, 10)
}

///|
/// 解密单个 16 字节块（原地写回 block）。
fn decrypt_block(block : FixedArray[Int], w : FixedArray[Int]) -> Unit {
  add_round_key(block, w, 10)
  for round in 1..<10 {
    shift_rows(block, true)
    sub_bytes(block, true)
    add_round_key(block, w, 10 - round)
    mix_columns(block, true)
  }
  shift_rows(block, true)
  sub_bytes(block, true)
  add_round_key(block, w, 0)
}

///|
/// 校验 16 字节密钥。
fn normalize_key(key : FixedArray[Int]) -> FixedArray[Int]? {
  if key.length() != 16 {
    return None
  }
  let out : FixedArray[Int] = FixedArray::make(16, 0)
  for i in 0..<16 {
    out[i] = key[i] & 0xFF
  }
  Some(out)
}

///|
/// ECB 模式加密：数据按 PKCS7 填充到 16 字节倍数后逐块加密。
pub fn aes128_ecb_encrypt(
  data : FixedArray[Int],
  key : FixedArray[Int],
) -> FixedArray[Int]? {
  let key16 = match normalize_key(key) {
    Some(k) => k
    None => return None
  }
  let w = expand_key(key16)
  let padded = pkcs7_pad(data, 16)
  let out : FixedArray[Int] = FixedArray::make(padded.length(), 0)
  let mut offset = 0
  while offset < padded.length() {
    let block : FixedArray[Int] = FixedArray::make(16, 0)
    for i in 0..<16 {
      block[i] = padded[offset + i]
    }
    encrypt_block(block, w)
    for i in 0..<16 {
      out[offset + i] = block[i]
    }
    offset = offset + 16
  }
  Some(out)
}

///|
/// ECB 模式解密：逐块解密后去除 PKCS7 填充。
pub fn aes128_ecb_decrypt(
  data : FixedArray[Int],
  key : FixedArray[Int],
) -> FixedArray[Int]? {
  let key16 = match normalize_key(key) {
    Some(k) => k
    None => return None
  }
  if data.length() == 0 || data.length() % 16 != 0 {
    return None
  }
  let w = expand_key(key16)
  let out : FixedArray[Int] = FixedArray::make(data.length(), 0)
  let mut offset = 0
  while offset < data.length() {
    let block : FixedArray[Int] = FixedArray::make(16, 0)
    for i in 0..<16 {
      block[i] = data[offset + i]
    }
    decrypt_block(block, w)
    for i in 0..<16 {
      out[offset + i] = block[i]
    }
    offset = offset + 16
  }
  pkcs7_unpad(out, 16)
}

///|
pub fn pkcs7_pad(data : FixedArray[Int], block_size : Int) -> FixedArray[Int] {
  let pad_len = block_size - (data.length() % block_size)
  let out : FixedArray[Int] = FixedArray::make(data.length() + pad_len, pad_len)
  for i in 0..<data.length() {
    out[i] = data[i]
  }
  out
}

///|
pub fn pkcs7_unpad(
  data : FixedArray[Int],
  block_size : Int,
) -> FixedArray[Int]? {
  let n = data.length()
  if n == 0 || n % block_size != 0 {
    return None
  }
  let pad = data[n - 1]
  if pad < 1 || pad > block_size {
    return None
  }
  for i in (n - pad)..<n {
    if data[i] != pad {
      return None
    }
  }
  let out : FixedArray[Int] = FixedArray::make(n - pad, 0)
  for i in 0..<(n - pad) {
    out[i] = data[i]
  }
  Some(out)
}
