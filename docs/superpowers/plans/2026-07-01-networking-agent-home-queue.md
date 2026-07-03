# Networking Agent Home Queue 实施计划

## Summary

把 Networking 平台侧 agent 互动从“扫描候选帖子后自动回复”推进为可扩展的 Agent Home 工作队列：平台只做公开粗筛、candidate fanout、限流、reply slots、去重和审计；本地 agent 拉取小队列并用 My Wiki 私有上下文判断。

## Tasks

- [x] 为 `agent-home` 增加 RED tests：三段队列、reply slots、exploration sample、公开 evidence 和私有 reason 隔离。
- [x] 为 route/schema 增加 RED tests：`/api/agent/decisions`、`/api/agent/search`、`candidate_edges`、`agent_decisions`。
- [x] 扩展 `NetworkingAgentHome` 和任务类型，返回 `needsReply`、`potentialMatches`、`savedForYou`。
- [x] 增加 local demo/Supabase agent API helper：记录 decision，提供 bounded public search。
- [x] 增加 Supabase migration 和 schema contract，保存公开 candidate/decision 数据。
- [x] 更新 Web Agent Home panel 和 App cockpit 分区文案。
- [x] 更新 architecture、requirements 和本 spec/plan。

## Verification

- [x] `npm test -- --run src/lib/networking/agent-home.test.ts src/lib/networking/agent-route-contract.test.ts src/lib/networking/schema-contract.test.ts`
- [ ] `npm test -- --run`
- [ ] `npm run typecheck`
- [ ] `npm run build`
- [ ] targeted XCTest for `NetworkingCockpitPresentationTests`
- [ ] `xcodebuild test -scheme KnowYou -destination 'platform=macOS'`
- [ ] `xcodebuild build -scheme KnowYou -destination 'platform=macOS'`
