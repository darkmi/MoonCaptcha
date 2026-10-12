///|
test "repcode values match java" {
  assert_true(@protocol.Success.code() == "0000")
  assert_true(@protocol.Error.code() == "0001")
  assert_true(@protocol.Exception.code() == "9999")
  assert_true(@protocol.BlankError.code() == "0011")
  assert_true(@protocol.ApiCaptchaInvalid.code() == "6110")
  assert_true(@protocol.ApiCaptchaCoordinateError.code() == "6111")
  assert_true(@protocol.ApiCaptchaError.code() == "6112")
  assert_true(@protocol.ApiCaptchaBasemapNull.code() == "6113")
  assert_true(@protocol.ApiReqLimitGetError.code() == "6201")
  assert_true(@protocol.ApiReqLockGetError.code() == "6202")
  assert_true(@protocol.ApiReqLimitCheckError.code() == "6204")
  assert_true(@protocol.ApiReqLimitVerifyError.code() == "6205")
  assert_true(@protocol.ApiReqInvalid.code() == "6206")
  assert_true(@protocol.Success.is_success())
  assert_true(!@protocol.ApiCaptchaInvalid.is_success())
}

///|
test "point captcha json byte-exact" {
  let p = @protocol.Point::make(5, 27, "abc123")
  assert_true(
    p.to_captcha_json() == "{\"secretKey\":\"abc123\",\"x\":5,\"y\":27}",
  )
  let empty_key = @protocol.Point::make(200, 5, "")
  assert_true(
    empty_key.to_captcha_json() == "{\"secretKey\":\"\",\"x\":200,\"y\":5}",
  )
}

///|
test "point parse frontend float json" {
  // 前端 VerifySlide.vue 提交：JSON.stringify({x: moveLeftDistance, y: 5.0})
  let p = match
    @protocol.Point::parse_captcha_json("{\"x\": 111.09764310704718, \"y\": 5}") {
    Ok(p) => p
    Err(_) => {
      assert_true(false)
      abort("unreachable")
    }
  }
  assert_true(p.x == 111)
  assert_true(p.y == 5)
  assert_true(p.secret_key == "")
}

///|
test "point parse with secretKey and defaults" {
  let p = match
    @protocol.Point::parse_captcha_json(
      "{\"secretKey\":\"k1\",\"x\":85,\"y\":34}",
    ) {
    Ok(p) => p
    Err(_) => abort("unreachable")
  }
  assert_true(p.x == 85)
  assert_true(p.secret_key == "k1")
  // 缺省字段
  let d = match @protocol.Point::parse_captcha_json("{}") {
    Ok(p) => p
    Err(_) => abort("unreachable")
  }
  assert_true(d.x == 0)
  assert_true(d.secret_key == "")
  assert_true(@protocol.Point::parse_captcha_json("not json") is Err(_))
}

///|
test "point list roundtrip" {
  let points = [
    @protocol.Point::make(85, 34, "k"),
    @protocol.Point::make(129, 56, "k"),
    @protocol.Point::make(233, 27, "k"),
  ]
  let json = @protocol.Point::list_to_captcha_json(points)
  assert_true(
    json ==
    "[{\"secretKey\":\"k\",\"x\":85,\"y\":34},{\"secretKey\":\"k\",\"x\":129,\"y\":56},{\"secretKey\":\"k\",\"x\":233,\"y\":27}]",
  )
  let parsed = match @protocol.Point::parse_captcha_json_array(json) {
    Ok(ps) => ps
    Err(_) => {
      assert_true(false)
      abort("unreachable")
    }
  }
  assert_true(parsed.length() == 3)
  assert_true(parsed[1].x == 129)
}

///|
test "response model json" {
  assert_true(
    @protocol.ResponseModel::success().to_json() ==
    "{\"repCode\":\"0000\",\"repMsg\":\"成功\"}",
  )
  assert_true(
    @protocol.ResponseModel::error(ApiCaptchaInvalid).to_json() ==
    "{\"repCode\":\"6110\",\"repMsg\":\"验证码已失效，请重新获取\"}",
  )
  assert_true(
    @protocol.ResponseModel::blank_error("token").to_json() ==
    "{\"repCode\":\"0011\",\"repMsg\":\"token不能为空\"}",
  )
  assert_true(
    @protocol.ResponseModel::success_data("{\"a\":1}").to_json() ==
    "{\"repCode\":\"0000\",\"repMsg\":\"成功\",\"repData\":{\"a\":1}}",
  )
  assert_true(@protocol.ResponseModel::success().is_success())
}

///|
test "get response json for blockPuzzle" {
  let resp : @protocol.GetResponse = {
    captcha_type: "blockPuzzle",
    original_image_base64: "ORI",
    jigsaw_image_base64: "JIG",
    word_list: None,
    token: "t1",
    secret_key: "k1",
  }
  assert_true(
    resp.to_json() ==
    "{\"captchaType\":\"blockPuzzle\",\"originalImageBase64\":\"ORI\",\"jigsawImageBase64\":\"JIG\",\"token\":\"t1\",\"secretKey\":\"k1\"}",
  )
}

///|
test "get response json for clickWord" {
  let resp : @protocol.GetResponse = {
    captcha_type: "clickWord",
    original_image_base64: "ORI",
    jigsaw_image_base64: "",
    word_list: Some(["的", "一", "了"]),
    token: "t2",
    secret_key: "",
  }
  assert_true(
    resp.to_json() ==
    "{\"captchaType\":\"clickWord\",\"originalImageBase64\":\"ORI\",\"wordList\":[\"的\",\"一\",\"了\"],\"token\":\"t2\",\"secretKey\":\"\"}",
  )
}

///|
test "check success data json" {
  assert_true(
    @protocol.check_success_data("blockPuzzle", "tok") ==
    "{\"captchaType\":\"blockPuzzle\",\"token\":\"tok\",\"result\":true}",
  )
}
