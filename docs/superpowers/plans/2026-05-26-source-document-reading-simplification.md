# Source Document Reading Simplification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the duplicate source document index and make source leaves open a rendered Markdown preview.

**Architecture:** Use the sidebar as the only source tree. Keep source scanning on `Add Source`; make source document reading a pure preview state.

**Tech Stack:** SwiftUI, XCTest, existing `DailyMarkdownRenderer`.

---

### Task 1: Lock Reading Presentation Behavior

**Files:**
- Modify: `KnowYouTests/KnowledgeSourceContentViewTests.swift`

- [x] Write failing tests that assert source reading has no document list, no `Refresh`, no `Configure`, no status message, and strips frontmatter before preview.
- [x] Run the targeted tests and verify they fail against the old implementation.

### Task 2: Simplify Source Preview UI

**Files:**
- Modify: `KnowYou/UI/Knowledge/KnowledgeSourceContentView.swift`
- Modify: `KnowYou/UI/Reader/DailyMarkdownView.swift`

- [x] Replace the main-pane document browser with a single Markdown preview.
- [x] Reuse the existing Markdown block renderer through a shared `MarkdownPreviewContent` view.
- [x] Strip YAML frontmatter before rendering source documents.

### Task 3: Fix Source Selection Semantics

**Files:**
- Modify: `KnowYou/App/AppState.swift`
- Modify: `KnowYou/UI/MainWindowView.swift`
- Modify: `KnowYouTests/MainWindowViewModelTests.swift`

- [x] Make connector root selection clear selected document content instead of opening the first document.
- [x] Keep selected document stable across refresh when the user selected a leaf.
- [x] Hide the third detail pane for source reading states.

### Task 4: Verify

**Files:**
- Modify: `docs/architecture.md`
- Modify: `docs/requirements-spec.md`

- [x] Update product docs to make `Refresh` an Add Source management action only.
- [x] Run focused source-reading tests.
- [x] Run full test, build, release build, and open the fresh release app without clearing login state.
