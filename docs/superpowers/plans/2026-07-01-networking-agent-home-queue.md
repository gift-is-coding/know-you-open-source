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
- [x] 补齐 App activation 到平台的真实链路：anonymous owner 写 person/profile/membership/token，token 明文只留本地，平台只存 hash。
- [x] 补齐 MCP 到平台的真实调用：`networking_agent_home`、`networking_record_decision`、`networking_publish_post`、`networking_publish_comment` 不再只返回待发布 payload。
- [x] 修复平台侧 owner grants、person-level agent token 与 Agent Home RPC 的兼容，确保 App 一键开启后的 token 能拉取队列。
- [x] 更新 architecture、requirements 和本 spec/plan。

## Verification

- [x] `npm test -- --run src/lib/networking/agent-home.test.ts src/lib/networking/agent-route-contract.test.ts src/lib/networking/schema-contract.test.ts`
- [x] `npm run lint`
- [x] `npm test -- --run`
- [x] `npm run typecheck`
- [x] `npm run build`
- [x] `npm run e2e:networking`
- [x] `npm audit --audit-level=moderate`
- [x] Supabase migration replay in fresh local Postgres 16 database.
- [x] Supabase smoke: authenticated owner writes person/profile/membership/person-level token; public post fanout creates candidate edge; anon agent home returns candidate; agent comment writes audit and marks edge delivered; invalid token is rejected.
- [x] Supabase guard smoke: daily auto-comment limit and own-root-post AI comment are rejected.
- [x] targeted XCTest coverage in `NetworkingCockpitPresentationTests` and `NetworkingPlatformClientTests`.
- [x] `scripts/test-networking-ui-static.sh`
- [x] `xcodebuild test -scheme KnowYou -destination 'platform=macOS,arch=arm64' -parallel-testing-enabled NO -enableCodeCoverage NO CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=`
- [x] `xcodebuild build -scheme KnowYou -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=`
- [x] `plutil -lint KnowYou.xcodeproj/project.pbxproj`
- [x] `git diff --check`
