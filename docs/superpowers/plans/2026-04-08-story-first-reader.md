# Story-First Reader Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans if this work is resumed in a later session. This plan reflects the implemented state in the repo.

**Goal:** Replace the raw-Markdown-first reader with a story-first daily reader that preserves direct access to underlying source events.

**Architecture:** Extend the existing macOS SwiftUI app with a structured `DailyStory` artifact, persist `*.story.json` alongside daily Markdown, render the main window as a three-column reader, and keep paragraph-level source links in app state.

**Tech Stack:** Swift 6, SwiftUI, GRDB, XCTest, `xcodebuild`

---

## Files Changed

- Modify: `KnowYou/Domain/DailyNote.swift`
- Modify: `KnowYou/Services/Composer/DailyMarkdownComposer.swift`
- Modify: `KnowYou/App/AppEnvironment.swift`
- Modify: `KnowYou/App/AppState.swift`
- Modify: `KnowYou/UI/MainWindowView.swift`
- Modify: `KnowYou/UI/Sidebar/DateSidebarView.swift`
- Modify: `KnowYou/UI/Reader/DailyMarkdownView.swift`
- Modify: `KnowYouTests/MainWindowViewModelTests.swift`
- Modify: `KnowYouTests/DailyMarkdownComposerTests.swift`
- Create: `docs/superpowers/specs/2026-04-08-story-first-reader.md`
- Create: `docs/superpowers/plans/2026-04-08-story-first-reader.md`

## Task 1: Introduce Structured Story Artifacts

**Files:**

- Modify: `KnowYou/Domain/DailyNote.swift`
- Modify: `KnowYou/App/AppEnvironment.swift`

- [x] Add `DailyStory`, `DailyStorySection`, and `DailyStoryParagraph` domain types
- [x] Persist `YYYY-MM-DD.story.json` alongside `YYYY-MM-DD.md`
- [x] Load existing story sidecars when present

## Task 2: Replace Raw Summary Generation With Story Generation

**Files:**

- Modify: `KnowYou/Services/Composer/DailyMarkdownComposer.swift`
- Modify: `KnowYou/App/AppState.swift`

- [x] Add a fixed four-section story template
- [x] Generate strict JSON prompts for summarizer-backed story output
- [x] Parse structured story JSON into typed models
- [x] Add deterministic local fallback story generation when parsing or summarization fails
- [x] Keep Markdown export as a derived output instead of the primary UI representation

## Task 3: Upgrade Reader UX To Three Columns

**Files:**

- Modify: `KnowYou/UI/MainWindowView.swift`
- Modify: `KnowYou/UI/Reader/DailyMarkdownView.swift`
- Modify: `KnowYou/UI/Sidebar/DateSidebarView.swift`

- [x] Change sidebar labels to `MM-dd EEE`
- [x] Render story sections and paragraph cards in the center pane
- [x] Make paragraph cards the selection affordance
- [x] Add a source detail pane on the right
- [x] Add collapsed `View All Sources` disclosure for the full day
- [x] Wire keyboard up/down movement to paragraph navigation
- [x] Make the toolbar refresh button regenerate the selected day

## Task 4: Extend App State For Story Selection

**Files:**

- Modify: `KnowYou/App/AppState.swift`

- [x] Track selected story and selected paragraph id
- [x] Track linked source events for the selected paragraph
- [x] Track all source events for the selected day
- [x] Load story presentation whenever the selected date changes
- [x] Keep story and source panes synchronized after regeneration

## Task 5: Add Regression Coverage

**Files:**

- Modify: `KnowYouTests/MainWindowViewModelTests.swift`
- Modify: `KnowYouTests/DailyMarkdownComposerTests.swift`

- [x] Verify story-first Markdown export shape
- [x] Verify fallback stories keep source event ids
- [x] Verify daily regeneration persists `.story.json`
- [x] Verify paragraph selection updates the visible source evidence

## Verification

- [x] Run: `xcodebuild test -scheme KnowYou -destination 'platform=macOS'`
- [x] Run: `xcodebuild build -scheme KnowYou -destination 'platform=macOS'`

## Notes

- The implementation intentionally keeps Markdown on disk for export and compatibility, but the reader no longer treats raw Markdown as the primary presentation surface.
- Historical days without story sidecars are still readable via local fallback generation.
