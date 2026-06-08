# Codex 回归 Runner 设计

## 目标

让 KnowYou 回归测试从“文档说明”变成可运行入口：脚本负责构建、隔离环境、fixture、启动路径和证据目录；Codex 的 GUI / Computer Use / Browser / Chrome 能力负责真实用户点击、观察和截图。

## 核心设计

- 新增 `scripts/regression/run-user-journey.sh`，支持 `--app-clean`、`--permission-clean`、`--true-clean-checklist` 和 `--dry-run`。
- `app-clean` 使用 `build/regression/<run-id>/profile` 作为隔离根，导出 `KNOWYOU_PROFILE_ROOT`、`KNOWYOU_USER_DEFAULTS_SUITE`、`KNOWYOU_KEYCHAIN_SERVICE` 等环境变量，并生成 Computer Use prompt。
- `permission-clean` 继续使用 `/Applications/KnowYou New User.app` 和 `dev.knowyou.newuser`，只允许清理或重置 New User 身份，禁止触碰日常 `dev.knowyou.app`。
- App 运行时支持读取 regression 环境变量，把 Application Support、Vault、SQLite、UserDefaults suite、Keychain service 切到隔离 profile。
- 脚本不伪装成 UI 自动化框架；它只做确定性准备、启动和证据收集，实际点击必须由 Codex Computer Use/GUI 能力完成。

## 成功标准

- 用户可以运行 `scripts/regression/run-user-journey.sh --app-clean` 得到一个可复用 run 目录、隔离 profile、启动命令和 Computer Use prompt。
- 用户可以运行 `scripts/regression/run-user-journey.sh --permission-clean` 安装并启动 New User app，验证 first-run/TCC 路径不会影响日常 app。
- 测试覆盖 runner dry-run 输出、runtime profile 环境变量解析、UserDefaults suite 隔离。
- 回归文档说明脚本入口、证据目录和 Computer Use 执行边界。
