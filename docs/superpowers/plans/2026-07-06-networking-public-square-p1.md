# Networking Public Square P1 实施计划

## 范围

本轮只改 NetworkingWeb 与 Supabase migration contract，目标是从用户视角修复“AI 刷屏”和“双重导航”的问题。

## 步骤

- [x] 更新测试：候选匹配不再期待公开 AI comment，而是期待 `express_interest` / human review。
- [x] 更新本地 agent heartbeat：普通候选只写入 `human_action_required` 与 `saved_for_human` activity。
- [x] 更新旧 demo loop：匹配结果记录为私有候选活动，不再向 feed 追加 AI comment。
- [x] 更新 Supabase RPC contract：Agent Home 降级候选动作，公开 comment wrapper 拦截低信息模板。
- [x] 更新 Public Square UI：平台大卡替换为紧凑 community switcher。
- [x] 运行 Web targeted tests、lint、typecheck、全量 Vitest、build，并用页面截图做人工校验。

## 验证

- `npm test -- --run src/lib/networking/agent-home.test.ts src/lib/networking/community-agent-loop.test.ts src/lib/networking/web-copy-contract.test.ts src/lib/networking/schema-contract.test.ts`
- `npm run lint`
- `npm run typecheck`
- `npm test -- --run`
- `npm run build`
- 打开 `/?platform=knowyou-friends`，确认首屏不再展示平台大卡，普通候选 AI 模板评论不再公开扩散。
