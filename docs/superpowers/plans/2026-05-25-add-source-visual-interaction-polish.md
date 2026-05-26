# Add Source Visual Interaction Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Add Source prompt generation modal, readable, logo-backed, and remove redundant root folders in the sidebar source tree.

**Architecture:** Keep the existing SwiftUI views and presentation structs. Add lightweight presentation fields for logo assets and prompt modal state, then adjust the tree path helper to trim duplicated root-folder components.

**Tech Stack:** SwiftUI, XCTest, existing asset catalog logos.

---

### Task 1: Presentation Tests

**Files:**
- Modify: `KnowYouTests/ConnectorsPanelTests.swift`
- Modify: `KnowYouTests/DailyMarkdownViewTests.swift`

- [ ] Add tests that Add Source cards expose expected logo asset names, external prompt UI is modal-only, and default prompt time is 11:00.
- [ ] Add a sidebar test that paths like `<root>/<root-name>/A.md` show `A` directly under the connector instead of an extra root-name folder.
- [ ] Run targeted tests and confirm they fail for missing behavior.

### Task 2: Add Source UI

**Files:**
- Modify: `KnowYou/UI/Settings/ConnectorsPanel.swift`

- [ ] Add optional `brandAssetName` to Add Source card presentation.
- [ ] Render real logo assets for Obsidian, Feishu, Notion, and Google Drive.
- [ ] Replace inline prompt builder with `.sheet`.
- [ ] Default prompt time to 11:00.
- [ ] Increase Add Source title, subtitle, card text, card padding, icon size, and button control size.
- [ ] Run `ConnectorsPanelTests` and confirm green.

### Task 3: Sidebar UI And Tree

**Files:**
- Modify: `KnowYou/UI/Sidebar/DateSidebarView.swift`

- [ ] Add optional `brandAssetName` to sidebar root items.
- [ ] Render logos for source rows.
- [ ] Increase sidebar row font and vertical spacing.
- [ ] Trim duplicated connector root folder names from imported document paths.
- [ ] Run `DailyMarkdownViewTests` and confirm green.

### Task 4: Verification

**Files:**
- Modify docs if architecture or requirements need small wording updates.

- [ ] Run `git diff --check`.
- [ ] Run targeted tests.
- [ ] Run `xcodebuild build -scheme KnowYou -destination 'platform=macOS'`.
- [ ] Run `./scripts/build-release.sh`.
- [ ] Open fresh `build/release/KnowYou.app` without clearing state and verify the running process path.
