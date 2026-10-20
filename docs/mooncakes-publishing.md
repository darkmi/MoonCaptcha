# mooncakes.io 发布方案

> mooncakes.io 是 MoonBit 官方包注册表（类似 npm/crates.io）。本文是 MoonCaptcha
> 作为第三方类库发布到 mooncakes 的完整方案。发布相关的账号操作需要仓库所有者
> 人工完成，其余步骤已尽可能落地为可执行命令。

## 1. 前置决策（需要所有者确认）

### 1.1 模块名与 mooncakes 用户名（✅ 已决策：darkmi/mooncaptcha）

mooncakes 的模块名格式为 `<用户名>/<包名>`，第一段必须与 mooncakes 账号用户名一致。
已采用方案 B：模块更名为 `darkmi/mooncaptcha`（2026-10-13 完成全仓改名，
29 处引用更新，88/88 测试与 js-server E2E 回归通过）。
仅需在 mooncakes.io 注册用户名 `darkmi`。

### 1.2 首发版本

当前 `version = "0.1.0"`。建议首发即用 `0.1.0`（已有完整功能与测试支撑）；
0.x 阶段允许 minor 版本含破坏性变更（与 semver 的 0.x 惯例一致），1.0 起严格化。

## 2. 账号与认证（人工，一次性）

```bash
moon login        # 浏览器跳转 mooncakes.io 完成登录授权
                  # 无浏览器环境可用 API Token 方式（mooncakes.io 个人设置页生成）
```

## 3. 发布前检查清单

已完成 ✅：

- [x] `moon.mod` 补齐 `license = "MIT"`、`readme = "README.md"`、`repository` 字段
- [x] `.mbti` 接口文件入库（`moon info` 产物，公开 API 面可 review；
      CI 检查接口漂移：`.github/workflows/ci.yml` 的 `moon info` +
      `git diff --exit-code -- '*.mbti'`）。当前基线工具链
      **`moon 0.1.20261016`**——`moon.mod` 无法锁定版本，工具链升级会改写
      类型打印名（如 `Int` → `Int32`，二者为同一类型的别名，语义不变），
      届时需重新生成并一并提交，否则 CI 漂移检查会失败
- [x] `.gitattributes`：换行统一 LF（`eol=lf` 优先于本地 `core.autocrlf`），
      显式标记 PNG 等二进制资源为 `binary`，消除交叉检出产生的整文件 diff 噪音
- [x] 公开 API doc comment 覆盖（六个包核心类型/函数均有中文文档注释）
- [x] 多目标测试：wasm 88/88、js 88/88（native 依赖 CI 的 ubuntu 环境）
- [x] LICENSE（MIT）

待完成：

- [ ] CHANGELOG.md（从 0.1.0 起维护，条目可直接取自各里程碑提交说明）
- [ ] 三目标 CI 全绿（见 `.github/workflows/ci.yml`，native 需在 CI 验证）
- [ ] 打包范围确认：`moon package --list` 当前包含 `demo/`、`examples/`、`docs/`、
      `tools/`——其中 `demo/assets` 含 AJ-Captcha（Apache-2.0）底图。moon.mod
      暂不支持 exclude；两种处理：(a) 接受打包（Apache-2.0 声明已随包，
      见 demo/README.md）；(b) 发布前临时移出（脚本化）。建议 (a)。

## 4. 发布流程

```bash
# 1) 预检：本地全目标测试 + 打包审查
moon test                                    # wasm 默认目标
moon test --target js
moon package --list                          # 审查发布内容清单
moon package                                 # 生成 _build/publish/*.zip 可人工复查

# 2) 版本号：编辑 moon.mod 的 version（必须大于已发布版本）

# 3) 发布
moon publish                                 # 推送到 mooncakes.io
```

发布后 mooncakes.io 自动基于 doc comment 生成 API 文档页面。

## 5. 自动化发布（建议，M6 收尾项）

GitHub Actions release 工作流：推送 `v*` tag 时执行三目标测试 → `moon publish`。
认证用 mooncakes API Token 存入仓库 Secrets（如 `MOONCAKES_TOKEN`，具体
env 名称以 `moon login` 的非交互模式文档为准——首次人工发布时确认）。

## 6. 发布后的依赖使用方式

下游项目：

```
# moon.mod
name = "example/app"
deps = { "darkmi/mooncaptcha" = "0.1.0" }
```

```bash
moon update    # 拉取 registry 依赖
```

```moonbit
// 使用门面（推荐）
let pool = @image.ImagePool::new()
// …注册底图/字体
let svc = @service.CaptchaService::new(pool)
let resp = svc.get(cache, @service.BlockPuzzle, client_id="…")
```

## 7. 开放项 / 风险

| 项 | 状态 |
| --- | --- |
| mooncakes 用户名归属（§1.1） | ✅ 已决策：darkmi（仅需注册账号） |
| native 目标测试 | 本机无 C 工具链，待 CI ubuntu 验证 |
| 打包范围控制（exclude） | moon.mod 暂不支持；接受打包 + Apache-2.0 声明随包 |
| 发布自动化（release workflow） | 首次人工发布成功后补建 |
