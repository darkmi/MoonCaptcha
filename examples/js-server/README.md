# MoonCaptcha JS 目标 HTTP 服务示例

把 **MoonCaptcha MoonBit 核心**（AES、PNG 编解码、模板抠图、TTL 缓存、滑动窗口频控）
编译到 JS 目标，接入 Node HTTP 服务——宿主只做 HTTP ↔ JSON 搬运，
验证码全部逻辑跑在 MoonBit 引擎里。

```
examples/js-server/
├── moon-srv/          # MoonBit 派发层（js_captcha_init/get/check/verify）
├── build.js           # 构建：moon build --target js + 提取派发函数 → build/moonbit_lib.cjs
├── server.js          # Node HTTP 宿主
└── test-e2e.js        # 协议端到端测试
```

## 运行

```bash
# 1. 构建（需 moon 工具链；首次需先 moon bundle --target js 于 core 标准库）
node examples/js-server/build.js

# 2. 启动（可选 MOONCAPTCHA_FONT=/path/to/WenQuanZhengHei.ttf 烧录点选文字）
node examples/js-server/server.js 3300

# 3. 端到端测试
node examples/js-server/test-e2e.js
```

端点：`POST /captcha/get`、`POST /captcha/check`、`POST /captcha/verify`、`GET /health`，
协议与 AJ-Captcha 完全一致（repCode / AES-ECB pointJson / token 一次性 / 防重放）。

## 已验证

- 协议 E2E 10/10：get 双图 → 坐标容差判定（6111）→ check → verify → 防重放（6110）→ token 一次性
- 频控：同一 client 第 121 次 get 返回 6201（滑动窗口，由 MoonBit 引擎内部执行）

## 实现说明

- **导出机制**：moonc 生成 JS 时会 tree-shake 未从 `main` 可达的函数；
  `moon-srv/server.mbt` 的 `main` 预热调用各派发函数保证入口可达，
  `build.js` 按确定性 mangling 名（`_M0` 前缀、下划线翻倍）提取并拼接
  `module.exports`（构建期自动完成）。
- **全局状态**：进程内单例（内存缓存 + 内存频控）。分布式部署时实现
  `Cache` trait 接入共享存储（如 Redis），MoonBit 侧接口不变。
- **clickWord 文字烧录**：通过 `MOONCAPTCHA_FONT` 提供 TTF（如 AJ-Captcha
  的 WenQuanZhengHei.ttf，Apache-2.0）后由 MoonBit 字体光栅化烧录；
  未提供时不烧录（仅协议可用）。
- **合成底图**：示例用程序化渐变图免资源文件开箱即用；生产用
  `tools/gen-assets.js` 嵌入真实底图。
