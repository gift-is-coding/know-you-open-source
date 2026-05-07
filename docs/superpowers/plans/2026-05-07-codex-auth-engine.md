# Codex Auth Engine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 新增一个与现有 diary engines 平行的 `Codex Auth` engine，复用本机 Codex CLI 登录态并直连 Codex backend。

**Architecture:** 新功能拆成 `CodexJWT`、`CodexAuthStore`、`CodexOAuthRefresher`、`CodexDirectSummarizer` 四个小组件；`DiaryEngine`、`SummarizerConfig`、`EngineProbe`、Settings UI 只接入新 engine，不把 token 存到 KnowYou 自己的设置。网络请求使用 `URLSession` 和 SSE 文本解析，Keychain 通过现有 `KeychainStoring` 抽象测试。

**Tech Stack:** Swift, XCTest, URLSession, Security Keychain, CryptoKit SHA256, Xcode project `KnowYou.xcodeproj`

---

### 文件结构

- Create: `KnowYou/Services/Summary/CodexJWT.swift`
  - 解析 JWT payload 的 `exp` 与 `https://api.openai.com/auth.chatgpt_account_id`。
- Create: `KnowYou/Services/Summary/CodexAuthStore.swift`
  - 解析 Codex home、计算 Keychain account、从 Keychain/auth.json 读取并构造 credential、构造刷新后的 auth record。
- Create: `KnowYou/Services/Summary/CodexOAuthRefresher.swift`
  - 发送 OAuth refresh 请求，解析响应并调用 store 写回。
- Create: `KnowYou/Services/Summary/CodexDirectSummarizer.swift`
  - 使用有效 credential 请求 `https://chatgpt.com/backend-api/codex/responses`，解析 SSE 文本。
- Create: `KnowYouTests/CodexJWTTests.swift`
- Create: `KnowYouTests/CodexAuthStoreTests.swift`
- Create: `KnowYouTests/CodexOAuthRefresherTests.swift`
- Create: `KnowYouTests/CodexDirectSummarizerTests.swift`
- Modify: `KnowYou/Services/Summary/DiaryEngine.swift`
- Modify: `KnowYou/Services/Summary/SummarizerConfig.swift`
- Modify: `KnowYou/Services/Summary/EngineProbe.swift`
- Modify: `KnowYou/UI/Settings/EngineConfigurationSection.swift`
- Modify: `KnowYou/UI/Reader/DiaryEnginePanel.swift`
- Modify: `KnowYouTests/SummarizerConfigTests.swift`
- Modify: `KnowYouTests/EngineProbeTests.swift`
- Modify: `KnowYou.xcodeproj/project.pbxproj`
- Modify: `docs/architecture.md`
- Modify: `docs/requirements-spec.md`
- Modify: `PRIVACY.md`

### Task 1: JWT 与 Auth Store

- [ ] 写 `CodexJWTTests`，覆盖 `exp`、`chatgpt_account_id`、malformed token。
- [ ] 运行 `xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/CodexJWTTests`，确认因为类型不存在失败。
- [ ] 实现 `CodexJWT.swift`。
- [ ] 写 `CodexAuthStoreTests`，覆盖 Keychain account、Keychain 优先、auth file fallback、malformed auth record、刷新 record 保留字段。
- [ ] 运行 `xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/CodexAuthStoreTests`，确认因为类型不存在或行为缺失失败。
- [ ] 实现 `CodexAuthStore.swift`。
- [ ] 将新生产文件和测试文件加入 `KnowYou.xcodeproj/project.pbxproj`。
- [ ] 运行 Task 1 两组测试，确认通过。

### Task 2: OAuth Refresh

- [ ] 写 `CodexOAuthRefresherTests`，使用 `URLProtocol` stub 验证 form body、响应解析、缺字段失败、错误不暴露 token。
- [ ] 运行 `xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/CodexOAuthRefresherTests`，确认因为类型不存在失败。
- [ ] 实现 `CodexOAuthRefresher.swift`，refresh 成功后通过 store 写回同来源。
- [ ] 将新文件加入 `project.pbxproj`。
- [ ] 运行 Task 2 测试，确认通过。

### Task 3: Codex Direct Summarizer

- [ ] 写 `CodexDirectSummarizerTests`，使用 stub auth provider 与 `URLProtocol` stub 验证 URL/header/body、SSE completion 解析、空响应失败。
- [ ] 运行 `xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/CodexDirectSummarizerTests`，确认因为类型不存在失败。
- [ ] 实现 `CodexDirectSummarizer.swift`，同时支持 full 和 incremental prompt 输入。
- [ ] 将新文件加入 `project.pbxproj`。
- [ ] 运行 Task 3 测试，确认通过。

### Task 4: Engine 接入

- [ ] 扩展 `DiaryEngine`，新增 `.codexAuth` 的 display name 与说明。
- [ ] 更新 `SummarizerConfigTests`，覆盖 `.codexAuth` round-trip 与 factory 返回 `CodexDirectSummarizer`。
- [ ] 更新 `SummarizerConfig.makeSummarizer(for:)`，为 `.codexAuth` 返回新 summarizer。
- [ ] 更新 `EngineProbeTests`，覆盖缺 auth 灰色、refresh/backend 失败黄色、smoke test 成功绿色。
- [ ] 更新 `EngineProbe`，新增 `.codexAuth` 分支。
- [ ] 更新 `EngineConfigurationSection` 和 `DiaryEnginePanel`，让 `Codex Auth` 像独立 engine 一样显示、测试、选择。
- [ ] 运行 `xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/SummarizerConfigTests -only-testing:KnowYouTests/EngineProbeTests`。

### Task 5: 文档与全量验证

- [ ] 更新 `docs/architecture.md`、`docs/requirements-spec.md`、`PRIVACY.md`。
- [ ] 运行 focused tests：
  - `xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/CodexJWTTests -only-testing:KnowYouTests/CodexAuthStoreTests -only-testing:KnowYouTests/CodexOAuthRefresherTests -only-testing:KnowYouTests/CodexDirectSummarizerTests -only-testing:KnowYouTests/SummarizerConfigTests -only-testing:KnowYouTests/EngineProbeTests`
- [ ] 运行完整测试：
  - `xcodebuild test -scheme KnowYou -destination 'platform=macOS'`
- [ ] 运行完整 build：
  - `xcodebuild build -scheme KnowYou -destination 'platform=macOS'`
- [ ] 检查 `git diff`，确认没有 token、account id、真实 auth record 或无关改动。

### Self-Review

- Spec 覆盖：JWT、auth discovery、refresh、backend request、engine probe、UI、文档和测试均有任务覆盖。
- 占位扫描：计划中没有 `TBD`、`TODO`、`implement later`。
- 类型一致性：统一使用 `.codexAuth`、`CodexAuthStore`、`CodexOAuthRefresher`、`CodexDirectSummarizer`、`CodexJWT`。
