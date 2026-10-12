///|
test "sbox spot checks" {
  assert_true(aes_sbox[0x00] == 0x63)
  assert_true(aes_sbox[0x53] == 0xED)
  assert_true(aes_sbox[0xFF] == 0x16)
  assert_true(aes_inv_sbox[0x63] == 0x00)
}

///|
test "key expansion fips197 c1" {
  // FIPS-197 C.1：key=2b7e1516...，w[4..7] 应为 a0fafe17 88542cb1 23a33939 2a6c7605
  let hex = "0123456789abcdef".to_array()
  let key_hex = "2b7e151628aed2a6abf7158809cf4f3c".to_array()
  let key : FixedArray[Int] = FixedArray::make(16, 0)
  for i in 0..<16 {
    let hi = key_hex[i * 2].to_int() - 48
    let lo = key_hex[i * 2 + 1].to_int() - 48
    key[i] = (if hi > 9 { hi - 39 } else { hi }) * 16 +
      (if lo > 9 { lo - 39 } else { lo })
  }
  let w = expand_key(key)
  let expected = "a0fafe1788542cb123a339392a6c7605"
  let buf = StringBuilder()
  for i in 4..<8 {
    for sh in [24, 16, 8, 0] {
      let byte = (w[i] >> sh) & 0xFF
      buf.write_char(hex[(byte >> 4) & 0xF])
      buf.write_char(hex[byte & 0xF])
    }
  }
  assert_true(buf.to_string() == expected)
}

///|
test "aes128 fips197 decrypt block" {
  // 直接解密 FIPS-197 C.1 密文块，应还原明文
  let hex = "0123456789abcdef".to_array()
  let parse = fn(src : String) -> FixedArray[Int] {
    let chars = src.to_array()
    let out : FixedArray[Int] = FixedArray::make(chars.length() / 2, 0)
    for i in 0..<out.length() {
      let hi = chars[i * 2].to_int() - 48
      let lo = chars[i * 2 + 1].to_int() - 48
      out[i] = (if hi > 9 { hi - 39 } else { hi }) * 16 +
        (if lo > 9 { lo - 39 } else { lo })
    }
    out
  }
  let tohex = fn(data : FixedArray[Int]) -> String {
    let buf = StringBuilder()
    for b in data {
      buf.write_char(hex[(b >> 4) & 0xF])
      buf.write_char(hex[b & 0xF])
    }
    buf.to_string()
  }
  let key = parse("000102030405060708090a0b0c0d0e0f")
  let w = expand_key(key)
  let block = parse("69c4e0d86a7b0430d8cdb78070b4c55a")
  decrypt_block(block, w)
  assert_true(tohex(block) == "00112233445566778899aabbccddeeff")
}
