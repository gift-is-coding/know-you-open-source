# Networking Stateful Falcon Spec

## 背景

`app-networking-stateful-falcon.md` 要求把 KnowYou Networking 从“可演示的真实平台循环”推进到 App 与 Web 都能保持状态的 P0 闭环：App 负责生成/批准/同步 profile、本地 agent 权限和 Web handoff；Web 负责使用真实 Supabase session 展示 public square，并且在已有 Supabase 配置时不再回退到 fixture 数据。

## 用户结果

- 用户在 App 中批准 profile 后，平台同步结果会被持久化到 `.knowyou/networking/profile-approval.json`，重启后仍知道本地 profile 对应的服务端 profile。
- App 的 Networking community card 提供 `Open Square`，仅在已连接真实平台、profile 已批准且已同步时可用。
- `Open Square` 使用本机保存的机器账号凭证换取 Supabase session，并生成 `/auth/handoff#access_token=...&refresh_token=...&platform=...`，token 不放在 query string。
- Web `/auth/handoff` 消费 fragment、设置 Supabase session、清除 fragment，并跳转回对应 community。
- Web 首页一次加载 `knowyou-jobs` 和 `knowyou-friends` 两个 community，client-side tabs 本地切换并用 `router.replace` 同步 URL。
- Web 顶部导航是 App-first：只有 public square 入口和身份 chip，不再展示 demo profile 或 editable drafts 链接。
- `/profiles/me` 是 read-only 状态页；profile 写入只来自 App activation/profile sync。
- App 缺少真实 Supabase 配置时显示明确失败，不再写 `local.knowyou.invalid` 这类看似 ready 的假 activation。
- MCP `networking_fetch_public_square` 读取真实 public posts，`networking_record_highlight` 写入本地 cockpit inbox；`NetworkingInboxService` 合并本地 highlights 与平台 Agent Home 队列；MCP 输出不得泄漏 plaintext agent token。

## 非目标

- 不在本轮提交生产 Supabase/Vercel secrets。
- 不替用户执行真实线上部署或创建生产用户；外部凭证/部署需要单独授权。
- 不重写 profile 生成 pipeline、agent candidate ranking 或现有 E2E lab。

## 验收标准

- Swift targeted tests 覆盖机器账号 signup/sign-in、handoff URL、activation state 兼容、profile sync record、本地 inbox、MCP public fetch/highlight。
- Web contract tests 覆盖无 fixture fallback、English copy、App-first nav、read-only `/profiles/me`、client SquareTabs、handoff auth。
- `npm run build` 通过。
- 完成后运行全量 macOS build/test、启动最新构建 App，并保持 dev bundle 既有登录/onboarding 状态。
