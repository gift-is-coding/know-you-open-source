# Worktree-safe App Launch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让开发期打开 KnowYou 时不误杀其他 worktree，并在 build badge 里显示当前 branch/worktree。

**Architecture:** `scripts/run-dev-app.sh` 只围绕当前 repo 的 `.derived-data/dev` app 做精确 quit/kill/open。Xcode build phase 写入 `BuildMetadata.json` 的 branch/worktree 字段，`AppBuildMetadata` 只读取 bundle 内静态元数据。

**Tech Stack:** Bash, Xcode build phase, Swift metadata model, XCTest.

---

### Task 1: 测试 build badge 和启动脚本边界

**Files:**
- Modify: `KnowYouTests/SettingsMetadataTests.swift`

- [x] 添加 `AppBuildMetadata` 显示 branch/worktree 的失败测试。
- [x] 添加 `scripts/run-dev-app.sh` 不做全局 kill/DerivedData 清理的失败测试。
- [x] 运行 targeted test，确认失败来自缺失字段和旧脚本行为。

### Task 2: 实现 metadata 与脚本修复

**Files:**
- Modify: `KnowYou/App/AppSupportMetadata.swift`
- Modify: `KnowYou.xcodeproj/project.pbxproj`
- Modify: `scripts/run-dev-app.sh`

- [x] `AppBuildMetadata` 增加 `gitBranch`、`worktreeName` 并拼进 badge。
- [x] build phase 写入 `gitBranch`、`worktreeName`。
- [x] dev 启动脚本只 kill 当前 app path，移除全局 DerivedData 清理，并使用 `open -n` 启动当前 build。

### Task 3: 验证

**Files:**
- Modify: `docs/architecture.md`
- Modify: `docs/requirements-spec.md`

- [x] 运行 `SettingsMetadataTests`。
- [x] 运行 `git diff --check`。
- [x] 运行 `xcodebuild test -scheme KnowYou -destination 'platform=macOS'`。
- [x] 运行 `xcodebuild build -scheme KnowYou -destination 'platform=macOS'`。
- [x] 用修复后的 `scripts/run-dev-app.sh` 打开当前 worktree app。
