# My Wiki Update Feedback 和 Onboarding 安装判断实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复 My Wiki Update 无反馈和 Onboarding 已安装仍提示移动的问题。

**Architecture:** 把 My Wiki 更新按钮状态收敛到 presentation model，SwiftUI 只渲染 presentation；把安装判断收敛到 `OnboardingApplicationInstallPolicy`，支持 macOS Applications firmlink 路径。

**Tech Stack:** Swift 6, SwiftUI, XCTest, macOS app bundle path policy.

---

### Task 1: 写失败测试

**Files:**
- Modify: `KnowYouTests/KnowledgeOntologyPanelTests.swift`
- Modify: `KnowYouTests/MyWikiIngestProgressStoreTests.swift`
- Modify: `KnowYouTests/OnboardingContentTests.swift`

- [x] 增加 My Wiki updating presentation 测试，期望按钮显示 `Generating...`、禁用、状态为 `Generating My Wiki...`。
- [x] 增加 My Wiki project unavailable presentation 测试，期望按钮禁用并显示 folder unavailable。
- [x] 增加 running placeholder progress 测试，期望无 source count 时标题为 `Generating My Wiki`。
- [x] 增加 `/System/Volumes/Data/Applications` 安装路径测试。
- [x] 运行 focused tests，确认新增断言失败。

### Task 2: 实现 My Wiki 更新反馈

**Files:**
- Modify: `KnowYou/UI/MyWiki/MyWikiModels.swift`
- Modify: `KnowYou/UI/MyWiki/MyWikiPanel.swift`
- Modify: `KnowYou/Services/MyWiki/MyWikiIngestProgressStore.swift`

- [x] 扩展 `MyWikiDigestSchedulePresentation`，包含更新按钮标题、禁用状态和状态文案。
- [x] 点击 Update 时立即设置 running placeholder progress。
- [x] `projectRoot == nil` 时显示状态而不是静默返回。
- [x] 运行 My Wiki focused tests，确认通过。

### Task 3: 实现 Onboarding 安装判断修复

**Files:**
- Modify: `KnowYou/UI/Onboarding/OnboardingContent.swift`

- [x] 允许 `/Applications/<expected app>`。
- [x] 允许 `/System/Volumes/Data/Applications/<expected app>`。
- [x] 保持 DMG、Downloads、DerivedData 和错误 bundle id 为 false。
- [x] 运行 Onboarding focused tests，确认通过。

### Task 4: 验证和打包

**Files:**
- Review: touched Swift files and docs.

- [ ] 运行 `xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/KnowledgeOntologyPanelTests -only-testing:KnowYouTests/MyWikiIngestProgressStoreTests -only-testing:KnowYouTests/OnboardingContentTests`。
- [ ] 运行 `xcodebuild build -scheme KnowYou -destination 'platform=macOS'`。
- [ ] 如用户需要，再生成新的 New User DMG 到 Desktop。
