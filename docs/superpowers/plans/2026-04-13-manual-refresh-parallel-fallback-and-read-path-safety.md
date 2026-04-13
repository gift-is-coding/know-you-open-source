# Manual Refresh Parallel Fallback And Read-Path Safety Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Remove legacy read-path rewrites, keep fresh `fullRecovery` output normalized, and change manual refresh retries from serial fallback to primary-first plus parallel green-engine fallback.

**Architecture:** Update `AppState` refresh orchestration, make CLI attempts cancellable, lock behavior with regression tests, and synchronize product docs.

**Tech Stack:** Swift 6, XCTest, `xcodebuild`

---

## Files Changed

- Modify: `KnowYou/App/AppState.swift`
- Modify: `KnowYou/Services/Summary/CLISummarizer.swift`
- Modify: `KnowYouTests/MainWindowViewModelTests.swift`
- Modify: `docs/architecture.md`
- Modify: `docs/requirements-spec.md`
- Create: `docs/superpowers/specs/2026-04-13-manual-refresh-parallel-fallback-and-read-path-safety.md`
- Create: `docs/superpowers/plans/2026-04-13-manual-refresh-parallel-fallback-and-read-path-safety.md`

## Task 1: Remove Read-Path Writes

- [x] Remove startup-time legacy story migration
- [x] Remove date-load migration/writeback
- [x] Keep legacy stories readable without rewriting them on load

## Task 2: Normalize Only On Fresh Writes

- [x] Ensure `generateDailyNote(for:)` delegates to the unified refresh pipeline
- [x] Make `fullRecovery` use the global prompt override when present
- [x] Normalize parsed `fullRecovery` stories before persistence

## Task 3: Add Parallel Manual Fallback

- [x] Remove the early full-recovery guard that blocked fallback engines
- [x] Keep the default engine as the first manual attempt
- [x] Run remaining green fallback engines in parallel after primary failure
- [x] Cancel losing attempts once one fallback succeeds
- [x] Keep automation single-engine

## Task 4: Lock The Behavior With Tests

- [x] Add regression coverage proving `generateDailyNote(for:)` respects incremental mode
- [x] Add regression coverage proving manual fallback engines race in parallel and losers are cancelled
- [x] Add regression coverage proving full recovery uses prompt override and normalized persistence
- [x] Add regression coverage proving load/init paths no longer migrate legacy stories

## Task 5: Sync Docs And Verify

- [x] Update `docs/architecture.md`
- [x] Update `docs/requirements-spec.md`
- [x] Save spec + plan artifacts for this behavior change
- [x] Run targeted test slice
- [ ] Run `xcodebuild test -scheme KnowYou -destination 'platform=macOS'`
- [x] Run `xcodebuild build -scheme KnowYou -destination 'platform=macOS'`
