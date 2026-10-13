# MoonCaptcha 迁移设计

> 依据：[AJ-Captcha 源码分析](./aj-captcha-analysis.md)（下称"分析文档"）
> 状态：M1 / M2a 已交付并通过 `moon test`；Web 登录演示已提前交付；类库化设计见 §8。
> 修订记录：2026-10-12/13 增补类库化设计（§8）；交付 M2b PNG 编解码、M2c 资源池、M3 字体光栅化、**M4 安全默认值与门面**（secure_random.mbt：`@env.rand` 跨平台 CSPRNG + 拒绝采样 key16；limit.mbt：滑动窗口频控修复 increment 缺陷 + 失败锁定默认开启；captcha_service.mbt：`CaptchaService` 门面 + CaptchaKind/CaptchaError），88 测试全绿。图像栈 M1–M3 完成：双模式完整 get + 真实底图逐像素验证 + 文泉驿真实字体目视验证。

## 1. 目标与非目标

**目标**

1. **协议兼容**：与 AJ-Captcha 生态的现有前端组件（vue / uni-app / android / ios / flutter 等）直接对接——端点、`repCode`、字段名、AES/ECB/PKCS7 加密格式、`token---pointJson` 拼接规则全部保持字节级一致。
2. **核心逻辑 MoonBit 化**：验证流程（get / check / verification）、令牌生命周期、坐标校验、加密、缓存全部以 MoonBit 实现，可编译到 WASM / JS / Native。
3. **图像栈自足**：PNG 编解码、RGBA 像素缓冲上的模板抠图、字体光栅化均为纯 MoonBit 实现，不依赖任何宿主图形库。
4. **可作为第三方类库分发**（2026-10-12 增补）：发布到 mooncakes.io，默认配置安全、API 稳定可演进、多目标验证、文档与示例齐备——详见 §8。

**非目标（首阶段）**

- 不兼容 `rotatePuzzle` / `curveSlider` 扩展类型（列入 M5）。
- 不内置 HTTP 框架——集成层由宿主环境适配（见 §6）。

## 2. 总体架构

```
┌─────────────────────────────────────────────────────┐
│            集成层（宿主适配，M4）                      │
│   HTTP 服务(WASM/Native) · 前端 SDK · 边缘运行时      │
├─────────────────────────────────────────────────────┤
│  service/  验证服务：门面 CaptchaService · get/check  │
│            verification · blockPuzzle / clickWord    │
├──────────────┬──────────────┬───────────────────────┤
│  protocol/   │   cache/     │   crypto/             │
│  repCode     │  Cache trait │  AES-128/ECB/PKCS7    │
│  ResponseModel  MemoryCache │  (+CSPRNG 门面, §8.2) │
│  Point JSON  │  (可替换Redis)│                       │
├──────────────┴──────────────┴───────────────────────┤
│  image/  PixelBuffer(ARGB) · 模板抠图 · 模糊/描边     │
│  (M2)    PNG 编解码 · 字体光栅化 · 底图资源池         │
├─────────────────────────────────────────────────────┤
│  common/  RNG(splitmix64) · UUID · Base64 · jsonlite │
└─────────────────────────────────────────────────────┘
```

## 3. 包结构与映射

| AJ-Captcha (Java) | MoonCaptcha (MoonBit) | 说明 |
| --- | --- | --- |
| `model/common/RepCodeEnum` | `src/protocol/repcode.mbt` | 应答码枚举，code/描述一一对应 |
| `model/common/ResponseModel` | `src/protocol/response.mbt` | `{repCode, repMsg, repData}` 序列化 |
| `model/vo/PointVO` + `util/JsonUtil` | `src/protocol/point.mbt` | `{"secretKey":"..","x":..,"y":..}` 字节级兼容序列化/解析 |
| `model/vo/CaptchaVO` | `src/protocol/vo.mbt` | 请求/响应 VO（get repData 组装） |
| `service/CaptchaService` | `src/service/`（按类型分文件） | get / check / verification 流程；门面见 §8.1 |
| `service/impl/BlockPuzzleCaptchaServiceImpl` | `src/service/block_puzzle.mbt` | 校验逻辑 + 生成参数逻辑 |
| `service/impl/ClickWordCaptchaServiceImpl` | `src/service/click_word.mbt` | 分列布点 + 逐点容差校验 |
| `service/impl/CaptchaCacheServiceMemImpl` + `util/CacheUtil` | `src/cache/` | `Cache` trait + 内存实现（可替换 Redis） |
| `util/AESUtil` | `src/crypto/aes.mbt` + `base64`（移至 common） | AES-128/ECB/PKCS7 |
| `util/RandomUtils` | `src/common/random.mbt` | splitmix64 PRNG，区间语义与 Java 一致；安全默认见 §8.2 |
| `util/ImageUtils` | `src/image/`（M2b/M2c） | 底图资源池 |
| `cutByTemplate / interferenceByTemplate` | `src/image/cut.mbt`（✅ 已实现） | PixelBuffer 版本，逐像素对照移植（含 avgMatrix 除 8 怪癖） |
| 字体绘制（Graphics2D/freetype） | `src/image/font/`（M3） | 字体光栅化 |
| `FrequencyLimitHandler` | `src/service/limit.mbt`（M4） | 频控（默认开启，见 §8.2） |
| `controller`（Spring 示例） | 集成层（M4）/ `demo/`（Node 参考实现 ✅） | 宿主 HTTP 框架适配 |

## 4. 关键设计决策

### 4.1 字节级协议兼容（最高优先级）

分析文档 §5/§6 的每一处字节细节都是接口契约：

- 存储格式：`RUNNING:CAPTCHA:{token}` → `{"secretKey":"..","x":123,"y":5}`（TTL 120s）；`RUNNING:CAPTCHA:second-{verification}` → token（TTL 180s）。
- check 通过后 `verification = AES(token + "---" + pointJson)`，其中 `pointJson` 必须是**解密后的原字符串**，不得重新序列化（前端本地构造同名凭证依赖 ECB 确定性，字节不同即校验失败）。
- 滑动拼图坐标比较：`|Δx| ≤ slip_offset(5)` 且 **y 严格相等**；点选比较：逐点 `|Δx| ≤ 字号(25)` 且 `|Δy| ≤ 25`。
- 前端浮点坐标按 int 截断后再比较。

### 4.2 可注入的副作用：时间与随机

- `Cache::MemoryCache` 构造时注入 `now_ms : () -> Int64` 时钟（测试注入可控假时钟；集成层接各目标平台的真实时钟）。
- `Rng` 显式传参、可播种（测试用固定种子保证可复现）。**类库化修订**：分发形态下不能要求集成方自己提供熵源——`common` 将补充 CSPRNG 门面（各 target extern 到平台安全随机），作为服务层默认构造；可播种 RNG 仅保留给测试（§8.2）。

### 4.3 自实现 AES-128/ECB/PKCS7

S 盒由 GF(2^8) 求逆 + 仿射变换**程序化生成**（避免手抄 256 项查找表出错），FIPS-197 标准测试向量验证，另与 Node.js `crypto` 对拍确认；ECB + PKCS7 分组填充；空密钥时明文直通（对应 `captcha.aes.status=false` 的 Java 行为）。

### 4.4 jsonlite 迷你 JSON

AJ-Captcha 自身就用极简 JSON（`JsonUtil` 仅支持 PointVO）。MoonCaptcha 在 `src/common/jsonlite.mbt` 实现协议子集的解析（对象/数组/字符串/数字），序列化则由 protocol 包按精确格式拼装——解析兼容前端 `JSON.stringify` 的浮点输出（如 `{"x":111.0976,"y":5}`），数值统一截断为 int。

### 4.5 图像栈分期

| 阶段 | 内容 | 状态 |
| --- | --- | --- |
| M2a | `PixelBuffer`（ARGB int，对齐 Java `getRGB/setRGB` 语义）+ `cut_by_template` + 干扰块 + 模糊 + 白描边 | ✅ 已交付 |
| M2b | PNG 编解码（zlib inflate 全块型 + stored 编码；Node.js 对拍验证） | ✅ 已交付（2026-10-12） |
| M3 | 字体光栅化（TTF glyf 解析 + 二次贝塞尔细分 + 4×4 超采样 nonzero 填充；draw_text/draw_watermark） | ✅ 已交付（2026-10-12，文泉驿真实字体目视验证） |
| M2c | ImagePool 资源池（三类图 + PNG 字节注册 + 随机选取）+ tools/gen-assets.js 构建期嵌入工具（⚠️ 规避 AJ-Captcha 的 defaultImages/ 资源错位问题） | ✅ 已交付（2026-10-12） |

> 2026-10-12 修正：重读 Java 源码确认 `avgMatrix` 为 6 像素求和后**仍除以 8**（除数硬编码），M2a 初版误作除 6，已修正并更新测试（`765/8=95`）。该偏差影响凹槽明暗，属视觉级差异。

### 4.6 对 AJ-Captcha 行为的有意修正

1. `CacheUtil.increment` 计数键不过期（分析文档 §11.9）——频控实现（M4）时改为正确 TTL / 滑动窗口。
2. `generateJigsawPoint` 在小底图下会因 `nextInt(负数)` 抛异常（分析文档 §11 注）——MoonCaptcha 对 `width ≤ jigsawWidth + 200` 回退 `x = 5`，不 panic。
3. jsonlite 解析失败返回显式错误而非静默 null。
4. `PointVO.toJsonString()` 对空 secretKey 输出字符串 `"null"`——MoonCaptcha 输出空字符串。

## 5. 里程碑

| 里程碑 | 内容 | 状态 |
| --- | --- | --- |
| **M1 核心逻辑** | common（RNG/UUID/Base64/jsonlite）· crypto（AES/ECB/PKCS7）· cache（trait + 内存实现）· protocol（repCode/VO/Point）· service（blockPuzzle / clickWord 的 check、verification、生成参数） | ✅ 已交付 |
| **M2 图像栈** | M2a 抠图 ✅ → M2b PNG 编解码 ✅ → M2c 资源池 ✅；**blockPuzzle 完整 get 已打通**（get→check→verify 全链路测试 + 真实底图/模板逐像素验证） | ✅ 已交付（clickWord get 待 M3 字体） |
| **M3 文字绘制** | 字体光栅化 ✅，**clickWord 完整 get 已打通**（文字含干扰字烧录 + 水印） | ✅ 已交付 |
| **M4 集成层与安全默认值** | 门面 `CaptchaService`（§8.1）· CSPRNG 默认构造（§8.2）· 频控默认开启 · HTTP 端点适配（WASM/Native）· Redis 缓存参考实现。Web 登录演示（`demo/`，Node 参考集成）已提前交付 ✅ | 🔄 进行中 |
| **M5 扩展** | rotatePuzzle / curveSlider、图形验证码（传统字符型）、UI 组件 | 待办 |
| **M6 类库发布就绪**（2026-10-12 增补） | semver + CHANGELOG + `.mbti` 入库 · 三目标（wasm/js/native）CI · mooncakes.io 发布 · 公开 API doc comment 全覆盖 · 三平台集成示例 + AJ-Captcha 迁移指南 · `demo/` → `examples/` · 资源许可声明（§8.5） | 待办 |

## 6. 集成层形态（预设，M4 落地）

服务层暴露的纯函数接口（`block_puzzle_check(config, cache, token, point_json)` 等）不绑定任何运行时，集成层只需：

1. 提供真实时钟与熵源（各平台 extern；M4 后熵源由库默认提供，见 §8.2）；
2. 实现 `Cache`（内存 / Redis / 边缘 KV）；
3. 提供 `POST /captcha/get | /captcha/check | /captcha/verify` 三个端点的参数搬运与 `ResponseModel` JSON 直出。

参考实现：`demo/`（Node.js 零依赖，含 PNG 编解码与完整协议流程，协议端到端 14 项 + 浏览器真实输入实测通过）。

## 7. 交付记录

| 日期 | 内容 | 提交 |
| --- | --- | --- |
| 2026-10-11 | M1 核心逻辑 + M2a 抠图算法，58 项测试全绿（AES 与 Node.js 对拍验证） | `ba14edc` |
| 2026-10-12 | avgMatrix 除数偏差修正（/6 → /8） | `829ea85` |
| 2026-10-12 | Web 登录演示页（双模式验证码 + 协议端到端 14 项 + 浏览器实测） | `425aa50` |
| 2026-10-12 | README 双语拆分 | `4a572d9` |
| 2026-10-12 | M2b PNG 编解码（zlib inflate 全块型 + stored 编码 + PNG 容器，67 测试） | 待提交 |

## 8. 类库化设计（分发就绪要求）

2026-10-12 评估结论：当前代码离"可分发的第三方类库"的差距不在代码质量，而在**端到端能力、安全默认值、API 稳定性承诺与发布工程**四方面。

### 8.1 门面 API

现状是按类型的自由函数（`block_puzzle_check(config, cache, token, point_json)`），参数组装暴露给调用方。分发形态需要：

- `CaptchaService` 结构体门面：构造时收拢 config / cache / 时钟 / RNG，暴露 `get / check / verify` 三个方法，与 AJ-Captcha 的 `CaptchaService` 接口同名同构，降低迁移心智成本。
- `CaptchaConfig` 补充 builder 风格的默认值构造（已有 `default()`，补齐频控、水印等字段）。
- 错误路径统一：当前 `Result[_, String]` 与 `ResponseModel` 混用，门面层收敛为 `CaptchaError` 枚举（Invalid / CoordinateMismatch / BasemapMissing / RateLimited / Internal），repCode 映射收口在一处。
- 扩展点正式化：`Cache` trait 已有；补自定义底图注册（对应 `ImageUtils.cacheBootImage`）与自定义验证码类型注册表（对应 Java SPI，M5 一并考虑）。

### 8.2 安全默认值（分发红线）

与"自己用"最本质的区别——**默认配置必须安全**：

- **CSPRNG 门面**：splitmix64 非密码学安全且需显式种子，集成方随手 `Rng::new(1)` 会导致 token / secretKey 可预测。在 `common` 增加 `SecureRandom`（wasm → `Crypto.getRandomValues`，js 同，native → OS 熵源 extern），作为服务层默认；`Rng` 可播种版本仅服务测试。
- **频控默认开启**：Java 版限流默认关；类库反转——get ≤120/min、失败 5 次锁 300s 等默认生效（数值可配），并修正 `increment` 键不过期缺陷（§4.6.1）。
- **AES-ECB 定位说明**：ECB 是协议兼容的历史包袱（前端本地构造凭证依赖其确定性），文档必须明示其威胁模型——防篡改混淆而非机密保护，真正的安全边界在一次性 token + TTL + 频控。
- **令牌比较**：token 比较采用常量时间实现（成本极低，防御性收益）。

### 8.3 API 稳定性

- 语义化版本：0.x 阶段明确"minor 可能含破坏性变更"，1.0 起严格 semver；CHANGELOG 从首个对外版本维护。
- `moon info` 生成的 `.mbti` 接口文件提交入库，API 变更在 review 中强制可见；同时审查收窄导出面（`pub(all)` 的 struct 字段同为承诺）。
- 公开 API 的 doc comment 全覆盖（现为部分覆盖），`moon doc` 产出 API 参考。

### 8.4 多目标与 CI

- 三目标（wasm / js / native）`moon check` + `moon test` 矩阵进 GitHub Actions——核心卖点"编译到多目标"必须被 CI 背书；注意每个 target 需先 `moon bundle` 对应 core 标准库。
- `moon fmt` 纳入 CI 检查。

### 8.5 发布、示例与许可

- 发布渠道：mooncakes.io（`moon publish`）。
- 三平台最小集成示例（WASM 绑定 / Native HTTP / JS），一份"从 AJ-Captcha 迁移"指南（最可能的用户群体）。
- `demo/` → `examples/`（或独立仓库），避免用户误将其当作库的一部分；demo 中的 `wordPositions` 演示专用字段在真实集成中必须替换为服务端图片烧录。
- **许可边界**：库本体 Apache-2.0；`demo/assets` 底图复制自 AJ-Captcha（同为 Apache-2.0），协议兼容；若正式发行版内置这些资源建议保留来源与协议声明，或替换为自制底图。
- 错误文案 i18n：`repMsg` 现硬编码中文，类库应只保证 repCode 稳定，文案可配置。

### 8.6 推进顺序

M2b（PNG）→ M3（字体）本身是类库化的前置；完成后按 **安全默认值 → 门面 API + mbti 审查 → 三目标 CI + mooncakes 发布 → 文档/示例** 推进，即 §5 中 M4（安全默认值部分）→ M6。
