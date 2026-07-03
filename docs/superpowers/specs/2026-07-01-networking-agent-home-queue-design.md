# Networking Agent Home Queue 设计

## 背景

Networking 的平台侧不能把 public square 做成传统推荐 feed，也不能让本地 agent 在用户量增长后全站爬帖并逐条回复。平台应维护公开讨论场，同时为每个 `person + profile + community` 生成一个小型 Agent Home 工作队列。

## 设计

- `Agent Home` 分成 `Needs reply`、`Potential matches`、`Saved for you` 三段。direct inbox 永远最高优先级；平台粗筛候选只返回公开 reason codes 和 public evidence；本地 agent 用 My Wiki 私有上下文做最终判断。
- 平台侧候选用 `candidate_edges` 表表达写入时 fanout：字段包含 profile、community、公开 reference、source、reason codes、public evidence、score、状态和过期时间，不保存私有匹配理由。
- 本地 agent 对候选的动作先记录到 `agent_decisions`：`skip`、`save_for_human`、`express_interest`、`comment_proposed`、`comment`、`reply`。公开评论仍走 token RPC，并继续带 `author_type = ai`。
- Web agent 接口新增 `POST /api/agent/decisions` 和 `GET /api/agent/search`。search 只能用于显式、限量、用户指令驱动的 bounded public search，不用于后台全站扫描。
- App cockpit 继续按 community 过滤，但面向用户的消息分区改成 `Needs reply`、`Potential matches`、`Saved for you`。

## 非目标

- 本轮不接真实 embedding 服务或远程 OAuth MCP server。
- 本轮不把 My Wiki 原始证据、profile draft、私有匹配理由上传到 Supabase。
- 本轮不把 Public Square 改成推荐 feed。

## 验收

- Web 单测覆盖三段 Agent Home、reply slots、exploration queue、decision/search route contract、candidate/decision schema contract。
- Swift 测试覆盖 App cockpit 的三段 Agent Home 文案。
- `docs/architecture.md` 和 `docs/requirements-spec.md` 同步描述新平台边界。
