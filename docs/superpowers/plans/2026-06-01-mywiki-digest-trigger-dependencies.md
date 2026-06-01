# My Wiki Digest Trigger Dependencies Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复 My Wiki digest 因 `vite` 缺失失败的问题，并在 My Wiki 页面明确展示触发方式、上次更新时间和手动更新按钮。

**Architecture:** 保持 My Wiki digest 手动触发语义；UI 通过 presentation model 显示触发说明和上次更新时间。Bridge 在 development source 模式下补齐 `ThirdParty/llm_wiki` 依赖后再调用 headless ingest。

**Tech Stack:** SwiftUI, XCTest, Node/npm, ThirdParty/llm_wiki headless runner.

---

## Tasks

- [x] 定位根因：`knowyou-ingest-runner.mjs` 启动时找不到 `vite`，当前 worktree 缺 `ThirdParty/llm_wiki/node_modules`。
- [x] 添加 bridge 测试：缺 `node_modules/vite` 时先执行 `npm install`，再执行 `npm run knowyou:ingest`。
- [x] 添加 My Wiki digest presentation 测试：说明手动触发、显示上次更新时间、提供 `Update Now`。
- [x] 实现 `MyWikiPipelineBridge.ensureDevelopmentDependencies(...)`。
- [x] 实现 `MyWikiDigestSchedulePresentation`。
- [x] 在 `MyWikiPanel` 顶部展示 digest 状态条和 `Update Now` 按钮。
- [x] 在当前 worktree 的 `ThirdParty/llm_wiki` 运行 `npm install`，确认 `node_modules/vite` 存在。
- [x] 运行 focused tests。
- [x] 运行 My Wiki 相关测试。
- [x] 运行完整 `xcodebuild test -scheme KnowYou -destination 'platform=macOS'`。
- [x] 运行 `xcodebuild build -scheme KnowYou -destination 'platform=macOS'`。
- [x] 运行 `git diff --check`。
- [x] 用 `scripts/install-new-user-app.sh` 重新安装并打开 `/Applications/KnowYou New User.app`。
