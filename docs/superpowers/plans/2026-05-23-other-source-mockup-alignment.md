# Other Source Mockup Alignment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the implemented `Other Source` route match the approved mockup and product semantics.

**Architecture:** Keep the existing connector domain and actions. Add a presentation surface enum so the same underlying controls can render either as the legacy mixed `Connectors` sheet or as the root-level `Other Source` page. Update tests first, then view copy/layout, then docs.

**Tech Stack:** SwiftUI, XCTest, existing `ConnectorsPanelPresentation`, `ConnectorsManagementView`, `MainWindowView`.

---

### Task 1: Presentation Contract

**Files:**
- Modify: `KnowYou/UI/Settings/ConnectorsPanel.swift`
- Modify: `KnowYouTests/ConnectorsPanelTests.swift`

- [x] Add a failing test that `Other Source` uses title `Other Source`, the local Markdown subtitle, and the mockup empty state.
- [x] Add a failing test that the legacy sheet surface keeps title `Connectors`.
- [x] Implement `ConnectorsManagementSurface` and computed copy on `ConnectorsManagementPresentation`.
- [x] Run `xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/ConnectorsPanelTests`.

### Task 2: Root Page Layout

**Files:**
- Modify: `KnowYou/UI/Settings/ConnectorsPanel.swift`
- Modify: `KnowYou/UI/MainWindowView.swift`

- [x] Render the root `Other Source` surface with knowledge imports first.
- [x] Hide Daily Memory Export from the root `Other Source` surface.
- [x] Keep Daily Memory Export in the gear-menu `Connectors` sheet.
- [x] Update the right detail pane to show `Local Storage` and `Sync Rules`.
- [x] Run the same focused tests.

### Task 3: Verification

**Files:**
- Modify: `docs/architecture.md`
- Review: `docs/requirements-spec.md`

- [x] Update architecture docs for the split between `Other Source` root and legacy `Connectors` sheet.
- [x] Run `git diff --check`.
- [x] Run `xcodebuild build -scheme KnowYou -destination 'platform=macOS'`.
- [x] Run `xcodebuild test -scheme KnowYou -destination 'platform=macOS'`.
