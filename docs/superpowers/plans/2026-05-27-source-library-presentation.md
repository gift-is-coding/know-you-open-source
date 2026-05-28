# Source Library Presentation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a hierarchical, selectable My Wiki source catalog presentation and wire Source Library UI to catalog snapshots.

**Architecture:** Put presentation and bulk mutation helpers beside catalog domain models so tests and SwiftUI can share behavior. Keep UI as a thin stateful shell that reloads via `MyWikiSourceCatalogBuilder`, mutates snapshots locally, saves through `MyWikiSourceCatalogStore`, and re-renders a filtered tree.

**Tech Stack:** Swift, SwiftUI, XCTest, Xcode project file registration.

---

### Task 1: Presentation Model And Tests

**Files:**
- Create: `KnowYouTests/MyWikiSourceLibraryPresentationTests.swift`
- Modify: `KnowYou/Services/MyWiki/MyWikiSourceCatalog.swift`
- Modify: `KnowYou.xcodeproj/project.pbxproj`

- [ ] Write failing tests for counts, title/path query, status filter, visible-only invert, and tree mixed state.
- [ ] Run the focused presentation test target and confirm failures are from missing presentation APIs.
- [ ] Add `MyWikiSourceCatalogBulkAction`, `MyWikiSourceLibraryPresentation`, and snapshot bulk apply helper.
- [ ] Run presentation tests until green.

### Task 2: Manual Imports Destination

**Files:**
- Modify: `KnowYou/Services/MyWiki/MyWikiSourceLibrary.swift`
- Modify: `KnowYouTests/MyWikiSourceLibraryTests.swift`

- [ ] Update existing tests to expect `raw/sources/Manual Imports`.
- [ ] Run source library tests and confirm path failures.
- [ ] Change `rawSourcesDirectory(projectRoot:)` to Manual Imports while leaving summary lookup under `wiki/sources`.
- [ ] Re-run source library tests.

### Task 3: Hierarchical Source Library UI

**Files:**
- Modify: `KnowYou/UI/MyWiki/MyWikiSourceLibraryView.swift`
- Modify: `KnowYou/UI/MyWiki/MyWikiPanel.swift`

- [ ] Change view init inputs to include `sourceVault` and `importedDocuments` with defaults for compatibility.
- [ ] Replace flat `[MyWikiSourceItem]` state with `MyWikiSourceCatalogSnapshot`, query, status filter, and status message.
- [ ] Render search, filter, bulk actions, directory rows, and source rows from `MyWikiSourceLibraryPresentation`.
- [ ] Implement source and directory selection mutations and save with `MyWikiSourceCatalogStore`.
- [ ] Reload catalog after imports and keep import affordances unchanged.

### Task 4: Verification And Commit

**Files:**
- All changed files

- [ ] Run `xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/MyWikiSourceLibraryTests -only-testing:KnowYouTests/MyWikiSourceLibraryPresentationTests`.
- [ ] Run `xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/MyWikiSourceLibraryPresentationTests`.
- [ ] Run `git diff --check`.
- [ ] If time allows, run `xcodebuild build -scheme KnowYou -destination 'platform=macOS'`.
- [ ] Review `git diff`, stage only Task 5 files, commit `Show hierarchical My Wiki source catalog`, and do not push.
