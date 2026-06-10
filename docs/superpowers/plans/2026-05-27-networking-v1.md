# KnowYou Networking V1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 新增 Networking V1 的 Web 平台骨架、Supabase 数据契约、KnowYou 本地 cockpit 数据契约、基础 UI 和本地 agent runtime 合同。

**Architecture:** Web 平台放在 `NetworkingWeb/`，使用 Next.js App Router、Supabase SSR client 和 Vitest。KnowYou 本地侧新增 Networking 模型、presentation、WebView bridge payload 和 runtime 合同：My Wiki 语义信号生成本地 profile draft，人工批准后形成公开 profile sync payload，agent 操作只上传公开内容和公开引用，私有匹配理由只进入 cockpit bridge。

**Tech Stack:** Next.js、React、TypeScript、Supabase、Vitest、SwiftUI、WebKit、XCTest。

---

### Task 1: Web 平台测试骨架

**Files:**
- Create: `NetworkingWeb/package.json`
- Create: `NetworkingWeb/vitest.config.ts`
- Create: `NetworkingWeb/src/lib/networking/content-ordering.test.ts`
- Create: `NetworkingWeb/src/lib/networking/schema-contract.test.ts`

- [x] 写自由文本、人类优先、AI 标注和 schema contract 的失败测试。
- [x] 运行 `npm install` 后执行 `npm test -- --run`，确认测试因缺少实现失败。

### Task 2: Web 平台核心实现

**Files:**
- Create: `NetworkingWeb/src/lib/networking/types.ts`
- Create: `NetworkingWeb/src/lib/networking/content-ordering.ts`
- Create: `NetworkingWeb/src/lib/networking/fixtures.ts`
- Create: `NetworkingWeb/app/page.tsx`
- Create: `NetworkingWeb/app/profiles/[handle]/page.tsx`
- Create: `NetworkingWeb/app/auth/page.tsx`
- Create: `NetworkingWeb/src/components/*`
- Create: `NetworkingWeb/src/lib/supabase/*`

- [x] 实现 post/comment/profile 类型。
- [x] 实现人类优先排序和 AI label formatter。
- [x] 实现公开帖子广场、profile page、Magic Link 登录页和 composer shell。
- [x] 使用 Supabase SSR 当前推荐的 `@supabase/ssr` client shape。

### Task 3: Supabase migration 与 RLS

**Files:**
- Create: `NetworkingWeb/supabase/migrations/202605270001_networking_v1.sql`
- Create: `NetworkingWeb/src/lib/networking/schema-contract.ts`

- [x] migration 创建 `people`、`profiles`、`posts`、`comments`、`agent_activity`、`public_interaction_events`。
- [x] 所有 public exposed table 启用 RLS。
- [x] 公开 SELECT 只允许 published/公开内容。
- [x] INSERT/UPDATE 只允许 authenticated owner；agent 写入字段必须保留 owner person/profile。
- [x] Agent token RPC 只允许写入 AI post/comment，拒绝空内容并记录公开 agent activity。
- [x] `public_interaction_events` 只能引用公开 post/comment，避免公开事件表泄露非公开引用。

### Task 4: KnowYou 本地 cockpit 契约

**Files:**
- Create: `KnowYou/Services/Networking/NetworkingModels.swift`
- Create: `KnowYou/Services/Networking/NetworkingCockpitPresentation.swift`
- Create: `KnowYou/UI/Networking/NetworkingCockpitView.swift`
- Create: `KnowYouTests/NetworkingCockpitPresentationTests.swift`

- [x] 先写 XCTest，覆盖 profile draft 需人审、AI 署名、人类优先和 cockpit 入站/出站/highlight payload。
- [x] 实现 Swift 模型和 presentation。
- [x] 实现本地 agent runtime 合同：My Wiki 信号生成多个 draft、批准后生成 public sync payload、候选机会进入 cockpit highlight、agent action 带频率/重复保护。
- [x] 新增 SwiftUI/WebKit cockpit shell，用于当前本地 cockpit 渲染和 Web UI 复用。
- [x] 把新 Swift 文件加入 Xcode project。

### Task 5: 文档与验证

**Files:**
- Modify: `docs/architecture.md`
- Modify: `docs/requirements-spec.md`
- Modify: `README.md`

- [x] 更新架构和需求文档，记录 Networking V1 的隐私边界。
- [x] 运行 Web test/typecheck/build。
- [x] 运行 Networking focused XCTest。
- [x] 运行完整 `xcodebuild test` 和 `xcodebuild build`。
