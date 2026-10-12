///|
/// zlib / PNG 单元测试：标准校验值向量 + 内部往返（含 >64KB 多块）。

///|
test "adler32 known vector" {
  // adler32("Wikipedia") = 0x11E60398（RFC 1950 经典示例）
  let wiki = @common.utf8_encode("Wikipedia")
  assert_true(adler32(wiki) == 0x11E60398)
}

///|
test "crc32 known vector" {
  // crc32("123456789") = 0xCBF43926（IEEE 802.3 标准校验值）
  let d = @common.utf8_encode("123456789")
  assert_true(crc32(d) == 0xCBF43926)
}

///|
fn arrays_equal(a : FixedArray[Int], b : FixedArray[Int]) -> Bool {
  if a.length() != b.length() {
    return false
  }
  for i in 0..<a.length() {
    if a[i] != b[i] {
      return false
    }
  }
  true
}

///|
fn lcg_bytes(seed : Int, n : Int) -> FixedArray[Int] {
  let out : FixedArray[Int] = FixedArray::make(n, 0)
  let mut x = seed
  for i in 0..<n {
    x = (x * 1103515245 + 12345) & 0x7FFFFFFF
    out[i] = (x >> 16) & 0xFF
  }
  out
}

///|
test "zlib stored roundtrip various sizes" {
  // 覆盖：空、单字节、随机小数据、恰好 65535、跨多块（70000）
  for size in [0, 1, 255, 1000, 65535, 70000] {
    let data = lcg_bytes(size + 7, size)
    let compressed = zlib_compress_stored(data)
    match zlib_decompress(compressed) {
      Ok(restored) => assert_true(arrays_equal(data, restored))
      Err(e) => {
        let _ = e
        assert_true(false)
      }
    }
  }
}

///|
test "png encode decode roundtrip" {
  // 16x10 渐变 + alpha 图案
  let w = 16
  let h = 10
  let rgba : FixedArray[Int] = FixedArray::make(w * h * 4, 0)
  for y in 0..<h {
    for x in 0..<w {
      rgba[(y * w + x) * 4] = (x * 16) & 0xFF
      rgba[(y * w + x) * 4 + 1] = (y * 25) & 0xFF
      rgba[(y * w + x) * 4 + 2] = ((x + y) * 9) & 0xFF
      rgba[(y * w + x) * 4 + 3] = if (x + y) % 3 == 0 { 0 } else { 255 }
    }
  }
  let img : PngImage = { width: w, height: h, rgba }
  let bytes = encode_png(img)
  match decode_png(bytes) {
    Ok(back) => {
      assert_true(back.width == w)
      assert_true(back.height == h)
      assert_true(arrays_equal(back.rgba, rgba))
    }
    Err(e) => {
      let _ = e
      assert_true(false)
    }
  }
}
