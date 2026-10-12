# AJ-Captcha → MoonCaptcha 迁移指南

> 面向已有 AJ-Captcha（Java）接入经验、希望迁移到 MoonCaptcha 的团队。
> 协议兼容性依据：[AJ-Captcha 源码分析](./aj-captcha-analysis.md)。

## 1. 迁移收益

| 维度 | AJ-Captcha (Java) | MoonCaptcha (MoonBit) |
| --- | --- | --- |
| 部署形态 | JVM 服务 + Spring 依赖 | 单一产物编译到 WASM/JS/Native，无 VM 依赖 |
| 运行环境 | 服务端 | 浏览器、Node、边缘运行时、嵌入式均可 |
| 缓存抽象 | Java SPI + 线程安全 ConcurrentHashMap | `Cache` trait + 可注入时钟（测试友好） |
| 随机源 | `new Random()`（可预测风险） | 跨平台 CSPRNG 默认（`@env.rand`），可注入固定种子测试 |
| 频控 | 可选（默认关闭） | **默认开启**，滑动窗口（修复 increment 永不过期缺陷） |
| 图像栈 | AWT/Graphics2D（JVM 绑定） | 纯 MoonBit：PNG 编解码 + 模板抠图 + TTF 光栅化 |

## 2. 协议兼容性（可直接对接现有前端组件）

以下契约与 AJ-Captcha **字节级一致**，前端无需任何改动：

- 端点：`POST /captcha/get | /captcha/check | /captcha/verify`，统一包装
  `{repCode, repMsg, repData}`
- repCode 语义与数值完全一致（0000 成功 / 6110 失效 / 6111 坐标错误 /
  6201-6205 频控 / 0011 参数为空）
- 加密：AES-128/ECB/PKCS7，密钥为 16 字符随机串随 get 下发；前端
  `CryptoJS.AES.encrypt(srcs, Utf8.parse(key), {ECB, Pkcs7})` 直接兼容
- 坐标比较：滑动 `|Δx| ≤ 5` 且 **y 严格相等（恒为 5）**；点选逐点 ±25px
- 二次校验凭证：`AES(token + "---" + pointJson)`，由前端本地构造
- 缓存键与 TTL：`RUNNING:CAPTCHA:{token}`（120s）、
  `RUNNING:CAPTCHA:second-{verification}`（180s），均一次性使用
- 底图/滑块模板/点选图尺寸：310×155 / 94×310 / 310×155

差异项（有意修正，见[迁移设计 §4.6](./migration-design.md)）：

| 项 | AJ-Captcha | MoonCaptcha |
| --- | --- | --- |
| 空 secretKey 序列化 | 输出字符串 `"null"` | 输出空字符串 |
| 小底图 get | `nextInt(负数)` 抛异常 | 回退 x=5 正常生成 |
| 频控计数键 | increment 后永不过期 | 每次请求重置 TTL（真滑动窗口） |
| 频控开关 | 默认关闭 | **默认开启**（上限 ≤0 关闭） |
| 底图编码 | JPG | PNG（体积稍大） |
| 复合字形字体 | freetype 渲染 | 自研 glyf 光栅化（文泉驿实测通过） |

## 3. 接入步骤

### 3.1 依赖引入（mooncakes 发布后）

```
# moon.mod
deps = { "mooncaptcha/mooncaptcha" = "0.1.0" }
```

### 3.2 组装服务（推荐：门面 CaptchaService）

```moonbit
// 1. 资源池：底图/滑块模板/点选图（构建期嵌入或运行时字节注册）
let pool = @image.ImagePool::new()
pool.add_original_png(bg_bytes)      // 310×155
pool.add_slider_png(tpl_bytes)       // 94×310 RGBA
pool.add_click_png(click_bytes)      // 310×155

// 2. 字体（可选：点选文字烧录 + 水印；不提供则不绘制）
let font = @image.Font::parse(ttf_bytes)

// 3. 门面：默认安全熵 + 默认频控
let svc = @service.CaptchaService::new(pool, font=Some(font))

// 4. 三个端点（HTTP 宿主只做 JSON 搬运，参照 examples/js-server）
let resp  = svc.get(cache, @service.BlockPuzzle, client_id=client_id)
let check = svc.check(cache, @service.ClickWord, client_id=client_id,
                      token=token, point_json=point_json)
let verify = svc.verify(cache, client_id=client_id,
                        captcha_verification=captcha_verification)
```

`cache` 实现 `@cache.Cache` trait（单机用内置 `MemoryCache`；分布式实现
该 trait 接 Redis 等——五个方法 set/get/exists/delete，语义见 trait 文档）。

`client_id` 建议由服务端可得信息计算（AJ 用 MD5(ip+UA)——MoonCaptcha
不内置 MD5，集成方沿用原有计算即可），为空则跳过频控。

### 3.3 HTTP 集成参照

[examples/js-server](../examples/js-server/README.md)：MoonBit 核心编译到
JS 目标 + Node HTTP 宿主的完整可运行示例（协议 E2E 10/10）。WASM 宿主
（Netlify/Cloudflare/自建 WASI 服务）按同一派发函数模式适配。

### 3.4 底图与字体资产

- 嵌入构建：`tools/gen-assets.js <assets-dir> <output.mbt>`（兼容 AJ-Captcha
  的 `original/slidingBlock/pic-click` 目录布局）
- 注意：若嵌入 AJ-Captcha 自带底图/字体（Apache-2.0），保留其许可声明
- 已知坑规避：AJ-Captcha 核心库 `defaultImages/` 资源错位导致开箱 6113——
  MoonCaptcha 的 ImagePool 空池显式报错并要求注册资源

## 4. 从 AJ-Captcha 已知怪癖迁移的注意事项

详见[分析文档 §11](./aj-captcha-analysis.md)（迁移者应重点阅读）：

1. **y 恒为 5**：滑块模板全高画布 + 标准底图高度 → 前端硬编码 y=5.0，
   服务端 y 严格相等校验——换更高底图时会改变此行为，前端需同步
2. **captchaVerification 前端构造**：依赖 ECB 确定性，`pointJson` 必须用
   解密后的原串拼接，不得重新序列化
3. **坐标截断**：前端浮点坐标服务端按 int 截断
4. **水印**：绘制在抠图之前，凹槽与滑块小图都会包含水印像素
5. **AES-ECB 定位**：防篡改混淆而非机密保护；真正的安全边界是
   一次性 token + TTL + 频控（MoonCaptcha 频控默认开启）

## 5. 验证清单（迁移后）

- [ ] 现有前端组件（vue/uni-app/android…）不改代码完成一次验证
- [ ] check 后业务端 verify 通过；同一凭证二次 verify 返回 6110
- [ ] 错误坐标返回 6111；token 复用返回 6110
- [ ] 频控：同 client 第 121 次 get 返回 6201；失败 5 次后 get 锁定 6202
- [ ] 参照实现：`demo/`（Node 参考集成）、`examples/js-server`（MoonBit 引擎 HTTP 服务）
