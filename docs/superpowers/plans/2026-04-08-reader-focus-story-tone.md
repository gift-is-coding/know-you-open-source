# Reader Focus and Story Tone Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stabilize keyboard navigation between the date list and story content, warm up daily story output, and clarify notification diagnostics in-product.

**Architecture:** Add an explicit reader-focus state and per-day paragraph memory to `AppState`, then make the sidebar and story column route keyboard commands through that shared state. Update `DailyMarkdownComposer` to request a gentler diary voice and emit slightly richer Markdown, while expanding app status text to explain clipboard and notification ingestion behavior.

**Tech Stack:** SwiftUI, Observation, XCTest, macOS command handling

---

### Task 1: Lock reader-state behavior with tests

**Files:**
- Modify: `KnowYouTests/MainWindowViewModelTests.swift`

- [ ] Add failing tests for:
  - story focus returning to the date list on `Left`
  - story focus returning to the date list on `Escape`
  - date-list `Right` restoring the last selected paragraph for that day
  - per-day paragraph memory surviving date switches

- [ ] Run: `xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/MainWindowViewModelTests`

### Task 2: Lock story prompt and Markdown behavior with tests

**Files:**
- Modify: `KnowYouTests/DailyMarkdownComposerTests.swift`

- [ ] Add failing tests for:
  - prompt guidance allowing natural paragraph counts
  - prompt guidance encouraging a warmer diary tone
  - composed Markdown including light structure improvements
  - diagnostics text explaining clipboard and notification provenance

- [ ] Run: `xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/DailyMarkdownComposerTests`

### Task 3: Implement reader focus state

**Files:**
- Modify: `KnowYou/App/AppState.swift`
- Modify: `KnowYou/UI/MainWindowView.swift`
- Modify: `KnowYou/UI/Sidebar/DateSidebarView.swift`
- Modify: `KnowYou/UI/Reader/DailyMarkdownView.swift`

- [ ] Add the shared focus enum and paragraph-memory storage in `AppState`.
- [ ] Implement keyboard-routing helpers for up/down/left/right and escape behavior.
- [ ] Restore remembered paragraphs per day when re-entering story content.
- [ ] Add visible focused-column styling and bind SwiftUI focus to the shared state.

### Task 4: Implement story-tone and Markdown updates

**Files:**
- Modify: `KnowYou/Services/Composer/DailyMarkdownComposer.swift`
- Modify: `KnowYou/UI/Reader/DailyMarkdownView.swift`

- [ ] Revise the story prompt to request natural paragraphing, stronger transitions, and light inline Markdown.
- [ ] Update composed Markdown spacing and separators without changing the structured story schema.
- [ ] Render paragraph text as Markdown in the story reader so emphasis and light formatting are visible.

### Task 5: Implement notification diagnostics

**Files:**
- Modify: `KnowYou/App/AppState.swift`
- Modify: `KnowYou/UI/Settings/SettingsView.swift`

- [ ] Add concise diagnostic strings explaining the clipboard source and notification import source.
- [ ] Differentiate missing database, permission issues, and machine-dependent non-persistence in status copy.
- [ ] Keep this task limited to messaging and diagnostics, not a new ingestion path.

### Task 6: Verify the full change

**Files:**
- Modify as needed from earlier tasks only

- [ ] Run focused tests while iterating.
- [ ] Run: `xcodebuild test -scheme KnowYou -destination 'platform=macOS'`
- [ ] Run: `xcodebuild build -scheme KnowYou -destination 'platform=macOS'`
