# Networking Stateful Falcon Plan

## 计划

1. 验证 worktree、分支和现有计划
   - 确认开发只发生在 `.worktrees/networking-main-sync`。
   - 阅读 `/Users/wutianfu/.claude/plans/app-networking-stateful-falcon.md`，把 P0 拆成 Swift/App、Web、docs、verification。

2. 先写失败测试
   - Swift：机器账号 auth、handoff URL、activation/profile sync 持久化、MCP public square/highlight。
   - Web：无 Supabase fixture fallback、App-first nav、read-only `/profiles/me`、client SquareTabs、handoff session。

3. 实现 Swift/App P0
   - 增加 `NetworkingBackendConfiguration` 与 `NetworkingWebHandoffURLBuilder`。
   - activation runner 使用机器账号 signup/password sign-in，activation state 保存本地凭证和 refresh token。
   - approval state 保存 local profile 到 server profile 的 sync record。
   - MCP 真实读取 public posts，并把 highlight 写入本地 inbox state。
   - Cockpit 缺少平台配置时明确失败，不写假 local activation；通过 `NetworkingInboxService` 合并本地 inbox 与 Agent Home，并提供 gated `Open Square`。

4. 实现 Web P0
   - Layout 使用 `IdentityChip`，删除 demo profile/editable drafts nav。
   - `/auth/handoff` 从 fragment 设置 Supabase session 并清理 URL。
   - `/profiles/me` 改为 read-only 状态页。
   - 首页一次加载 jobs/friends，`SquareTabs` 在客户端切换 panel。

5. 更新文档
   - 新增本 spec/plan。
   - 更新 `docs/architecture.md` 与 `docs/requirements-spec.md` 中 Networking activation、MCP、Web handoff 和 fixture 行为。

6. 验证与 review
   - 跑 Swift targeted tests、Web contract tests、Next build。
   - 跑全量 `xcodebuild test` 与 `xcodebuild build`。
   - 启动最新 DerivedData `KnowYou.app`，打开 Web 和本地 App 给用户看。
   - 调用 Claude review，按发现修复或记录剩余 blocker。
