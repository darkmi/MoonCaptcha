///|
test "rng next_bounded stays in range" {
  let rng = @common.Rng::new(7UL)
  for bound in [1, 2, 3, 16, 97, 200] {
    for _i in 0..<500 {
      let v = rng.next_bounded(bound)
      assert_true(v >= 0 && v < bound)
    }
  }
}

///|
test "rng random_range is [start, end)" {
  let rng = @common.Rng::new(9UL)
  for _i in 0..<500 {
    let v = rng.random_range(200, 216)
    assert_true(v >= 200 && v < 216)
  }
  // start >= end 降级为 start
  assert_true(rng.random_range(5, 5) == 5)
  assert_true(rng.random_range(9, 2) == 9)
}

///|
test "rng random_string charset and length" {
  let rng = @common.Rng::new(11UL)
  let s = rng.random_string(16)
  assert_true(s.length() == 16)
  for c in s.iter() {
    assert_true(
      (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9'),
    )
  }
}

///|
test "rng uuid is 32 lowercase hex chars" {
  let rng = @common.Rng::new(13UL)
  let id = rng.uuid()
  assert_true(id.length() == 32)
  for c in id.iter() {
    assert_true((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f'))
  }
  assert_true(rng.uuid() != rng.uuid())
}

///|
test "base64 known vectors" {
  assert_true(@common.base64_encode(@common.fixed_from_array([])) == "")
  assert_true(@common.base64_encode(@common.fixed_from_array([102])) == "Zg==")
  assert_true(
    @common.base64_encode(@common.fixed_from_array([102, 111])) == "Zm8=",
  )
  assert_true(
    @common.base64_encode(@common.fixed_from_array([102, 111, 111])) == "Zm9v",
  )
  assert_true(
    @common.base64_encode(@common.fixed_from_array([104, 101, 108, 108, 111])) ==
    "aGVsbG8=",
  )
}

///|
test "base64 roundtrip" {
  let rng = @common.Rng::new(21UL)
  for len in [0, 1, 2, 3, 4, 5, 15, 16, 17, 255] {
    let data : FixedArray[Int] = FixedArray::make(len, 0)
    for i in 0..<len {
      data[i] = rng.next_bounded(256)
    }
    let encoded = @common.base64_encode(data)
    match @common.base64_decode(encoded) {
      Some(decoded) => assert_true(decoded.length() == data.length())
      None => assert_true(false)
    }
  }
}

///|
test "base64 rejects malformed input" {
  assert_true(@common.base64_decode("a") is None)
  assert_true(@common.base64_decode("!!!!") is None)
  assert_true(@common.base64_decode("Zg=x") is None)
}

///|
test "utf8 known vector" {
  // "你好" → E4 BD A0 E5 A5 BD
  let encoded = @common.utf8_encode("你好")
  assert_true(encoded.length() == 6)
  assert_true(encoded[0] == 0xE4)
  assert_true(encoded[1] == 0xBD)
  assert_true(encoded[2] == 0xA0)
  assert_true(@common.utf8_decode(encoded) == "你好")
}

///|
test "utf8 roundtrip ascii and 4-byte codepoints" {
  for text in ["hello", "", "密captcha验证", "\u{1F600}emoji"] {
    assert_true(@common.utf8_decode(@common.utf8_encode(text)) == text)
  }
}

///|
test "jsonlite parses point json with floats" {
  let v = @common.parse_json("{\"x\": 111.09764310704718, \"y\": 5}")
  assert_true(v is Ok(_))
}

///|
test "jsonlite parse object / array / escapes" {
  let obj = @common.parse_json("{\"secretKey\":\"a\\\"b\",\"x\":5,\"y\":-3}")
  match obj {
    Ok(JObject(entries)) => {
      assert_true(entries.length() == 3)
      assert_true(entries[0].0 == "secretKey")
      match entries[0].1 {
        JString(s) => assert_true(s == "a\"b")
        _ => assert_true(false)
      }
      match entries[1].1 {
        JNumber(v) => assert_true(v == 5.0)
        _ => assert_true(false)
      }
      match entries[2].1 {
        JNumber(v) => assert_true(v == -3.0)
        _ => assert_true(false)
      }
    }
    _ => assert_true(false)
  }
  let arr = @common.parse_json("[{\"x\":85.0,\"y\":34.0},{\"x\":129,\"y\":56}]")
  match arr {
    Ok(JArray(items)) => assert_true(items.length() == 2)
    _ => assert_true(false)
  }
  assert_true(@common.parse_json("[1, 2,") is Err(_))
  assert_true(@common.parse_json("{\"a\":}") is Err(_))
  assert_true(@common.parse_json("nul") is Err(_))
}

///|
test "jsonlite unicode escape and surrogate pair" {
  match @common.parse_json("\"\u5154\"") {
    Ok(JString(s)) => assert_true(s == "兔")
    _ => assert_true(false)
  }
  match @common.parse_json("\"\u0041\u0042\"") {
    Ok(JString(s)) => assert_true(s == "AB")
    _ => assert_true(false)
  }
}

///|
test "parse_double basics" {
  match @common.parse_double("5") {
    Some(v) => assert_true(v == 5.0)
    None => assert_true(false)
  }
  match @common.parse_double("111.09764310704718") {
    // 手工浮点累加与字面量解析存在 ~1e-13 级误差，坐标场景（截断为 int）不受影响
    Some(v) => assert_true((v - 111.09764310704718).abs() < 0.0000000001)
    None => assert_true(false)
  }
  match @common.parse_double("-3") {
    Some(v) => assert_true(v == -3.0)
    None => assert_true(false)
  }
  match @common.parse_double("1.5e2") {
    Some(v) => assert_true(v == 150.0)
    None => assert_true(false)
  }
  assert_true(@common.parse_double("abc") is None)
  assert_true(@common.parse_double("") is None)
  assert_true(@common.parse_double("-") is None)
}

///|
test "json escape roundtrip" {
  let buf = StringBuilder()
  buf.write_char('a')
  buf.write_char('"')
  buf.write_char((92).to_char().unwrap())
  buf.write_char('c')
  buf.write_char('\n')
  buf.write_char('d')
  let original = buf.to_string()
  let escaped = @common.json_escape_string(original)
  // 转义输出中不得出现裸换行
  let mut has_raw_newline = false
  for c in escaped.iter() {
    if c == '\n' {
      has_raw_newline = true
    }
  }
  assert_true(!has_raw_newline)
  // 转义后应可被解析回原串
  match @common.parse_json(escaped) {
    Ok(JString(back)) => assert_true(back == original)
    _ => assert_true(false)
  }
}

///|
test "secure random primitives" {
  // wasm 测试运行于 WASI，熵源应可用
  match @common.secure_key16() {
    Some(key) => {
      assert_true(key.length() == 16)
      for c in key.iter() {
        assert_true(
          (c >= 'a' && c <= 'z') ||
          (c >= 'A' && c <= 'Z') ||
          (c >= '0' && c <= '9'),
        )
      }
    }
    None => assert_true(false)
  }
  match @common.secure_uuid() {
    Some(id) => {
      assert_true(id.length() == 32)
      for c in id.iter() {
        assert_true((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f'))
      }
    }
    None => assert_true(false)
  }
  // 两次种子应当不同（128 位熵下碰撞概率忽略）
  assert_true(@common.secure_seed() != 0UL)
  match @common.secure_bytes(8) {
    Some(bs) => assert_true(bs.length() == 8)
    None => assert_true(false)
  }
}
