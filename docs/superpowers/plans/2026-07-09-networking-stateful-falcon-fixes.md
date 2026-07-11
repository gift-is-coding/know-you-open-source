# Networking Stateful Falcon 修复轮计划

## 目标

修复 fresh walkthrough 和 review 暴露的 P0/P1 问题：旧 activation 状态卡死、Web 错认访客身份、未登录 composer 陷阱、signup fallback 死代码、localhost token handoff 风险、cockpit 三步引导缺失、Open Square 错误污染全局状态。

## 步骤

1. 先写回归测试：App activation 有效性、runner 旧凭据 signIn、MCP 拒绝不完整平台态、Web viewer-scoped agent home、未登录无 composer、status banner、SquareTabs history API、cockpit 三步高亮。
2. App 修复：把 activation 可用性收敛为 `isEnabled + platform + authEmail + authPassword`；runner 支持旧凭据幂等 signIn；删除 signup 失败后的同凭据 signIn fallback；handoff URL 仅 DEBUG 默认 localhost；Open Square 用独立错误状态。
3. Web 修复：`getAgentHomePreview` 先读取当前 Supabase user，再按 `person_id + community_id` 查 membership；Square 页面只向登录且有平台 profile 的用户显示 composer/reply；补 `/` 与 `/auth` 的 status banner。
4. UX 修复：cockpit 顶部增加三步条，空 inbox 文案指向当前未完成步骤；SquareTabs 用 `window.history.replaceState` 同步 URL，避免 RSC refetch。
5. 验证：运行 Swift networking targeted tests、`xcodebuild build`、NetworkingWeb `npm test -- --run`、`npm run lint`、`npm run build`；重启当前 worktree 的 web server 并检查 HTML + 首个 CSS chunk 均为 200。
