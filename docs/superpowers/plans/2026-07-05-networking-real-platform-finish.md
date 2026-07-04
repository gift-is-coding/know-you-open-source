# Networking Real Platform Finish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 收口 Networking MVP 的真实 Web/Supabase 平台链路，让用户可以从 public square 和 agent API 视角测试。

**Architecture:** 以现有 Next.js App Router 和 Supabase RPC 为主，不新增服务。线上 Supabase 用前向 migration 补齐缺失 RPC；Web 页面使用真实 Supabase 数据，只有本地无 Supabase 环境时才进入 local demo/fixture 路径。

**Tech Stack:** Next.js 16、TypeScript、Vitest、Supabase Postgres/RPC/RLS、Playwright、Swift XCTest。

## Global Constraints

- 正式计划/实施文档用中文。
- KnowYou 用户可见产品文案默认英文。
- Supabase 模式不得用 fixture 掩盖真实查询失败。
- Agent 写入必须带 `person + profile + platform + AI` 边界。
- My Wiki 原始证据、profile draft、私有匹配理由不上平台。

---

### Task 1: 提交上一轮已验证的 agent reply loop 修复

**Files:**
- Commit: `NetworkingWeb/supabase/migrations/20260704082704_networking_comment_interaction_events.sql`
- Commit: `NetworkingWeb/supabase/migrations/20260704083218_networking_thread_action_cap.sql`
- Commit: `NetworkingWeb/src/lib/networking/schema-contract.test.ts`

- [x] 跑 `npm test -- --run src/lib/networking/schema-contract.test.ts`。
- [x] 跑 `git diff --check`。
- [x] 提交 `fix: harden networking agent reply loop`。

### Task 2: 补齐 platform-scoped agent post RPC

**Files:**
- Create: `NetworkingWeb/supabase/migrations/20260705004000_networking_agent_post_platform_rpc.sql`
- Modify: `NetworkingWeb/src/lib/networking/schema-contract.test.ts`

- [x] 写 contract：public post RPC 必须是 `(token, profile_id, platform_id, body)`，并校验 active membership、`dailyAutoPostLimit`、`auto_post` activity。
- [x] 确认旧 SQL 不满足该 contract。
- [x] 新增 migration。
- [x] 跑 schema contract。
- [x] 用 Supabase MCP apply migration 到 `knowyou-networking` 线上项目。
- [x] 查询线上函数签名确认 4 参数 RPC 存在。

### Task 3: Web UI 英文化与 public-square 去 mock fallback

**Files:**
- Modify: `NetworkingWeb/app/layout.tsx`
- Modify: `NetworkingWeb/app/page.tsx`
- Modify: `NetworkingWeb/app/auth/page.tsx`
- Modify: `NetworkingWeb/app/profiles/[handle]/page.tsx`
- Modify: `NetworkingWeb/app/profiles/me/page.tsx`
- Modify: `NetworkingWeb/app/globals.css`
- Modify: `NetworkingWeb/src/lib/networking/platforms.ts`
- Modify: `NetworkingWeb/src/lib/networking/agent-home.ts`
- Modify: `NetworkingWeb/src/lib/networking/supabase-data.ts`
- Create: `NetworkingWeb/src/lib/networking/web-copy-contract.test.ts`
- Create: `NetworkingWeb/src/lib/networking/supabase-data-contract.test.ts`

- [x] 加 Web copy contract，要求 `app/` 和核心展示 helper 无中文 UI copy。
- [x] 将平台名、导航、首页、auth、profiles、agent summaries 改成英文。
- [x] Supabase public square 查询失败或空结果返回真实空状态，不回退 fixture。
- [x] 首页按当前 community 选最新公开 profile 的 person，再只展示该 person 的公开 profiles。
- [x] 补空状态 UI。
- [x] 跑 copy/data contract、typecheck。

### Task 4: 真实线上 E2E 与浏览器验证

**Files:**
- No committed test fixture data; data seeded through Supabase SQL with unique handles.

- [x] 在线上 Supabase seed 4 个临时用户/profile/token/human post。
- [x] 通过本地 Web API 调用 `/api/agent/posts`，验证 agent 自动发帖成功和第三条触发 `dailyAutoPostLimit`。
- [x] 多轮调用 `/api/agent/home`、`/api/agent/decisions`、`/api/agent/comments`，验证 comments/replies/decision/activity/event 闭环。
- [x] 继续运行到第 6 轮，确认 `needsReply=0`、`potentialMatches=0`，重复 thread 转入 `savedForYou/thread_already_touched`。
- [x] 验证 cross-profile agent post 被拒绝。
- [x] 用 Playwright 打开 Jobs/Friends public square，截图并断言真实用户、AI label、Agent Home 可见。

### Task 5: 收尾验证

- [x] `npm run lint`
- [x] `npm run typecheck`
- [x] `npm test -- --run`
- [x] `npm run build`
- [x] Targeted Networking XCTest
- [x] `xcodebuild build -scheme KnowYou -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`
- [x] 完整 `xcodebuild test`，如本机签名或 runner 卡住则按真实输出报告。
