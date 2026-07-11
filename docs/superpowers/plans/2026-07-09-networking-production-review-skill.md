# Networking Production Review Skill 计划

## 目标

把“Codex 开发完成后运行本地验证、打开 App/Web、再调用 Claude review”的流程变成项目内可复用 skill，并让它能产出生产打通视角的 benchmark 和 test case。

## 步骤

1. 先写 skill pipeline contract test，约束必须包含 Swift/Web 验证、HTML/CSS chunk、fresh app metadata、Claude review、fail-closed 语义和 review prompt 关键词。
2. 创建 `.agents/skills/knowyou-networking-production-review/`，补 `SKILL.md`、`agents/openai.yaml`、Claude review prompt。
3. 实现 `scripts/run_pipeline.sh`：验证 git 状态、运行 Web/App gates、重启当前 worktree 的 Web preview、检查首个 CSS chunk、解析 freshly built `KnowYou.app` 的 `BuildMetadata.json`、可选启动 App、调用 `claude -p` 并写 report。
4. 加强生产风险检查：localhost handoff 只允许 DEBUG 配置路径；任何非允许命中都让 pipeline 失败。
5. 验证 skill 本身：运行 contract test、skill creator validator、`bash -n`、`--help` 和 dry-run。
