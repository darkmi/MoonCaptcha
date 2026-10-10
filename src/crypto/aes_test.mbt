///|
fn hex_to_bytes(hex : String) -> FixedArray[Int] {
  let chars = hex.to_array()
  let out : FixedArray[Int] = FixedArray::make(chars.length() / 2, 0)
  for i in 0..<out.length() {
    let hi = chars[i * 2].to_int()
    let lo = chars[i * 2 + 1].to_int()
    let d = fn(c : Int) -> Int {
      if c >= 48 && c <= 57 {
        c - 48
      } else if c >= 97 && c <= 102 {
        c - 97 + 10
      } else if c >= 65 && c <= 70 {
        c - 65 + 10
      } else {
        0
      }
    }
    out[i] = d(hi) * 16 + d(lo)
  }
  out
}

///|
fn bytes_to_hex(data : FixedArray[Int]) -> String {
  let buf = StringBuilder()
  let hex = "0123456789abcdef".to_array()
  for b in data {
    buf.write_char(hex[(b >> 4) & 0xF])
    buf.write_char(hex[b & 0xF])
  }
  buf.to_string()
}

///|
test "aes128 fips197 vector" {
  // FIPS-197 C.1：key=000102...0f，明文 00112233...
  // ECB 输出首块 = 69c4e0d86a7b0430d8cdb78070b4c55a（已与 Node.js crypto 对拍验证）
  // 注：aes128_ecb_encrypt 会做 PKCS7 填充，16 字节明文输出 32 字节，只比对首块
  let key = hex_to_bytes("000102030405060708090a0b0c0d0e0f")
  let plain = hex_to_bytes("00112233445566778899aabbccddeeff")
  let cipher = match @crypto.aes128_ecb_encrypt(plain, key) {
    Some(c) => c
    None => abort("unreachable")
  }
  assert_true(cipher.length() == 32)
  let expected = hex_to_bytes("69c4e0d86a7b0430d8cdb78070b4c55a")
  let mut ok = true
  for i in 0..<16 {
    if cipher[i] != expected[i] {
      ok = false
    }
  }
  assert_true(ok)
}

///|
test "aes128 encrypt decrypt roundtrip random" {
  let key = hex_to_bytes("000102030405060708090a0b0c0d0e0f")
  let plain = hex_to_bytes("00112233445566778899aabbccddeeff")
  let cipher = match @crypto.aes128_ecb_encrypt(plain, key) {
    Some(c) => c
    None => abort("unreachable")
  }
  let decrypted = match @crypto.aes128_ecb_decrypt(cipher, key) {
    Some(d) => d
    None => abort("unreachable")
  }
  assert_true(bytes_to_hex(decrypted) == bytes_to_hex(plain))
}

///|
