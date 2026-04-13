# Fallback Preservation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prevent fallback refresh output from overwriting an existing successful model-generated daily story.

**Architecture:** Keep the existing daily generation pipeline, but add a persistence guard after story generation and before file writes. The guard compares the existing persisted story with the newly generated one and blocks only the downgrade case.

**Tech Stack:** Swift, XCTest, GRDB, local file persistence

---

### Task 1: Lock the downgrade regression with tests

**Files:**
- Modify: `KnowYouTests/MainWindowViewModelTests.swift`

- [ ] Add a focused regression test proving fallback still persists when there is no existing successful story.
- [ ] Add a focused regression test proving an existing `generationMode == model` story is preserved when summarization falls back.
- [ ] Run the two targeted tests and confirm the new preservation test fails before implementation.

### Task 2: Add the persistence guard

**Files:**
- Modify: `KnowYou/App/AppState.swift`

- [ ] Load the existing persisted story inside the daily generation pipeline before writing artifacts.
- [ ] Add a small helper that returns true only for the downgrade case: existing story is `.model`, new story is not `.model`.
- [ ] When the helper returns true, skip all artifact writes, keep the existing selected presentation, mark the run failed, and surface a failure status message explaining that the existing model story was preserved after fallback.
- [ ] Re-run the targeted tests and confirm both pass.

### Task 3: Sync behavior docs

**Files:**
- Modify: `docs/architecture.md`
- Modify: `docs/requirements-spec.md`
- Create: `docs/superpowers/specs/2026-04-13-fallback-preservation-design.md`
- Create: `docs/superpowers/plans/2026-04-13-fallback-preservation.md`

- [ ] Document the new invariant that fallback cannot downgrade an existing successful model story.
- [ ] Keep the docs scoped to current behavior; do not expand the refresh design beyond this rule.

### Task 4: Verify end-to-end

**Files:**
- Modify: none

- [ ] Run the full test command: `xcodebuild test -scheme KnowYou -destination 'platform=macOS'`
- [ ] Run the full build command: `xcodebuild build -scheme KnowYou -destination 'platform=macOS'`
- [ ] Review the results and report only what the fresh command output proves.
