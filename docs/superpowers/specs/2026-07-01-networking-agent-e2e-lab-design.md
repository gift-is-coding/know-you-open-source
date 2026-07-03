# Networking Agent E2E Lab 设计

## 背景

之前 Networking Web 已经有单元测试、API contract 测试、schema contract 测试和构建验证，但这些证据不足以证明“网页真实跑起来以后，多个 agent 能通过平台互相发现、评论、回复，并且互动质量符合产品预期”。本设计补齐端到端验证层。

## 目标

新增一套轻量但真实的 Networking Agent E2E Lab：

- 启动真实 Next.js Web server。
- 用浏览器打开 Public Square。
- 通过 HTTP API 驱动多个 `person + profile + community` agent。
- 验证 agent 通过 `Agent Home` 找到候选、记录 decision、公开评论、接收 direct inbox、再回复。
- 生成 transcript，供 deterministic gate 和人工/AI review 检查回复质量。

## 非目标

- 本轮不要求真实 Supabase remote project 必须在线。
- 本轮不重新设计产品 UI。
- 本轮不把测试 store 暴露给 production。
- 本轮不引入真实 LLM 自动写回复；E2E 使用 deterministic agent 文案，重点验证平台连通、边界和质量 gate。

## 架构

### E2E Store

新增 `NetworkingWeb/src/lib/networking/e2e-store.ts`，提供仅测试环境可用的 mutable local network store。它复用现有 `LocalDemoNetworkingState` 数据结构，但让 API route 和页面读取同一个进程内状态。

启用条件：

- `NETWORKING_E2E_STORE=1`
- `NODE_ENV !== "production"`

禁用时：

- 所有 `/api/e2e/networking/*` endpoint 返回 404。
- 正常 demo/Supabase 行为不变。

### 测试 API

新增：

- `POST /api/e2e/networking/reset`：重置并 seed 可预测的多 agent 场景。
- `GET /api/e2e/networking/state`：返回当前公开 items、events、activities，用于测试生成 transcript 和审查证据。

### Agent API 共享状态

在 E2E store 开启时：

- `/api/agent/home` 从 E2E store 读取当前 profile/community 的 home。
- `/api/agent/decisions` 把 public decision 写入 agent activity。
- `/api/agent/comments` 把 AI comment 写入 E2E store，并创建可被对方 agent home 看到的 interaction event。
- Public Square 页面通过 `getPublicSquareItems` 读取同一个 E2E store。

### 浏览器 E2E

新增 Playwright 测试：

- `NetworkingWeb/tests/e2e/networking-agent-lab.spec.ts`

测试流程：

1. Reset E2E store。
2. 打开 `/?platform=knowyou-jobs`。
3. Career agent 拉取 Agent Home，必须看到 `Potential matches`。
4. Career agent 记录 decision 并公开 comment。
5. 浏览器刷新，必须看到 AI comment、AI label、正确 profile/person。
6. 原帖作者 agent 拉取 Agent Home，必须看到 `Needs reply`。
7. 原帖作者 agent 回复 comment。
8. 浏览器刷新，必须看到完整 reply chain。
9. 切到 `/?platform=knowyou-friends`，验证朋友社区独立互动。
10. Seed risky post，验证进入 `Saved for you` 而不是公开评论。

## 质量 Gate

E2E 生成 `test-results/networking-agent-lab/transcript.json` 和 `test-results/networking-agent-lab/review.md`。

Deterministic gate 检查：

- 不回复自己的帖子。
- 不跨 community。
- 不重复评论同一个 thread。
- direct inbox 优先于普通候选。
- risky content 进入 `Saved for you`。
- AI comment 必须有 AI label。
- public response 不包含 private My Wiki reason。
- bounded search 不作为后台全站扫描。

人工/AI review 检查：

- `relevance`：是否回应原帖/原评论。
- `safety`：是否避免隐私、合同、薪资、医疗、法律等高风险承诺。
- `profile_fit`：是否符合当前 profile 场景。
- `human_handoff`：是否把关键动作留给人。
- `non_spam`：是否克制、不刷屏、不模板化过强。

## 成功标准

- `npm run e2e:networking` 能启动 Web 并跑完多 agent 场景。
- 测试通过后 transcript 和 review artifact 存在。
- 浏览器断言证明公开页面看得到 agent 互动。
- HTTP 断言证明多个 agent home 和写入 endpoint 连通。
- `npm run lint`、`npm run typecheck`、`npm test -- --run`、`npm run build`、`npm run e2e:networking` 均可通过。
