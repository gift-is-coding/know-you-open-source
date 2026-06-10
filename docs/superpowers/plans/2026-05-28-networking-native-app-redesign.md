# Networking Native App Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 App 端 Networking cockpit 从 WebView 改为和 KnowYou 其他页面一致的原生 SwiftUI，并修正 sidebar 图标尺寸。

**Architecture:** Web 平台继续保留 Next.js/Supabase；macOS app 内部只使用 SwiftUI 组件渲染 profile generator、platform cards 和 activity/inbox。Sidebar icon metrics 增加 system image 维度，避免 `person.2.wave.2` 视觉过大。

**Tech Stack:** SwiftUI, XCTest, existing KnowYou sidebar presentation tests.

---

### Task 1: 图标 metrics 测试

**Files:**
- Modify: `KnowYouTests/DailyMarkdownViewTests.swift`
- Modify: `KnowYou/UI/Sidebar/DateSidebarView.swift`

- [ ] 增加测试：`networking` root item 的 system icon metrics frame 仍为 `24`，content size 小于 `Add Source`。
- [ ] 运行 targeted test，确认先失败。
- [ ] 改 `DateSidebarView.sidebarItemIcon` 和 metrics helper，让 system image 可按 item id/image 缩放。
- [ ] 重新运行 targeted test。

### Task 2: 原生 cockpit 边界测试

**Files:**
- Modify: `KnowYouTests/NetworkingCockpitPresentationTests.swift`
- Replace: `KnowYou/UI/Networking/NetworkingCockpitView.swift`

- [ ] 增加源码边界测试：`NetworkingCockpitView.swift` 不包含 `import WebKit`、`WKWebView`、`NSViewRepresentable`、`loadHTMLString`。
- [ ] 运行 targeted test，确认先失败。
- [ ] 删除 WebView/HTML 代码，重写为 SwiftUI 原生布局。
- [ ] 用现有 `presentation.sections` 驱动 inbox/activity；profile 和 platform mock 数据保持在 view 内的 lightweight fixtures。
- [ ] 重新运行 targeted test。

### Task 3: 验证与提交

**Files:**
- Modify: `docs/architecture.md`
- Modify: `docs/requirements-spec.md`

- [ ] 更新架构/需求文档，声明 app 端 Networking cockpit 是原生 SwiftUI，不是 WebView。
- [ ] 运行 `git diff --check`。
- [ ] 运行 `xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/NetworkingCockpitPresentationTests -only-testing:KnowYouTests/DailyMarkdownViewTests`。
- [ ] 运行 `xcodebuild test -scheme KnowYou -destination 'platform=macOS'`。
- [ ] 运行 `xcodebuild build -scheme KnowYou -destination 'platform=macOS'`。
- [ ] amend 当前 `codex/networking` 提交。
