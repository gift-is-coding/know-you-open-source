# External Source Prompt Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make external platform sources prompt-driven and local-directory-backed while fixing Add Source sidebar and source-list duplication.

**Architecture:** Keep the existing Knowledge Imports persistence pipeline, but route Feishu/Notion/Google Drive through a local file scanner when they have a `sourcePath`. Add Source produces platform prompts and local source metadata only; remote credentials stay outside KnowYou. The sidebar becomes a flat source list where connector roots expand into path-derived document trees.

**Tech Stack:** SwiftUI, AppState, existing Knowledge Import models, GRDB-backed imported document index, XCTest.

---

### Task 1: Prompt-backed Add Source

- [x] Add presentation tests for a single Sources list, no Add Connector header, no token form, and Generate Prompt platform cards.
- [x] Implement prompt presentation state and UI in `ConnectorsPanel.swift`.
- [x] Add source metadata creation for prompt-backed platform sources in `MainWindowView.swift`.

### Task 2: Local Directory Platform Imports

- [x] Add tests proving platform sources scan local Markdown directories without tokens.
- [x] Add a file-backed platform connector that wraps `FileKnowledgeSnapshotScanner` with the platform connector id.
- [x] Route Feishu/Notion/Google Drive instances with `sourcePath` through the file-backed connector in `AppState`.

### Task 3: Sidebar Tree

- [x] Add sidebar presentation tests for non-collapsible Add Source and path-derived connector document trees.
- [x] Pass imported documents into `DateSidebarView`.
- [x] Render connector roots as expandable tree rows and document leaves as `.knowledgeDocument` selections.

### Task 4: Remove Duplicate Entrypoints

- [x] Remove the left gear-menu `Connectors` action.
- [x] Keep Daily Memory Export out of Add Source.
- [x] Update docs and focused tests.

### Task 5: Verification

- [x] Run focused XCTest slices.
- [x] Run `xcodebuild test -scheme KnowYou -destination 'platform=macOS'`.
- [x] Run `xcodebuild build -scheme KnowYou -destination 'platform=macOS'`.
- [x] Run `./scripts/build-release.sh`.
- [x] Open fresh `build/release/KnowYou.app` and verify the running process path.
