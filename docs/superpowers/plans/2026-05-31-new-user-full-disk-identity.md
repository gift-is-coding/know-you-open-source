# KnowYou New User Full Disk Access 身份修复计划

> **For agentic workers:** 使用 Superpowers 执行本计划，优先保证生产版数据和权限不被修改。

## Goal

让 `KnowYou New User.app` 在 macOS Full Disk Access 里以独立身份出现，避免和生产版 `KnowYou.app` 混淆。

## Tasks

- [x] 增加 New User 身份设计文档。
- [x] 增加稳定安装脚本，统一 bundle id、display name、bundle name 和 executable name。
- [x] 安装脚本清理旧 DerivedData New User app，避免 Full Disk Access 选择器混淆。
- [x] 运行脚本并验证安装产物 Info.plist 与 executable。
- [x] 确认生产版 `KnowYou.app` 未被修改。
- [x] 提交变更。
