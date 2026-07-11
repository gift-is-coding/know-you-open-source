# Networking Destination Visual Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** 将 Careers 重构为可信、高密度的职业社交界面，将 Friends 重构为明亮、卡通、人物发现优先的 Gen Z 社交界面，同时完整保留现有身份、发帖、回复、Agent Home、隐私和 App handoff 能力。

**Architecture:** 保留 `PublicSquarePage` 一次加载两个 destination 的 SSR 数据模型和 `SquareTabs` 的 History API 切换。页面层根据 scenario 渲染两个独立 layout component，共享经过约束的 identity、composer、thread 和 Agent Home primitives；视觉差异由明确的 Careers/Friends class 与 design tokens 驱动，不增加虚假后端功能。

**Tech Stack:** Next.js 16 App Router、React 19、TypeScript、Supabase SSR、CSS、Vitest、Playwright、Cloudflare OpenNext。

---

### Task 1: 固定双目的地结构契约

**Files:**
- Modify: `NetworkingWeb/src/lib/networking/web-copy-contract.test.ts`
- Modify: `NetworkingWeb/tests/e2e/networking-destinations.spec.ts`

- [x] **Step 1: 写失败的结构测试**

在 contract test 中断言 `page.tsx` 包含 `CareersSquare`、`FriendsSquare`、`DestinationHeader`、`PeopleDiscovery`，且不包含未实现的 Photo、Poll、Voice、Stories、RSVP 控件。

- [x] **Step 2: 验证 RED**

Run: `cd NetworkingWeb && npm test -- --run src/lib/networking/web-copy-contract.test.ts`

Expected: FAIL，提示目标组件尚不存在。

- [x] **Step 3: 扩展 Playwright 断言**

为 Careers 添加 `data-layout="professional-network"`，为 Friends 添加 `data-layout="people-discovery"`；断言 Friends 有人物发现区，Careers 有职业 identity rail，且两边均保留 composer/feed。

- [x] **Step 4: 验证 E2E RED**

Run: `cd NetworkingWeb && npm run e2e:destinations`

Expected: FAIL，提示新 layout marker 或 discovery region 不存在。

### Task 2: 拆分目的地页面结构

**Files:**
- Modify: `NetworkingWeb/app/page.tsx`
- Test: `NetworkingWeb/src/lib/networking/web-copy-contract.test.ts`
- Test: `NetworkingWeb/tests/e2e/networking-destinations.spec.ts`

- [x] **Step 1: 引入共享 destination view model**

保持 `loadPlatformSquareData` 返回值不变，增加 `DestinationSquareProps` 类型；将当前 `SquarePanel` 拆为 `CareersSquare` 与 `FriendsSquare`，两者继续调用共享 `Composer`、`PostThread`、`AgentHomePanel` 和 guidance components。

- [x] **Step 2: 实现 Careers 三栏结构**

输出 `data-layout="professional-network"`，顺序为职业 identity rail、中心 composer/feed、右侧 Agent Home/privacy rail。所有指标仅使用现有 profile、post 和 queue 数据。

- [x] **Step 3: 实现 Friends 混合结构**

输出 `data-layout="people-discovery"`，使用公开 feed 中去重后的 person/profile 构造 `PeopleDiscovery`；随后显示 Friends composer、动态/活动式 feed 和 Agent Home/privacy rail。不推断年龄、距离、匹配分数。

- [x] **Step 4: 验证 GREEN**

Run: `cd NetworkingWeb && npm test -- --run src/lib/networking/web-copy-contract.test.ts && npm run e2e:destinations`

Expected: contract 与 3 个 destination E2E 全部 PASS。

### Task 3: 重建共享导航与 destination switcher

**Files:**
- Modify: `NetworkingWeb/src/components/SquareTabs.tsx`
- Modify: `NetworkingWeb/app/layout.tsx`
- Modify: `NetworkingWeb/app/globals.css`
- Test: `NetworkingWeb/src/lib/networking/square-tabs-contract.test.tsx`
- Test: `NetworkingWeb/tests/e2e/networking-destinations.spec.ts`

- [x] **Step 1: 写失败的导航契约**

断言 switcher 保留真实 `<a>`、History API、announcement 与 heading focus，并暴露当前 destination 的 `data-active-platform`；layout header 不显示虚假的聊天/连接入口。

- [x] **Step 2: 验证 RED**

Run: `cd NetworkingWeb && npm test -- --run src/lib/networking/square-tabs-contract.test.tsx`

Expected: FAIL，缺少 active destination contract。

- [x] **Step 3: 实现共享 destination header**

使用 KnowYou cube、产品名、Careers/Friends switcher、公开 Square 状态和真实 IdentityChip。切换继续无整页刷新，主 heading 在切换后 focus。

- [x] **Step 4: 验证 GREEN**

Run: `cd NetworkingWeb && npm test -- --run src/lib/networking/square-tabs-contract.test.tsx && npm run e2e:destinations`

Expected: PASS。

### Task 4: 实现 Careers 视觉系统

**Files:**
- Modify: `NetworkingWeb/app/globals.css`
- Modify: `NetworkingWeb/app/page.tsx`
- Test: `NetworkingWeb/src/lib/networking/web-copy-contract.test.ts`
- Test: `NetworkingWeb/tests/e2e/networking-destinations.spec.ts`

- [x] **Step 1: 写失败的 Careers token/structure 断言**

断言存在职业蓝、冷灰、charcoal tokens，`career-identity-rail`、`career-feed-column`、`career-agent-rail` 和 compact composer classes。

- [x] **Step 2: 验证 RED**

Run: `cd NetworkingWeb && npm test -- --run src/lib/networking/web-copy-contract.test.ts`

Expected: FAIL。

- [x] **Step 3: 实现职业网络样式**

桌面使用稳定三栏、1px 边框、6px 圆角、紧凑 sans-serif 与职业蓝；移动端变为 identity strip → composer/feed → Agent/Privacy sections。删除现有大 hero 视觉占比。

- [x] **Step 4: 验证 GREEN**

Run: `cd NetworkingWeb && npm test -- --run src/lib/networking/web-copy-contract.test.ts && npm run e2e:destinations`

Expected: PASS，移动端无横向溢出。

### Task 5: 实现 Friends 视觉系统

**Files:**
- Modify: `NetworkingWeb/app/globals.css`
- Modify: `NetworkingWeb/app/page.tsx`
- Test: `NetworkingWeb/src/lib/networking/web-copy-contract.test.ts`
- Test: `NetworkingWeb/tests/e2e/networking-destinations.spec.ts`

- [x] **Step 1: 写失败的 Friends token/structure 断言**

断言存在 bright yellow、cyan、coral、lime tokens，`friends-discovery`、`vibe-person`、`friends-composer`、`friends-feed-column` 和 privacy classes。

- [x] **Step 2: 验证 RED**

Run: `cd NetworkingWeb && npm test -- --run src/lib/networking/web-copy-contract.test.ts`

Expected: FAIL。

- [x] **Step 3: 实现 Gen Z 样式**

人物发现带使用确定性 profile avatar 与公开 label；composer 与 feed 使用明亮边框、圆润粗体、彩色兴趣标签和轻量活动语气。所有点击控件必须对应现有真实功能。

- [x] **Step 4: 实现 reduced motion 与移动端**

人物带仅自身横向滚动；页面不横向溢出。`prefers-reduced-motion` 禁止 destination transition，颜色对比满足正文可读。

- [x] **Step 5: 验证 GREEN**

Run: `cd NetworkingWeb && npm test -- --run src/lib/networking/web-copy-contract.test.ts && npm run e2e:destinations`

Expected: PASS。

### Task 6: 完整验证、GUI review 与发布

**Files:**
- Modify when findings require: `NetworkingWeb/app/page.tsx`
- Modify when findings require: `NetworkingWeb/app/globals.css`
- Modify when findings require: `NetworkingWeb/src/components/SquareTabs.tsx`

- [x] **Step 1: 运行完整 Web verification**

Run: `cd NetworkingWeb && npm test -- --run && npm run lint && npm run typecheck && npm run e2e:destinations && npm run build && npm audit --audit-level=high`

Expected: 全部 PASS，audit 0 high/critical vulnerabilities。

- [x] **Step 2: GUI 检查**

通过浏览器检查 Careers/Friends 桌面与移动视口：页面非空、视觉显著不同、文字不重叠、无整页横向滚动、switch focus 正确、真实登录身份与 composer gate 正确。

- [x] **Step 3: Claude review**

使用本地 Claude CLI review 当前 diff，要求从代码、Careers UX、Friends UX、响应式、可访问性与生产连通性报告 P0/P1/P2。逐项验证并修复，重复 review 直到 `NO P0/P1/P2`。

- [x] **Step 4: 发布并验证线上**

Run: `cd NetworkingWeb && npm run deploy:cloudflare`

验证 `networking.giiift.site` HTML 与首个 CSS 200；`GET /api/e2e/networking/state` 与 `POST /api/e2e/networking/reset` 404；App handoff 登录身份和既有真实 post 仍可见。

- [x] **Step 5: 提交但不 push**

Run: `git add <本计划涉及文件> && git commit -m "feat: redesign networking destinations"`

Expected: worktree 仅保留用户原有的无关未跟踪文件，不 push。
