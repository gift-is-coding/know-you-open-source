# Networking Production Review Skill — Spec

日期：2026-07-09
分支：`codex/networking-community-bootstrap`
范围：把 Networking 生产可用性 review 流程固化为项目 skill，用于 App/Web/platform 打通前的确定性验证和 Claude review。

## 背景

Networking 这轮开发已经包含 App、Web、Supabase contract、MCP 和本地启动验证。单靠人工 checklist 容易漏掉 CSS chunk、fresh app、localhost handoff、viewer scope、Claude review 等生产风险。需要一个可复用 skill，让 Codex 开发完成后能按固定 pipeline 做验证、产出 review packet，并把 Claude 的生产 review 纳入流程。

## 目标

- 新增 `.agents/skills/knowyou-networking-production-review`。
- skill 能明确触发场景、执行命令、跳过规则、通过标准和失败报告方式。
- pipeline 需要覆盖代码功能、App UX、Web UX、生产集成和安全风险。
- pipeline 需要生成可追溯 report：命令日志、失败 gate、fresh app metadata、Web preview 证据、Claude review artifact。
- Claude prompt 必须要求 benchmark 和 test case，且从生产环境打通视角审查。

## 非目标

- 不替代人工最终产品验收。
- 不自动 push。
- 不在 Claude review 阶段修改文件。
- 不清理用户已有 App 登录、onboarding、auth 或 UserDefaults 状态。

## 验收标准

1. `SKILL.md` 描述清楚何时使用、如何运行、何时可以判定 PASS。
2. `run_pipeline.sh` 可执行，并包含 Web tests/lint/typecheck/build、Swift targeted/full test、xcodebuild build、Web HTML/CSS chunk 检查、fresh app metadata、Claude CLI review。
3. localhost handoff 审计 fail-closed：只允许 DEBUG 下的 `NetworkingBackendConfiguration` fallback。
4. prompt 明确覆盖 `production`、`App UX`、`Web UX`、`benchmark`、`test case`。
5. contract test、skill validator、shell syntax、dry-run 均通过。
