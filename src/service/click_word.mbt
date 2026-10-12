///|
/// 文字点选（clickWord）服务逻辑。
/// 逐条对照 ClickWordCaptchaServiceImpl 移植，协议细节见 docs/aj-captcha-analysis.md §6。
/// 文字的光栅化绘制见 image 包字体模块（M3）；本文件负责布点、选字、校验与令牌生命周期。

///|
/// 常用汉字池，逐字复制自 AJ-Captcha 的 HAN_ZI 常量。
pub const HAN_ZI : String = "\u{7684}\u{4e00}\u{4e86}\u{662f}\u{6211}\u{4e0d}\u{5728}\u{4eba}\u{4eec}\u{6709}\u{6765}\u{4ed6}\u{8fd9}\u{4e0a}\u{7740}\u{4e2a}\u{5730}\u{5230}\u{5927}\u{91cc}\u{8bf4}\u{5c31}\u{53bb}\u{5b50}\u{5f97}\u{4e5f}\u{548c}\u{90a3}\u{8981}\u{4e0b}\u{770b}\u{5929}\u{65f6}\u{8fc7}\u{51fa}\u{5c0f}\u{4e48}\u{8d77}\u{4f60}\u{90fd}\u{628a}\u{597d}\u{8fd8}\u{591a}\u{6ca1}\u{4e3a}\u{53c8}\u{53ef}\u{5bb6}\u{5b66}\u{53ea}\u{4ee5}\u{4e3b}\u{4f1a}\u{6837}\u{5e74}\u{60f3}\u{751f}\u{540c}\u{8001}\u{4e2d}\u{5341}\u{4ece}\u{81ea}\u{9762}\u{524d}\u{5934}\u{9053}\u{5b83}\u{540e}\u{7136}\u{8d70}\u{5f88}\u{50cf}\u{89c1}\u{4e24}\u{7528}\u{5979}\u{56fd}\u{52a8}\u{8fdb}\u{6210}\u{56de}\u{4ec0}\u{8fb9}\u{4f5c}\u{5bf9}\u{5f00}\u{800c}\u{5df1}\u{4e9b}\u{73b0}\u{5c71}\u{6c11}\u{5019}\u{7ecf}\u{53d1}\u{5de5}\u{5411}\u{4e8b}\u{547d}\u{7ed9}\u{957f}\u{6c34}\u{51e0}\u{4e49}\u{4e09}\u{58f0}\u{4e8e}\u{9ad8}\u{624b}\u{77e5}\u{7406}\u{773c}\u{5fd7}\u{70b9}\u{5fc3}\u{6218}\u{4e8c}\u{95ee}\u{4f46}\u{8eab}\u{65b9}\u{5b9e}\u{5403}\u{505a}\u{53eb}\u{5f53}\u{4f4f}\u{542c}\u{9769}\u{6253}\u{5462}\u{771f}\u{5168}\u{624d}\u{56db}\u{5df2}\u{6240}\u{654c}\u{4e4b}\u{6700}\u{5149}\u{4ea7}\u{60c5}\u{8def}\u{5206}\u{603b}\u{6761}\u{767d}\u{8bdd}\u{4e1c}\u{5e2d}\u{6b21}\u{4eb2}\u{5982}\u{88ab}\u{82b1}\u{53e3}\u{653e}\u{513f}\u{5e38}\u{6c14}\u{4e94}\u{7b2c}\u{4f7f}\u{5199}\u{519b}\u{5427}\u{6587}\u{8fd0}\u{518d}\u{679c}\u{600e}\u{5b9a}\u{8bb8}\u{5feb}\u{660e}\u{884c}\u{56e0}\u{522b}\u{98de}\u{5916}\u{6811}\u{7269}\u{6d3b}\u{90e8}\u{95e8}\u{65e0}\u{5f80}\u{8239}\u{671b}\u{65b0}\u{5e26}\u{961f}\u{5148}\u{529b}\u{5b8c}\u{5374}\u{7ad9}\u{4ee3}\u{5458}\u{673a}\u{66f4}\u{4e5d}\u{60a8}\u{6bcf}\u{98ce}\u{7ea7}\u{8ddf}\u{7b11}\u{554a}\u{5b69}\u{4e07}\u{5c11}\u{76f4}\u{610f}\u{591c}\u{6bd4}\u{9636}\u{8fde}\u{8f66}\u{91cd}\u{4fbf}\u{6597}\u{9a6c}\u{54ea}\u{5316}\u{592a}\u{6307}\u{53d8}\u{793e}\u{4f3c}\u{58eb}\u{8005}\u{5e72}\u{77f3}\u{6ee1}\u{65e5}\u{51b3}\u{767e}\u{539f}\u{62ff}\u{7fa4}\u{7a76}\u{5404}\u{516d}\u{672c}\u{601d}\u{89e3}\u{7acb}\u{6cb3}\u{6751}\u{516b}\u{96be}\u{65e9}\u{8bba}\u{5417}\u{6839}\u{5171}\u{8ba9}\u{76f8}\u{7814}\u{4eca}\u{5176}\u{4e66}\u{5750}\u{63a5}\u{5e94}\u{5173}\u{4fe1}\u{89c9}\u{6b65}\u{53cd}\u{5904}\u{8bb0}\u{5c06}\u{5343}\u{627e}\u{4e89}\u{9886}\u{6216}\u{5e08}\u{7ed3}\u{5757}\u{8dd1}\u{8c01}\u{8349}\u{8d8a}\u{5b57}\u{52a0}\u{811a}\u{7d27}\u{7231}\u{7b49}\u{4e60}\u{9635}\u{6015}\u{6708}\u{9752}\u{534a}\u{706b}\u{6cd5}\u{9898}\u{5efa}\u{8d76}\u{4f4d}\u{5531}\u{6d77}\u{4e03}\u{5973}\u{4efb}\u{4ef6}\u{611f}\u{51c6}\u{5f20}\u{56e2}\u{5c4b}\u{79bb}\u{8272}\u{8138}\u{7247}\u{79d1}\u{5012}\u{775b}\u{5229}\u{4e16}\u{521a}\u{4e14}\u{7531}\u{9001}\u{5207}\u{661f}\u{5bfc}\u{665a}\u{8868}\u{591f}\u{6574}\u{8ba4}\u{54cd}\u{96ea}\u{6d41}\u{672a}\u{573a}\u{8be5}\u{5e76}\u{5e95}\u{6df1}\u{523b}\u{5e73}\u{4f1f}\u{5fd9}\u{63d0}\u{786e}\u{8fd1}\u{4eae}\u{8f7b}\u{8bb2}\u{519c}\u{53e4}\u{9ed1}\u{544a}\u{754c}\u{62c9}\u{540d}\u{5440}\u{571f}\u{6e05}\u{9633}\u{7167}\u{529e}\u{53f2}\u{6539}\u{5386}\u{8f6c}\u{753b}\u{9020}\u{5634}\u{6b64}\u{6cbb}\u{5317}\u{5fc5}\u{670d}\u{96e8}\u{7a7f}\u{5185}\u{8bc6}\u{9a8c}\u{4f20}\u{4e1a}\u{83dc}\u{722c}\u{7761}\u{5174}\u{5f62}\u{91cf}\u{54b1}\u{89c2}\u{82e6}\u{4f53}\u{4f17}\u{901a}\u{51b2}\u{5408}\u{7834}\u{53cb}\u{5ea6}\u{672f}\u{996d}\u{516c}\u{65c1}\u{623f}\u{6781}\u{5357}\u{67aa}\u{8bfb}\u{6c99}\u{5c81}\u{7ebf}\u{91ce}\u{575a}\u{7a7a}\u{6536}\u{7b97}\u{81f3}\u{653f}\u{57ce}\u{52b3}\u{843d}\u{94b1}\u{7279}\u{56f4}\u{5f1f}\u{80dc}\u{6559}\u{70ed}\u{5c55}\u{5305}\u{6b4c}\u{7c7b}\u{6e10}\u{5f3a}\u{6570}\u{4e61}\u{547c}\u{6027}\u{97f3}\u{7b54}\u{54e5}\u{9645}\u{65e7}\u{795e}\u{5ea7}\u{7ae0}\u{5e2e}\u{5566}\u{53d7}\u{7cfb}\u{4ee4}\u{8df3}\u{975e}\u{4f55}\u{725b}\u{53d6}\u{5165}\u{5cb8}\u{6562}\u{6389}\u{5ffd}\u{79cd}\u{88c5}\u{9876}\u{6025}\u{6797}\u{505c}\u{606f}\u{53e5}\u{533a}\u{8863}\u{822c}\u{62a5}\u{53e6}\u{538b}\u{6162}\u{53d4}\u{80cc}\u{7ec6}"

///|
/// 从汉字池去重随机选取 word_count 个字。
pub fn random_words(rng : @common.Rng, word_count : Int) -> Array[String] {
  let words : Array[String] = []
  let mut done = words.length() >= word_count
  while !done {
    let word = rng.random_char(HAN_ZI).to_string()
    let mut exists = false
    for w in words {
      if w == word {
        exists = true
        break
      }
    }
    if !exists {
      words.push(word)
    }
    done = words.length() >= word_count
  }
  words
}

///|
/// 随机布点，对齐 randomWordPoint：按 avgWidth = width / (wordCount+1) 分列，
/// 第 i 个字落在第 i 列（内边距 HAN_ZI_SIZE_HALF），y ∈ [字号, 高度 - 字号)。
pub fn random_word_point(
  rng : @common.Rng,
  image_width : Int,
  image_height : Int,
  word_sort_index : Int,
  word_count : Int,
  han_zi_size : Int,
) -> @protocol.Point {
  let half = han_zi_size / 2
  let avg_width = image_width / (word_count + 1)
  let x = if avg_width < half {
    rng.random_range(1 + half, image_width)
  } else if word_sort_index == 0 {
    rng.random_range(1 + half, avg_width * (word_sort_index + 1) - half)
  } else {
    rng.random_range(
      avg_width * word_sort_index + half,
      avg_width * (word_sort_index + 1) - half,
    )
  }
  let y = rng.random_range(han_zi_size, image_height - han_zi_size)
  @protocol.Point::make(x, y, "")
}

///|
/// 单个点选字的绘制信息（颜色/旋转在生成期确定，绘制与校验保持一致）。
pub(all) struct ClickWordChar {
  word : String
  x : Int
  y : Int
  /// 0xAARRGGBB 不透明文字色（RGB 各分量 ∈ [1,255]，对齐 Java 随机色）
  color : Int
  /// 旋转角（度，[-45, 45]）
  rotation : Int
}

///|
/// 点选验证码生成数据，对齐 getImageData：
/// - 绘制 word_total_count 个字，其中随机 1 个为干扰字（只绘制、不参与校验）
/// - 干扰字下标 ∈ [0, word_total_count-2]，最后一个字永不成为干扰字
/// - 所有绘制点的 secretKey 为同一个密钥
/// chars 为全部绘制字（含干扰字）；word_list / point_list 为参与校验的子集。
pub(all) struct ClickWordData {
  chars : Array[ClickWordChar]
  word_list : Array[String]
  point_list : Array[@protocol.Point]
  secret_key : String
}

///|
pub fn generate_click_word_data(
  rng : @common.Rng,
  image_width : Int,
  image_height : Int,
  config : CaptchaConfig,
) -> ClickWordData {
  let word_count = config.word_total_count
  let han_zi_size = config.han_zi_size
  // 定义随机 1 到 arr.length 某一个字不参与校验
  let decoy_index = rng.random_range(1, word_count) - 1
  let secret_key = if config.aes_enabled { rng.random_string(16) } else { "" }
  let words = random_words(rng, word_count)
  let chars : Array[ClickWordChar] = []
  let word_list : Array[String] = []
  let point_list : Array[@protocol.Point] = []
  for i, word in words {
    let point = random_word_point(
      rng, image_width, image_height, i, word_count, han_zi_size,
    )
    // 随机颜色（RGB 各 [1,255]）与 ±45° 旋转，对齐 Java 绘制期随机
    let color = (255 << 24) |
      (rng.random_range(1, 256) << 16) |
      (rng.random_range(1, 256) << 8) |
      rng.random_range(1, 256)
    let rotation = rng.random_range(-45, 46)
    chars.push({ word, x: point.x(), y: point.y(), color, rotation, })
    if i != decoy_index {
      // 所有绘制点共用同一个 secretKey（对齐 Java 逐点 setSecretKey）
      word_list.push(word)
      point_list.push(@protocol.Point::make(point.x(), point.y(), secret_key))
    }
  }
  { chars, word_list, point_list, secret_key, }
}

///|
/// get 流程的存储步骤：图像由集成层绘制后，把坐标写入缓存（TTL 120s）。
pub fn click_word_store(
  config : CaptchaConfig,
  cache : &@cache.Cache,
  token : String,
  point_list : Array[@protocol.Point],
) -> Unit {
  cache.set(
    captcha_key(token),
    @protocol.Point::list_to_captcha_json(point_list),
    config.expires_in_seconds,
  )
}

///|
/// check 流程，对齐 ClickWordCaptchaServiceImpl#check：
/// 1. token 查缓存（坐标数组），**取出后立即删除**
/// 2. 以第一个点的 secretKey 解密前端点击坐标数组
/// 3. 逐点比较：|Δx| ≤ 字号 且 |Δy| ≤ 字号（默认 25）
/// 4. 通过后生成二次校验凭证存缓存（TTL 180s）
pub fn click_word_check(
  config : CaptchaConfig,
  cache : &@cache.Cache,
  token : String,
  point_json : String,
) -> @protocol.ResponseModel {
  let key = captcha_key(token)
  let stored = match cache.get(key) {
    Some(s) => s
    None => return @protocol.ResponseModel::error(@protocol.ApiCaptchaInvalid)
  }
  // 验证码只用一次，即刻失效
  cache.delete(key)
  let expected = match @protocol.Point::parse_captcha_json_array(stored) {
    Ok(points) => points
    Err(_) =>
      return @protocol.ResponseModel::error_msg(
        Error,
        "验证码坐标解析失败",
      )
  }
  if expected.length() == 0 {
    return @protocol.ResponseModel::error_msg(
      Error,
      "验证码坐标解析失败",
    )
  }
  let user_json = match
    @crypto.aes_decrypt(point_json, expected[0].secret_key()) {
    Some(s) => s
    None =>
      return @protocol.ResponseModel::error_msg(
        Error,
        "验证码坐标解析失败",
      )
  }
  let clicked = match @protocol.Point::parse_captcha_json_array(user_json) {
    Ok(points) => points
    Err(_) =>
      return @protocol.ResponseModel::error_msg(
        Error,
        "验证码坐标解析失败",
      )
  }
  // 对齐 Java：按服务端点数遍历，点击数不足按解析失败处理
  if clicked.length() < expected.length() {
    return @protocol.ResponseModel::error_msg(
      Error,
      "验证码坐标解析失败",
    )
  }
  let tolerance = config.han_zi_size
  for i, p in expected {
    let q = clicked[i]
    if p.x() - tolerance > q.x() ||
      q.x() > p.x() + tolerance ||
      p.y() - tolerance > q.y() ||
      q.y() > p.y() + tolerance {
      return @protocol.ResponseModel::error(@protocol.ApiCaptchaCoordinateError)
    }
  }
  store_second_verification(
    config,
    cache,
    token,
    user_json,
    expected[0].secret_key(),
    "clickWord",
  )
}

///|
/// verification 流程（业务后端二次校验），与 blockPuzzle 完全一致。
pub fn click_word_verification(
  config : CaptchaConfig,
  cache : &@cache.Cache,
  captcha_verification : String,
) -> @protocol.ResponseModel {
  verification(config, cache, captcha_verification)
}
