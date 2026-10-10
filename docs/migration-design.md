# MoonCaptcha 迁移设计

> 依据：[AJ-Captcha 源码分析](./aj-captcha-analysis.md)（下称"分析文档"）
> 状态：M1 已实现并通过 `moon test`，详见 §7。

## 1. 目标与非目标

**目标**

1. **协议兼容**：与 AJ-Captcha 生态的现有前端组件（vue / uni-app / android / ios / flutter 等）直接对接——端点、`repCode`、字段名、AES/ECB/PKCS7 加密格式、`token---pointJson` 拼接规则全部保持字节级一致。
2. **核心逻辑 MoonBit 化**：验证流程（get / check / verification）、令牌生命周期、坐标校验、加密、缓存全部以 MoonBit 实现，可编译到 WASM / JS / Native。
3. **图像栈自足**：PNG 编解码、RGBA 像素缓冲上的模板抠图、字体光栅化均为纯 MoonBit 实现，不依赖任何宿主图形库。

**非目标（首阶段）**

- 不兼容 `rotatePuzzle` / `curveSlider` 扩展类型（列入后续里程碑）。
- 不内置 HTTP 框架——集成层由宿主环境适配（见 §6）。

## 2. 总体架构

```
┌─────────────────────────────────────────────────────┐
│            集成层（宿主适配，M4）                      │
│   HTTP 服务(WASM/Native) · 前端 SDK · 边缘运行时      │
├─────────────────────────────────────────────────────┤
│  service/  验证服务：get 组装 · check · verification  │
│            blockPuzzle / clickWord / (rotatePuzzle)  │
├──────────────┬──────────────┬───────────────────────┤
│  protocol/   │   cache/     │   crypto/             │
│  repCode     │  Cache trait │  AES-128/ECB/PKCS7    │
│  ResponseModel  MemoryCache │  Base64               │
│  Point JSON  │  (可替换Redis)│                       │
├──────────────┴──────────────┴───────────────────────┤
│  image/  PixelBuffer(ARGB) · 模板抠图 · 模糊/描边     │
│  (M2)    PNG 编解码 · 字体光栅化(M3)                  │
├─────────────────────────────────────────────────────┤
│  common/  RNG(splitmix64) · UUID · jsonlite          │
└─────────────────────────────────────────────────────┘
```

## 3. 包结构与映射

| AJ-Captcha (Java) | MoonCaptcha (MoonBit) | 说明 |
| --- | --- | --- |
| `model/common/RepCodeEnum` | `src/protocol/repcode.mbt` | 应答码枚举，code/描述一一对应 |
| `model/common/ResponseModel` | `src/protocol/response.mbt` | `{repCode, repMsg, repData}` 序列化 |
| `model/vo/PointVO` + `util/JsonUtil` | `src/protocol/point.mbt` | `{"secretKey":"..","x":..,"y":..}` 字节级兼容序列化/解析 |
| `model/vo/CaptchaVO` | `src/protocol/vo.mbt` | 请求/响应 VO（get repData 组装） |
| `service/CaptchaService` | `src/service/`（按类型分文件） | get / check / verification 流程 |
| `service/impl/BlockPuzzleCaptchaServiceImpl` | `src/service/block_puzzle.mbt` | 校验逻辑 + 生成参数逻辑 |
| `service/impl/ClickWordCaptchaServiceImpl` | `src/service/click_word.mbt` | 分列布点 + 逐点容差校验 |
| `service/impl/CaptchaCacheServiceMemImpl` + `util/CacheUtil` | `src/cache/` | `Cache` trait + 内存实现（可替换 Redis） |
| `util/AESUtil` | `src/crypto/aes.mbt` + `base64`（移至 common） | AES-128/ECB/PKCS7 |
| `util/RandomUtils` | `src/common/random.mbt` | splitmix64 PRNG，区间语义与 Java 一致 |
| `util/ImageUtils` | `src/image/`（M2） | 底图资源池 |
| `cutByTemplate / interferenceByTemplate` | `src/image/cut.mbt`（M2a，**已实现**） | PixelBuffer 版本，逐像素对照移植 |
| 字体绘制（Graphics2D/freetype） | `src/image/font/`（M3） | 字体光栅化 |
| `FrequencyLimitHandler` | `src/service/limit.mbt`（M4） | 频控（get 120/min 等） |
| `controller`（Spring 示例） | 集成层（M4） | 宿主 HTTP 框架适配 |

## 4. 关键设计决策

### 4.1 字节级协议兼容（最高优先级）

分析文档 §5/§6 的每一处字节细节都是接口契约：

- 存储格式：`RUNNING:CAPTCHA:{token}` → `{"secretKey":"..","x":123,"y":5}`（TTL 120s）；`RUNNING:CAPTCHA:second-{verification}` → token（TTL 180s）。
- check 通过后 `verification = AES(token + "---" + pointJson)`，其中 `pointJson` 必须是**解密后的原字符串**，不得重新序列化（前端本地构造同名凭证依赖 ECB 确定性，字节不同即校验失败）。
- 滑动拼图坐标比较：`|Δx| ≤ slip_offset(5)` 且 **y 严格相等**；点选比较：逐点 `|Δx| ≤ 字号(25)` 且 `|Δy| ≤ 25`。
- 前端浮点坐标按 int 截断后再比较。

### 4.2 可注入的副作用：时间与随机

- `Cache::MemoryCache` 构造时注入 `now_ms : () -> Int64` 时钟（测试注入可控假时钟；集成层接各目标平台的真实时钟）。
- `Rng` 显式传参、可播种（测试用固定种子保证可复现；集成层负责提供真实熵源）。核心逻辑因此**完全确定、可离线测试**。

### 4.3 自实现 AES-128/ECB/PKCS7

S 盒由 GF(2^8) 求逆 + 仿射变换**程序化生成**（避免手抄 256 项查找表出错），FIPS-197 标准测试向量验证；ECB + PKCS7 分组填充；空密钥时明文直通（对应 `captcha.aes.status=false` 的 Java 行为）。

### 4.4 jsonlite 迷你 JSON

AJ-Captcha 自身就用极简 JSON（`JsonUtil` 仅支持 PointVO）。MoonCaptcha 在 `src/common/jsonlite.mbt` 实现协议子集的解析（对象/数组/字符串/数字），序列化则由 protocol 包按精确格式拼装——解析兼容前端 `JSON.stringify` 的浮点输出（如 `{"x":111.0976,"y":5}`），数值统一截断为 int。

### 4.5 图像栈分期

| 阶段 | 内容 | 状态 |
| --- | --- | --- |
| M2a | `PixelBuffer`（ARGB int，对齐 Java `getRGB/setRGB` 语义）+ `cut_by_template` + 干扰块 + 高斯近似模糊 + 白描边 | ✅ 本次交付，合成图像测试 |
| M2b | PNG 编解码（inflate/deflate；编码先用 stored block，合法但未压缩） | 待办 |
| M3 | 字体光栅化（水印 + 点选文字随机旋转/颜色），候选方案：内嵌位图字体或解析 TTF glyf | 待办 |
| M2c | 底图资源打包（⚠️ 规避 AJ-Captcha 的 `defaultImages/` 资源错位问题，分析文档 §11.5） | 待办 |

### 4.6 对 AJ-Captcha 行为的有意修正

1. `CacheUtil.increment` 计数键不过期（分析文档 §11.9）——频控实现（M4）时改为滑动窗口/正确 TTL。
2. `generateJigsawPoint` 在小底图下会因 `nextInt(负数)` 抛异常（分析文档 §11 注）——MoonCaptcha 对 `width ≤ jigsawWidth + 200` 回退 `x = 5`，不 panic。
3. jsonlite 解析失败返回显式错误而非静默 null。

## 5. 里程碑

| 里程碑 | 内容 | 状态 |
| --- | --- | --- |
| **M1 核心逻辑** | common（RNG/UUID/Base64/jsonlite）· crypto（AES/ECB/PKCS7）· cache（trait + 内存实现）· protocol（repCode/VO/Point）· service（blockPuzzle / clickWord 的 get 参数生成、check、verification） | ✅ 本次交付 |
| **M2 图像栈** | M2a 抠图算法（✅）→ M2b PNG 编解码 → M2c 资源打包；打通 blockPuzzle 完整 get | 进行中 |
| **M3 文字绘制** | 字体光栅化，打通 clickWord 完整 get | 待办 |
| **M4 集成层** | HTTP 端点适配（WASM/Native）、频控、Redis 缓存参考实现、前端对接示例 | 待办 |
| **M5 扩展** | rotatePuzzle / curveSlider、图形验证码（传统字符型）、UI 组件 | 待办 |

## 6. 集成层形态（预设，M4 落地）

服务层暴露的纯函数接口（`block_puzzle_check(config, cache, token, point_json)` 等）不绑定任何运行时，集成层只需：

1. 实现真实时钟与熵源（各平台 extern）；
2. 实现 `Cache`（内存 / Redis / 边缘 KV）；
3. 提供 `POST /captcha/get | /captcha/check | /captcha/verify` 三个端点的参数搬运与 `ResponseModel` JSON 直出。

## 7. 本次交付（M1 + M2a）清单

- `src/common`：splitmix64 RNG（Java 区间语义）、UUID(32hex)、Base64、jsonlite
- `src/crypto`：AES-128 加解密（S 盒程序化生成）、ECB、PKCS7、字符串级 aes_encrypt/aes_decrypt（空密钥直通）
- `src/cache`：`Cache` trait + `MemoryCache`（可注入时钟、懒淘汰、阈值清理）
- `src/protocol`：RepCode 枚举（与 Java 一一对应）、ResponseModel、Point 兼容序列化/解析、get repData 组装
- `src/service`：配置、缓存 key、blockPuzzle（生成点/check/verification）、clickWord（分列布点+干扰字/逐点校验）、共用 verification
- `src/image`：PixelBuffer、cut_by_template、interference_by_template、blend_with_white、3×3 模糊（M2a）
- 全部模块带单元测试（FIPS-197 AES 向量、坐标容差边界、TTL 过期、抠图像素断言等）
