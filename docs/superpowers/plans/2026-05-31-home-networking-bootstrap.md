# Home Networking Bootstrap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 增加默认 Home、可视化 Networking 预览、Todo 英文化和老用户最近 3 天补生成入口。

**Architecture:** 在现有 `NavigationSplitView` 和 `DateSidebarPresentation` 上扩展一个 `Home` root item，不改变日记、My Wiki、Other Source 的既有数据流。Home 与 Networking 使用轻量 presentation structs 让 copy 和视觉资产可测试；老用户补生成复用 `AppState` 现有 onboarding bootstrap 生成路径。

**Tech Stack:** SwiftUI、XCTest、Xcode asset catalog、现有 AppState/DateSidebarView/MainWindowView/TodoInboxView。

---

### Task 1: Sidebar 与 presentation 测试

**Files:**
- Modify: `KnowYouTests/DailyMarkdownViewTests.swift`

- [x] 写失败测试，断言 root 顺序为 `Home`、`Networking`、`Todo`、`My Wiki`、`Other Source`、`My Diary`。
- [x] 写失败测试，断言 Home、Networking、Todo copy presentation 的英文文案和视觉 asset name。
- [x] 运行 targeted tests，确认因缺少新 API/类型而失败。

### Task 2: UI 与状态实现

**Files:**
- Modify: `KnowYou/UI/Sidebar/DateSidebarView.swift`
- Modify: `KnowYou/UI/MainWindowView.swift`
- Modify: `KnowYou/UI/Todo/TodoInboxView.swift`
- Modify: `KnowYou/App/AppState.swift`
- Add: `KnowYou/Assets.xcassets/HomeDashboardHero.imageset/*`
- Add: `KnowYou/Assets.xcassets/NetworkingPreviewHero.imageset/*`

- [x] 增加 Home root item、selection action 和 MainWindow mode。
- [x] 增加视觉化 Home 页面，包含倒计时、短文案、功能跳转和 `Generate Last 3 Days`。
- [x] 替换 Networking placeholder 为 profile/social preview 页面。
- [x] 将 Todo 可见中文 copy 收敛到 `TodoInboxCopy` 并改为英文。
- [x] 增加 `missingRecentHistoryBootstrapDayKeys` 和 `queueRecentHistoryBootstrapIfNeeded()`，复用现有 bootstrap 逻辑。
- [x] 生成并提交 Home/Networking bitmap assets。

### Task 3: 文档与验证

**Files:**
- Modify: `docs/architecture.md`
- Modify: `docs/requirements-spec.md`
- Add: `docs/superpowers/specs/2026-05-31-home-networking-bootstrap-design.md`
- Add: `docs/superpowers/plans/2026-05-31-home-networking-bootstrap.md`

- [x] 记录 Home、Networking、Todo 英文化和老用户补生成行为。
- [x] 运行 targeted tests。
- [x] 运行完整 `xcodebuild test -scheme KnowYou -destination 'platform=macOS'`。
- [x] 运行完整 `xcodebuild build -scheme KnowYou -destination 'platform=macOS'`。
- [x] 运行 `git diff --check`。
- [x] 用 `./scripts/run-dev-app.sh` fresh build + launch。
