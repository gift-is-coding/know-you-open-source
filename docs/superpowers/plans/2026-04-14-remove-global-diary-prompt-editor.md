# Remove Global Diary Prompt Editor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 下线用户可编辑的全局 diary prompt，并让生成链路只走 canonical prompt。

**Architecture:** 删除主窗口 prompt editor UI、配置持久化字段和 AppState 公开接口。生成与 full recovery 统一回到 `DailyMarkdownComposer.storyPrompt(dayKey:events:)`。legacy override key 仅做忽略与清理，不保留任何运行时效果。

**Tech Stack:** SwiftUI, Swift 6, XCTest, Xcodebuild

---

### Task 1: Remove Product Surface

**Files:**
- Modify: `KnowYou/UI/MainWindowView.swift`
- Delete: `KnowYou/UI/Reader/DiaryPromptEditorSheet.swift`
- Modify: `KnowYou.xcodeproj/project.pbxproj`

- [x] 删除主窗口 `Edit Prompt` 按钮、sheet 状态和打开逻辑。
- [x] 删除 `DiaryPromptEditorSheet.swift` 源文件。
- [x] 从 Xcode project 中移除对应 file reference 和 source build entry。

### Task 2: Remove Override Runtime Path

**Files:**
- Modify: `KnowYou/Services/Summary/SummarizerConfig.swift`
- Modify: `KnowYou/App/AppState.swift`
- Modify: `KnowYou/Services/Composer/DailyMarkdownComposer.swift`

- [x] 删除 `SummarizerConfig.globalDiaryPromptOverride` 与相关 helper。
- [x] 让 `save` 与 `load` 清理 legacy `summarizerGlobalDiaryPromptOverride` key。
- [x] 删除 `AppState` prompt override 动作和状态接口。
- [x] 让生成与 full recovery 只传 canonical prompt。
- [x] 删除 `DailyMarkdownComposer` 的 `globalOverride` 重载入口。

### Task 3: Update Tests

**Files:**
- Modify: `KnowYouTests/SummarizerConfigTests.swift`
- Modify: `KnowYouTests/MainWindowViewModelTests.swift`
- Modify: `KnowYouTests/DailyMarkdownComposerTests.swift`

- [x] 用 legacy key 忽略/清理测试替换旧的 prompt override 持久化测试。
- [x] 增加生成与 full recovery 忽略 legacy override 的回归测试。
- [x] 更新 composer 测试到 canonical prompt API。

### Task 4: Sync Docs

**Files:**
- Modify: `docs/requirements-spec.md`
- Modify: `docs/architecture.md`
- Modify: `docs/feature-roadmap.md`
- Create: `docs/superpowers/specs/2026-04-14-remove-global-diary-prompt-editor.md`
- Create: `docs/superpowers/plans/2026-04-14-remove-global-diary-prompt-editor.md`

- [x] 删除现行产品与架构文档中的 prompt editor 描述。
- [x] 在 roadmap 记录结构化生成控制的后续方向。
- [x] 保存本次 spec/plan 归档文件。

### Task 5: Verify

**Files:**
- Modify: `none`

- [x] 跑 focused regression：
  - `xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/SummarizerConfigTests/testLoadIgnoresAndClearsLegacyGlobalDiaryPromptOverride -only-testing:KnowYouTests/SummarizerConfigTests/testSaveClearsLegacyGlobalDiaryPromptOverrideKey -only-testing:KnowYouTests/MainWindowViewModelTests/testGenerateStoryIgnoresLegacyPromptOverrideInPersistedConfig -only-testing:KnowYouTests/MainWindowViewModelTests/testRefreshSelectedDayFullRecoveryIgnoresLegacyPromptOverrideAndNormalizesBeforePersisting -only-testing:KnowYouTests/DailyMarkdownComposerTests/testStoryPromptUsesCanonicalDefaultPrompt`
- [x] 跑全量验证：
  - `xcodebuild test -scheme KnowYou -destination 'platform=macOS'`
  - `xcodebuild build -scheme KnowYou -destination 'platform=macOS'`
