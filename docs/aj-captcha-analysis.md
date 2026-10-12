# AJ-Captcha 源码分析

> 分析对象：[anji-plus/captcha](https://gitee.com/belief-team/captcha)（Gitee 镜像，master 分支，commit 时间 2026-10）
> 目的：为 MoonCaptcha（MoonBit 移植）提供准确的协议与算法依据。

## 1. 仓库结构

```
captcha/
├── core/captcha/                       # 核心库（纯 Java，含 AWT 图像处理）
│   └── com.anji.captcha
│       ├── model/common/               # ResponseModel / RepCodeEnum / CaptchaTypeEnum / Const
│       ├── model/vo/                   # CaptchaVO（请求与响应共用）、PointVO
│       ├── service/                    # CaptchaService、CaptchaCacheService 接口
│       ├── service/impl/               # BlockPuzzle / ClickWord / Default 服务实现、内存缓存、频控
│       └── util/                       # ImageUtils / AESUtil / CacheUtil / RandomUtils / JsonUtil
├── core/captcha-spring-boot-starter/   # Spring Boot 自动装配（AjCaptchaProperties 等）
├── service/                            # 示例服务：springboot / springboot3 / springmvc / go / php
│   └── go/                             # ⭐ Go 语言完整移植（与 MoonCaptcha 场景相同，重点参考）
├── view/                               # 前端组件：vue / vue3 / react-native / uni-app / android / ios / flutter ...
└── images/                             # 仓库根的底图资源
```

验证码类型：`blockPuzzle`（滑动拼图）、`clickWord`（文字点选）为成熟的两种；`rotatePuzzle`（旋转拼图）、`curveSlider`（滑块曲线）为扩展类型。

## 2. 服务接口与工厂

```java
public interface CaptchaService {
    void init(Properties config);
    ResponseModel get(CaptchaVO captchaVO);          // 获取验证码（前端调用）
    ResponseModel check(CaptchaVO captchaVO);        // 核对验证码（前端调用）
    ResponseModel verification(CaptchaVO captchaVO); // 二次校验（业务后端调用）
    String captchaType();
}
```

- `CaptchaServiceFactory`：Java SPI 加载全部 `CaptchaService` 与 `CaptchaCacheService`；`captcha.type=default` 时使用 `DefaultCaptchaServiceImpl` 作为路由器，按请求中的 `captchaType` 分发到具体实现。
- `CaptchaCacheService` 接口：`set / get / exists / delete / increment / setExpire / type`。默认内存实现 `CaptchaCacheServiceMemImpl`（单机）；分布式由接入方实现（demo 提供 Redis 实现）。

## 3. HTTP 协议

示例控制器（`service/springboot/.../CaptchaController.java`）暴露三个 POST 端点，请求体均为 `CaptchaVO` 的 JSON：

| 端点 | 用途 | 关键入参 | 关键出参（repData） |
| --- | --- | --- | --- |
| `POST /captcha/get` | 获取验证码 | `captchaType`（`blockPuzzle` / `clickWord`） | blockPuzzle：`originalImageBase64`(JPG)、`jigsawImageBase64`(PNG)、`token`、`secretKey`；clickWord：`originalImageBase64`(PNG)、`wordList`、`token`、`secretKey` |
| `POST /captcha/check` | 前端核对 | `captchaType`、`token`、`pointJson`（AES 加密的坐标） | 成功时回显 VO（`result=true`） |
| `POST /captcha/verify` | 业务后端二次校验 | `captchaVerification` | 空 |

统一响应包装 `ResponseModel`：`{ "repCode": "0000", "repMsg": "...", "repData": {...} }`。

### 3.1 应答码（RepCodeEnum）

| code | 含义 |
| --- | --- |
| `0000` | 成功 |
| `0001` | 操作失败（通用错误） |
| `9999` | 服务器内部异常 |
| `0011` | `{0}不能为空` |
| `6110` | 验证码已失效，请重新获取 |
| `6111` | 验证失败（坐标不匹配） |
| `6112` | 获取验证码失败 |
| `6113` | 底图未初始化成功 |
| `6201` | get 接口请求次数超限 |
| `6202` | 接口验证失败数过多，get 被锁定 |
| `6204` | check 接口请求次数超限 |
| `6205` | verify 请求次数超限 |
| `6206` | 无效请求 |

## 4. 加密方案

`AESUtil`：**AES/ECB/PKCS5Padding**，密钥为 16 字符随机串（`getRandomString(16)`，字母+数字 62 字符池）按 UTF-8 直接作为 16 字节密钥。

- `getKey()` → 16 位随机字符串（每个验证码独立）。
- `aesEncrypt(content, key)`：key 为空白时**原文直通**（即关闭 AES 的模式）；否则 AES 加密后 Base64。
- `aesDecrypt(encrypted, key)`：key 为空白时原文直通。
- 输出 Base64 使用标准字母表，无换行。

前端（`view/vue/.../utils/ase.js`）使用 CryptoJS：`CryptoJS.enc.Utf8.parse(keyWord)` + `mode: ECB` + `pad: Pkcs7` —— 与后端完全对齐（原始字节密钥，非 passphrase 模式）。默认密钥示例 `XwKsGlMcdPMEhR1B`。

> 结论：MoonCaptcha 需要实现 **AES-128 + ECB + PKCS7 + Base64**，即可与现有前端组件字节兼容。

## 5. 滑动拼图（BlockPuzzleCaptchaServiceImpl）

### 5.1 get 流程

1. 从底图缓存随机取一张背景图（310×155），右下角绘制白色水印（字体 WenQuanZhengHei.ttf，字号 12.5）。
2. 随机取一个滑块模板 PNG（**94×310 全高透明画布，不透明像素集中在上部 ≈155 行内**）。
3. `generateJigsawPoint`：`x ∈ [200, W - jigsawWidth - 200)`（`RandomUtils.getRandomInt(start,end)` 为左闭右开）；`y`：若 `H - jigsawHeight <= 0` 则 **y = 5**。⚠️ 标准底图高 155 < 模板高 310，因此 **y 恒等于 5** —— 这正是前端硬编码提交 `{x, y: 5.0}` 的原因（`VerifySlide.vue:281`）。
4. 若 `captcha.aes.status=true`（默认），生成 secretKey。
5. `cutByTemplate`（见 §7）在背景 `(x, 0)` 处抠图：生成带 alpha 的滑块小图 + 背景凹槽（模糊 + 白描边）。
6. 干扰项（`captcha.interference.options`，默认 0）：1=在主抠图右侧再扣一个假缺口；2=额外在左侧再扣一个。干扰块只处理背景，不产出小图。
7. 底图输出 **JPG** Base64（体积小），滑块输出 **PNG** Base64。
8. `token = UUID（32 位无连字符）`；以 `RUNNING:CAPTCHA:{token}` 为 key，缓存 `PointVO JSON`（`{"secretKey":"...","x":123,"y":5}`），TTL **120s**。

### 5.2 check 流程

1. `RUNNING:CAPTCHA:{token}` 不存在 → `6110`。**取出后立即删除**（一次性）。
2. 用缓存中的 secretKey 解密 `pointJson`（前端提交的 `AES({"x": moveLeftDistance, "y": 5.0})`）。
3. 坐标比较（均为 int，`PointVO` 字段为 int，前端浮点数会被截断）：

```java
if (point.x - slipOffset > point1.x      // slipOffset 默认 "5"
        || point1.x > point.x + slipOffset
        || point.y != point1.y)          // y 要求精确相等！
    return API_CAPTCHA_COORDINATE_ERROR; // 6111
```

4. 通过后：`captchaVerification = AES(token + "---" + pointJson, secretKey)`，以 `RUNNING:CAPTCHA:second-{captchaVerification}` 为 key 存入缓存（value=token，TTL **180s**）。
5. ⚠️ 服务端**并不回传** captchaVerification 字段；前端自行用同一算法构造（`VerifySlide.vue:300`：`aesEncrypt(backToken + '---' + JSON.stringify({x, y:5.0}), secretKey)`）。由于 ECB 确定性加密且明文逐字节相同，前后端构造结果一致，业务后端拿它调用 verify 能命中缓存。

### 5.3 verification 流程（业务后端二次校验）

1. `RUNNING:CAPTCHA:second-{captchaVerification}` 不存在 → `6110`。
2. **取出后立即删除**（防重放）。
3. 成功返回 `0000`。

## 6. 文字点选（ClickWordCaptchaServiceImpl）

### 6.1 get 流程

1. 随机取点选底图（310×155 PNG）。
2. `wordTotalCount`（默认 4）个汉字从常用字池 `HAN_ZI`（约 300 个高频字）去重随机选取。
3. 抽 `num ∈ [1, wordCount)`（左闭右开 → 1..3），**第 num-1 个字只绘制、不加入校验集合**（干扰字）。因此默认绘制 4 字、需点击 3 字，且干扰字永不落在最后一个。
4. 坐标分列：`avgWidth = width / (wordCount + 1)`；第 i 个字 x 落在第 i 列 `[avgWidth*i + 12, avgWidth*(i+1) - 12)`（12 = HAN_ZI_SIZE_HALF），y ∈ `[25, H - 25)`。字体随机颜色（RGB 各 1..255）、随机旋转 ±45°、字号 25。
5. 绘制白色水印。
6. `wordList`（需点击的字，按顺序）+ `token` + `secretKey` 返回；`pointList`（每个点带 secretKey）序列化为 JSON 数组存 `RUNNING:CAPTCHA:{token}`，TTL 120s，**不下发前端**。

### 6.2 check 流程

1. 取缓存 pointList（数组），**以第一个点的 secretKey** 解密前端 `pointJson`（前端提交 `AES(JSON.stringify(checkPosArr))`，`checkPosArr` 为点击坐标数组）。
2. 逐点比较，容差 = **字号 25**（x、y 双向开区间比较）：

```java
if (point[i].x - 25 > point1[i].x || point1[i].x > point[i].x + 25
        || point[i].y - 25 > point1[i].y || point1[i].y > point[i].y + 25)
    return 6111;
```

3. 通过后同 blockPuzzle：`AES(token---pointJson)` 存 second-key，TTL 180s。

### 6.3 verification

与 blockPuzzle 完全一致（同一套 second-key 机制）。

## 7. 抠图算法（cutByTemplate / interferenceByTemplate）

输入：背景图（RGB）、模板图（RGBA，形状由 alpha 定义）、抠图原点 (x, 0)。逐像素按模板 alpha 分派：

```java
int alpha = (templateRgb >> 24) & 0xff;
if (alpha > 0) {
    if (alpha > 200) {                          // 内部像素
        // 滑块小图：背景像素 + 模板 alpha
        newImage.setRGB(i, j, (alpha << 24) | (oriRgb & 0x00FFFFFF));
        // 背景：3×3 均值模糊（排除中心像素，共 8 个），形成凹槽
        oriImage.setRGB(x + i, y + j, avgMatrix(martrix));
    } else {                                     // 边缘过渡像素 (1..200)
        // 背景：按 alpha 比例与白色混合（白描边）
        oriImage.setRGB(x + i, y + j, blendWithWhite(oriRgb, alpha));
        // 滑块小图：白色 + 模板 alpha
        newImage.setRGB(i, j, (alpha << 24) | 0x00FFFFFF);
    }
}
```

- `blendWithWhite`：`ratio = alpha/255`，`nr = r*(1-ratio) + 255*ratio`（g、b 同理），输出 alpha=255。
- `avgMatrix`：3×3 邻域中**跳过中间整行**（`j==1` 对应 y 行的 3 个像素），对上下两行共 6 个像素求 R/G/B 和后**仍除以 8**（除数硬编码，凹槽因此偏暗）。边界处理：越界 x 取绝对值（`tx=-tx`）、越界 y 用当前 y 代替（`readPixel`）。
- 干扰块与主块逻辑一致（模糊 + 白描边），但不生成小图。
- alpha=0 像素完全跳过（背景保持原样）。

该算法只依赖**像素缓冲读写**，不依赖 AWT 特性 —— 可直接移植为 MoonBit 的 `PixelBuffer` 版本。

## 8. 缓存实现（CacheUtil，内存版）

- 结构：`Map<key, value>` + `Map<key_HoldTime, 过期毫秒时间戳>`。
- `set(key, value, expiresInSeconds)`：写入值与过期时间；**超过 `CACHE_MAX_NUMBER*2`（默认 2000）时整体 clear**（粗暴但有效的内存保护）。
- `exists`：懒淘汰 —— 读取时过期即删；另有定时器每 180s 主动刷新（默认）。
- `get`：先 exists 再取值。
- 频控用的 `increment`：读值累加后 `set(key, ret, 0)`（**不过期**，靠计数器首次时 `set(key,"1",60)` 覆盖 TTL）。

## 9. 接口频控（FrequencyLimitHandler.DefaultLimitHandler，默认关闭）

以 `clientUid`（优先 `MD5(browserInfo=ip+userAgent)`，其次组件实例 id）为维度：

| 接口 | 限制 | key |
| --- | --- | --- |
| get | 1 分钟 ≤120 次（可配） | `AJ.CAPTCHA.REQ.LIMIT-GET-{uid}` |
| get | 1 分钟内 check 失败 >5 次 → 锁定 300s | `...-FAIL-{uid}` / `...-LOCK-{uid}` |
| check | 1 分钟 ≤600 次 | `...-CHECK-{uid}` |
| verify | 1 分钟 ≤600 次 | `...-VERIFY-{uid}` |

## 10. 配置项（AjCaptchaProperties 默认值）

| 配置 | 默认值 | 说明 |
| --- | --- | --- |
| `aj.captcha.type` | default | default=路由全部类型 |
| `aj.captcha.water-mark` | 我的水印 | 右下角水印 |
| `aj.captcha.water-font` / `font-type` | WenQuanZhengHei.ttf | 水印/点选字体 |
| `aj.captcha.slip-offset` | 5 | 滑动 x 容差（px） |
| `aj.captcha.curve-offset` | 8 | 曲线容差 |
| `aj.captcha.font-size` | 25 | 点选字号（也是点击容差） |
| `aj.captcha.word-count` | 4 | 点选绘制字数（点击数 = n-1） |
| `aj.captcha.interference-options` | 0 | 滑动干扰 0/1/2 |
| `aj.captcha.aes-status` | true | AES 加密开关 |
| `aj.captcha.cache-type` | local | local / redis |
| `aj.captcha.cache-number` | 1000 | 内存缓存阈值 |
| `aj.captcha.timing-clear` | 180 | 定时清理周期（秒） |
| `aj.captcha.req.get.minute.limit` | 120 | get 频控 |
| `aj.captcha.req.get.lock.limit` | 5 | 失败锁定阈值 |
| `aj.captcha.req.get.lock.seconds` | 300 | 锁定时长 |

TTL 常量（硬编码于 AbstractCaptchaService）：验证码坐标 **120s**、二次校验凭证 **180s**；缓存 key 前缀 `RUNNING:CAPTCHA:` 与 `RUNNING:CAPTCHA:second-`。

## 11. 已知怪癖与迁移注意事项

1. **y 坐标怪癖**：标准底图（155 高）下滑动拼图 y 恒为 5，前端硬编码 `y: 5.0`；check 要求 y 精确相等。MoonCaptcha 需保持此约定才能兼容现有前端。
2. **captchaVerification 由前端构造**：服务端 check 不回传该字段，依赖 ECB 确定性 + 明文一致来保证两端结果一致。`pointJson` 必须原样（解密后的字符串）参与拼接，不能重新序列化。
3. **坐标类型**：`PointVO.x/y` 是 int，前端浮点坐标被截断（85.9 → 85）。比较前先截断。
4. **模板尺寸 94×310**：滑块模板是全高画布，不透明像素仅在上部；`cutByTemplate` 按模板坐标系平移，越界行 alpha=0 被跳过。
5. **默认底图资源错位**：核心库代码加载 `defaultImages/jigsaw/original`，但仓库资源实际在 `images/jigsaw/original`（bg1-6.png）——开箱即用时底图加载会失败（6113），需自备底图。**MoonCaptcha 打包资源时必须避免此问题。**
6. **JsonUtil 为手写极简实现**：仅支持 PointVO 的序列化/解析（`{"secretKey":"..","x":..,"y":..}`），数组按 `}` 切分。前端提交的 `{"x":111.0976,"y":5}` 也能解析（`Double.valueOf` 截断）。
7. **secretKey 明文下发前端**：AES 密钥随 get 响应下发，其定位是"防篡改混淆 + 绑定 captchaVerification"，不是机密。真正的安全边界在服务端缓存的一次性 token 与 TTL。
8. **干扰字逻辑**：`num ∈ [1, wordCount)`，最后一个字永不成为干扰字；点击容差=字号（双向 ±25px）。
9. **increment 计数键不过期**：首次 set 带 60s TTL，后续 increment 覆盖为永不过期 —— 迁移时修正为滑动窗口更合理。
10. **水印字体 12.5px**（HAN_ZI_SIZE/2），点选字号 25px；中英文混排水印宽度按 `汉字*12.5+5 + 英文*8` 估算。

## 12. 对 MoonCaptcha 迁移的关键结论

1. **协议层可 100% 兼容**：三个端点、repCode、字段名、AES/ECB/PKCS7、`token---pointJson` 拼接规则全部明确，现有 AJ-Captcha 前端组件（vue/uni-app/android...）可直接对接 MoonCaptcha 后端。
2. **核心校验逻辑是纯函数**：坐标比较、token 生命周期、AES、随机点生成都可脱离图像独立实现与测试 —— 适合作为第一里程碑。
3. **图像栈需求收敛为三件事**：PNG 编解码（含 zlib）、RGBA PixelBuffer 上的模板抠图（§7 算法，无 AWT 依赖）、字体光栅化（水印 + 点选文字）。Go 移植（service/go）同样选择了「PNG 标准库 + freetype」组合，验证了该路线。
4. **缓存/频控是接口 + 内存默认实现**，与 MoonBit trait 语义一一对应。
