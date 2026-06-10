# Networking App-first Agent Platform Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 Networking 改成 App 一键开启、My Wiki/LLM profile-first、两个 KnowYou 平台、MCP agent 可发帖评论的真实 V1 链路。

**Architecture:** Swift 侧增加 profile generation、activation、MCP 和 presentation contract；Web/Supabase 增加 platform-aware schema 和 UI。所有私有 My Wiki 证据留本地，公开平台只保存已确认 summary 和公开互动。

**Tech Stack:** SwiftUI, XCTest, local JSON/MCP command, Next.js App Router, Vitest, Supabase Auth/RLS/RPC.

---

### Task 1: 文档和测试基线

**Files:**
- Create: `docs/superpowers/specs/2026-05-28-networking-app-first-agent-platform.md`
- Create: `docs/superpowers/plans/2026-05-28-networking-app-first-agent-platform.md`
- Modify: `KnowYouTests/DailyMarkdownViewTests.swift`
- Modify: `KnowYouTests/NetworkingCockpitPresentationTests.swift`
- Modify: `NetworkingWeb/src/lib/networking/*.test.ts`

- [ ] 写 sidebar root selection 失败测试，证明 Networking/My Wiki 不再靠 `nil` selection。
- [ ] 写 profile generation 失败测试，证明 My Wiki context + LLM output 才能生成 draft，失败时不伪造成功 profile。
- [ ] 写 MCP 失败测试，证明未开启时 publish tool 返回 permission required，开启后 payload 含 platform/profile/AI。
- [ ] 写 Web 失败测试，证明只有两个 platform tab，profile 页面展示同人多面头像。
- [ ] 写 Supabase contract 失败测试，证明 migration 带 platform fields、anonymous owner 语义和 platform-aware agent RPC。

### Task 2: Swift 数据与服务

**Files:**
- Modify: `KnowYou/Services/Networking/NetworkingModels.swift`
- Create: `KnowYou/Services/Networking/NetworkingProfileGenerationService.swift`
- Create: `KnowYou/Services/Networking/NetworkingActivationService.swift`
- Create: `KnowYou/Services/Networking/NetworkingMCPCommand.swift`
- Modify: `KnowYou/KnowYouApp.swift`

- [ ] 增加 platform definitions、profile scenario、avatar seed/style、generation status、activation status。
- [ ] 实现 My Wiki context pack + LLM profile generator 的 draft 生成服务。
- [ ] 实现 activation contract：anonymous identity、person/profile sync payload、agent token storage payload。
- [ ] 实现 `--networking-mcp` JSON-line MCP command 和四个 networking tools。

### Task 3: SwiftUI 页面和侧边栏

**Files:**
- Modify: `KnowYou/UI/Sidebar/DateSidebarView.swift`
- Modify: `KnowYou/UI/MainWindowView.swift`
- Modify: `KnowYou/UI/Networking/NetworkingCockpitView.swift`

- [ ] 统一 root item selection/highlight，将 My Wiki 放入同一 root list。
- [ ] Networking 顶部改成水平头像 profile strip。
- [ ] 平台区域只显示 `Know You 求职` 和 `Know You 认识新朋友`。
- [ ] 底部显示按 platform 来源归类的消息和 agent activity。

### Task 4: Supabase 和 Web

**Files:**
- Create: `NetworkingWeb/supabase/migrations/*_networking_app_first_platforms.sql`
- Modify: `NetworkingWeb/src/lib/networking/types.ts`
- Modify: `NetworkingWeb/src/lib/networking/fixtures.ts`
- Modify: `NetworkingWeb/src/lib/networking/supabase-data.ts`
- Modify: `NetworkingWeb/app/page.tsx`
- Modify: `NetworkingWeb/app/profiles/[handle]/page.tsx`
- Modify: `NetworkingWeb/app/actions.ts`
- Modify: `NetworkingWeb/app/globals.css`

- [ ] 新 migration 给 profile/content/activity/event 增加 platform/scenario/avatar 字段，并更新 agent RPC。
- [ ] Web data layer 映射 platform fields，fixture 只保留两个平台。
- [ ] Web 首页改为两个 platform tab + public square。
- [ ] Profile 页面展示同一 person 的多个 profile face 和对应平台/场景。

### Task 5: 验证与提交

**Files:**
- Modify: `docs/architecture.md`
- Modify: `docs/requirements-spec.md`

- [ ] 更新架构和需求文档。
- [ ] 运行 Web lint/typecheck/test/build。
- [ ] 运行 targeted XCTest。
- [ ] 运行完整 `xcodebuild test` 和 `xcodebuild build`。
- [ ] 打开本地 app 和 NetworkingWeb 做 smoke。
- [ ] 复核 `git diff` 后提交。
