# MoonCaptcha 行为验证码演示（Web 登录页）

基于 Web 的登录测试页面，演示两种行为验证码：**滑动拼图（blockPuzzle）** 与 **文字点选（clickWord）**。

```
demo/
├── server.js          # Node.js HTTP 服务（零外部依赖，Node ≥ 18）
├── lib/
│   ├── png.js         # 极简 PNG 编解码器（Node 内置 zlib 实现）
│   └── captcha.js     # 两种验证码的 get / check / verify 协议实现
├── public/
│   ├── index.html     # 登录页
│   ├── app.js         # 验证码组件与登录逻辑
│   ├── aes.js         # 浏览器端 AES-128/ECB/PKCS7（WebCrypto 不支持 ECB）
│   └── style.css
└── assets/            # 底图与模板（复制自 AJ-Captcha，Apache-2.0）
    ├── backgrounds/   # 滑动拼图底图 310×155
    ├── sliders/       # 滑块模板 94×310（透明画布）
    └── click/         # 点选底图 310×155
```

## 运行

```bash
node demo/server.js
# → http://localhost:3000（可用 PORT 环境变量覆盖）
```

打开页面后：选择验证模式 → 完成验证（拖动滑块 / 按顺序点击文字）→ 输入任意用户名密码 → 登录。右侧协议日志实时展示 `get / check / verify` 的请求与 `repCode` 应答。

## 演示的协议要点（与 AJ-Captcha 字节级兼容）

| 环节 | 行为 |
| --- | --- |
| `POST /captcha/get` | 服务端随机底图 + 抠图（blockPuzzle）或分列布点（clickWord），坐标存缓存（TTL 120s），返回 `token` 与 `secretKey` |
| `POST /captcha/check` | token **一次性**；前端提交 `AES-ECB(pointJson)`；滑动容差 `|Δx|≤5` 且 **y 严格相等**；点选逐点容差 ±25px；通过后生成二次校验凭证（TTL 180s） |
| `POST /login` → `verify` | 业务侧二次校验，凭证取出即失效（**防重放**，重放返回 6110） |
| `captchaVerification` | 由**前端本地**构造 `AES(token + "---" + pointJson)`（依赖 ECB 确定性，与 AJ-Captcha 前端行为一致） |

## 已验证

- 协议端到端测试（`.tmp_e2e.js`，14 项）：容差边界、token 复用、错误密钥、凭证重放、点选顺序/数量/偏移全部符合预期
- 浏览器真实输入实测：拖拽滑块一次到位通过；点选按序点击通过；登录二次校验通过

## 与真实实现的差异（演示简化）

- **`wordPositions` 演示专用字段**：真实系统把文字烧录进图片，不回传坐标；演示中前端用 DOM 渲染文字，坐标随 get 响应下发（仅供本地演示）
- 底图输出 PNG（AJ-Captcha 为 JPG，体积更小）；未加水印、未实现干扰块与频控
- 服务端为 Node 参考实现；生产形态是 MoonBit 核心编译到 WASM/Native（见 `docs/migration-design.md` 里程碑 M4），两者协议语义一致

## 资源版权

`demo/assets/` 下的底图与模板复制自 [AJ-Captcha](https://gitee.com/belief-team/captcha)（Apache-2.0），仅作演示用途。
