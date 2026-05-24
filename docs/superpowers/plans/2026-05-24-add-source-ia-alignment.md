# Add Source IA Alignment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Align KnowYou's sidebar and source management page with the approved Add Source prototype.

**Architecture:** Keep the existing `MainContentSelection.otherSourceManager` route as the implementation backing route, but rename the user-facing surface to Add Source. Refactor sidebar presentation so `Add Source` is the source group and `My Diary`, local sources, and external connectors are children. Replace the Other Source management surface with a card-based Add Source page.

**Tech Stack:** SwiftUI, XCTest, existing `KnowledgeImportConfig` and `SyncMemoryConfig` presentation models.

---

### Task 1: Sidebar Presentation

**Files:**
- Modify: `KnowYou/UI/Sidebar/DateSidebarView.swift`
- Modify: `KnowYouTests/DailyMarkdownViewTests.swift`

- [x] Write failing tests for `Add Source` root, `My Diary` child, connector children, and no `Other Source` label.
- [x] Run `xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/DailyMarkdownViewTests` and verify red.
- [x] Refactor `DateSidebarPresentation` to expose `sourceRootItem`, `diaryRootItem`, diary sections, and connector source items.
- [x] Update `DateSidebarView` list to render Add Source as the top group, with My Diary dates and connectors nested under it.
- [x] Verify focused tests pass.

### Task 2: Add Source Cards

**Files:**
- Modify: `KnowYou/UI/Settings/ConnectorsPanel.swift`
- Modify: `KnowYou/UI/MainWindowView.swift`
- Modify: `KnowYouTests/ConnectorsPanelTests.swift`

- [x] Write failing tests for `Add Source` title/subtitle, built-in My Diary card, Local Folder/Obsidian/Feishu/Notion/Google Drive card labels, and no Add API option.
- [x] Run focused connector tests and verify red.
- [x] Add presentation structs for card rows and actions.
- [x] Render root Add Source surface as separate rounded cards matching the prototype.
- [x] Keep legacy Connectors sheet behavior available from settings without changing export controls.
- [x] Verify focused tests pass.

### Task 3: Verification

**Files:**
- Modify: `docs/architecture.md`
- Modify: `docs/requirements-spec.md`

- [x] Update docs to describe Add Source as the source hierarchy.
- [x] Run `git diff --check`.
- [x] Run focused tests.
- [x] Run `xcodebuild build -scheme KnowYou -destination 'platform=macOS'`.
- [x] Run `xcodebuild test -scheme KnowYou -destination 'platform=macOS'`.
- [x] Build release app and open it without clearing state.
