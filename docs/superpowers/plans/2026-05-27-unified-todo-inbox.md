# Unified Todo Inbox Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a native Todo inbox that deduplicates daily diary to-do candidates, supports manual promotion and direct manual entry, and conservatively auto-completes open items from later evidence.

**Architecture:** Keep daily diaries as narrative artifacts and persist canonical task state in `Vault/Todo.md`, with SQLite `todo_items` retained for first-run migration and compatibility. Add a small todo domain/store layer, deterministic candidate parsing and matching helpers, optional LLM-backed reconciliation/completion prompts, then wire a sidebar Todo page, direct entry, and diary-row actions into `AppState`.

**Tech Stack:** Swift, SwiftUI, GRDB, XCTest, existing `SummaryGenerating` engines, Xcode macOS test/build commands

---

### Task 1: Persistence And Domain

- [ ] Add `UnifiedTodoItem`, status, promotion kind, and completion kind domain types.
- [ ] Add a `todo_items` migration and `TodoStore` APIs for create, fetch ordered list, find by normalized title, manual complete, evidence complete, and merge source evidence.
- [ ] Add Markdown-backed `TodoStore` behavior that reads/writes `Vault/Todo.md`, embeds hidden `knowyou:todo` metadata, and seeds the Markdown file from existing SQLite rows when the document is missing.
- [ ] Add `TodoStoreTests` proving migration, dedupe, open-before-completed ordering, manual completion, and evidence completion.

### Task 2: Diary Candidate Semantics

- [ ] Update `DailyMarkdownComposer` prompts so the diary to-do section allows zero items, caps at three concrete items, rejects vague suggestions, and avoids completed or duplicate tasks.
- [ ] Add tests in `DailyMarkdownComposerTests` for the new prompt rules and incremental no-duplicate guidance.
- [ ] Add candidate parsing helpers that extract Markdown task rows from the selected daily story with stable source event IDs.

### Task 3: Reconciliation And Completion

- [ ] Add `TodoReconciler` to compare candidates with existing todo items and return `create`, `merge`, or `ignore`.
- [ ] Add deterministic high-confidence guards for exact/normalized duplicate titles and already-completed titles.
- [ ] Add optional LLM JSON parsing for semantic reconciliation, but skip auto-promotion when the engine is unavailable or the response is invalid.
- [ ] Add `TodoCompletionSweep` to mark open items complete only when later evidence clearly proves completion.
- [ ] Cover create, merge, ignore, invalid-LLM, and evidence-completion paths with focused tests.

### Task 4: AppState And UI

- [ ] Add `MainContentSelection.todo`, Todo state, and AppState actions to open Todo, refresh todo items, manually add a diary candidate, manually complete, and run post-refresh todo processing.
- [ ] Add a `TodoInboxView` with direct text entry, open items first, and completed items last.
- [ ] Add a Todo sidebar row with open-count badge.
- [ ] Add diary task-row presentation so candidates can show `Add to Todo` or `In Todo`.
- [ ] Add presentation tests for sidebar routing, Todo ordering, and diary candidate state.

### Task 5: Verification And Finish

- [ ] Run targeted red/green slices after each layer.
- [ ] Run `xcodebuild test -scheme KnowYou -destination 'platform=macOS'`.
- [ ] Run `xcodebuild build -scheme KnowYou -destination 'platform=macOS'`.
- [ ] Review `git diff`, update `docs/architecture.md` and `docs/requirements-spec.md` if the final public behavior differs from the spec.
- [ ] Commit locally; do not push.
