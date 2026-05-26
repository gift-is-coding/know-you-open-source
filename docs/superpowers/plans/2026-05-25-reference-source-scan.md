# Reference Source Scan Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Add Source document sources reference local files instead of copying them, and update UI language to Link/Scan/Refresh.

**Architecture:** Reuse the existing `KnowledgeImportCoordinator` and SQLite document rows, but add a reference-storage path for file-backed snapshots. File-backed connectors continue to enumerate Markdown/TXT files and emit snapshots with `sourcePath`; the store writes metadata and points `localContentPath` at the source file.

**Tech Stack:** Swift, SwiftUI, XCTest, GRDB-backed SQLite, existing KnowYou knowledge source services.

---

### Task 1: Reference-Only Storage Tests

**Files:**
- Modify: `KnowYouTests/KnowledgeImportStoreTests.swift`
- Modify: `KnowYouTests/KnowledgeImportCoordinatorTests.swift`

- [ ] **Step 1: Write failing tests**

Add tests proving file-backed snapshots store `localContentPath` as the original `sourcePath`, do not create copied `content.md`, and still upsert visible documents.

- [ ] **Step 2: Run targeted tests to verify RED**

Run:

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/KnowledgeImportStoreTests/testSaveFileBackedSnapshotReferencesSourceFileWithoutCopyingContent -only-testing:KnowYouTests/KnowledgeImportCoordinatorTests/testFileBackedScanReferencesOriginalSourceFile
```

Expected: fails because snapshots do not have reference storage and store writes `content.md`.

- [ ] **Step 3: Implement reference storage**

Add a storage mode to `KnowledgeImportSnapshot`, default existing tests to copy mode, and have `FileKnowledgeSnapshotScanner` emit reference mode. Update `KnowledgeImportStore.saveWithResult` to write metadata only and set `localContentPath` to `sourcePath` for reference mode.

- [ ] **Step 4: Run targeted tests to verify GREEN**

Run the same targeted test command. Expected: pass.

### Task 2: Add Source UI Wording Tests

**Files:**
- Modify: `KnowYouTests/ConnectorsPanelTests.swift`
- Modify: `KnowYouTests/KnowledgeSourceContentViewTests.swift`

- [ ] **Step 1: Write failing tests**

Update expectations so configured local/Obsidian cards show `Linked` and `Refresh`, prompt-backed empty directories show `Needs first scan`, source pages show `Refresh`, and UI copy says files are linked/read in place.

- [ ] **Step 2: Run targeted tests to verify RED**

Run:

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/ConnectorsPanelTests -only-testing:KnowYouTests/KnowledgeSourceContentViewTests
```

Expected: fails on old `Connected`, `Sync Now`, and copied-storage text.

- [ ] **Step 3: Implement UI copy and actions**

Update `ConnectorsPanel.swift`, `KnowledgeSourceContentView.swift`, and `MainWindowView.swift` strings/actions from Import/Sync copy to Link/Scan/Refresh reference semantics.

- [ ] **Step 4: Run targeted tests to verify GREEN**

Run the same targeted UI test command. Expected: pass.

### Task 3: Docs and Verification

**Files:**
- Modify: `docs/requirements-spec.md`
- Modify: `docs/architecture.md`

- [ ] **Step 1: Update product docs**

Replace local source copy/import claims with reference-source scan wording. Keep Daily Memory Export documented as a separate export job.

- [ ] **Step 2: Run focused knowledge source test slice**

Run:

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/KnowledgeImportStoreTests -only-testing:KnowYouTests/KnowledgeImportCoordinatorTests -only-testing:KnowYouTests/ConnectorsPanelTests -only-testing:KnowYouTests/KnowledgeSourceContentViewTests -only-testing:KnowYouTests/DailyMarkdownViewTests
```

Expected: pass.

- [ ] **Step 3: Run full verification**

Run:

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS'
xcodebuild build -scheme KnowYou -destination 'platform=macOS'
./scripts/build-release.sh
```

Expected: all pass. Open the fresh release app without clearing state and verify the launched process path points at `build/release/KnowYou.app`.
