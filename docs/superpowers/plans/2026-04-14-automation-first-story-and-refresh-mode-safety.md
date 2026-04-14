# Automation First Story And Refresh Mode Safety Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Let automation create the first story for today when possible, expose engine-configuration failures clearly, avoid refresh-mode misclassification on story load errors, and surface refresh-log write failures non-disruptively.

**Architecture:** Extend the today automation planner, harden `AppState` refresh-mode resolution, add UI state for refresh-log notices, and lock behavior with focused tests.

**Tech Stack:** Swift 6, SwiftUI, XCTest, `xcodebuild`

---

## Files Changed

- Modify: `KnowYou/App/AppState.swift`
- Modify: `KnowYou/Services/Scheduling/DailyAutomationPlanner.swift`
- Modify: `KnowYou/UI/MainWindowView.swift`
- Modify: `KnowYou/UI/Reader/DailyMarkdownView.swift`
- Modify: `KnowYouTests/DailyAutomationPlannerTests.swift`
- Modify: `KnowYouTests/MainWindowViewModelTests.swift`
- Modify: `docs/architecture.md`
- Modify: `docs/requirements-spec.md`
- Create: `docs/superpowers/specs/2026-04-14-automation-first-story-and-refresh-mode-safety.md`
- Create: `docs/superpowers/plans/2026-04-14-automation-first-story-and-refresh-mode-safety.md`

## Task 1: Today Automation Action

- [x] Replace the today automation boolean with an explicit action model
- [x] Allow automation to run full recovery for today when no model story exists and a verified engine is available
- [x] Keep automation today-only and preserve the “no engine, no fallback write” rule

## Task 2: Refresh Mode Safety

- [x] Stop using `try?` to collapse story-load failure into `fullRecovery`
- [x] Fail refresh explicitly when an existing story file cannot be loaded
- [x] Update no-engine full-recovery messaging to point users toward engine configuration

## Task 3: Low-Key Log Failure Notice

- [x] Track refresh-log persistence failures per day
- [x] Surface the notice below the refresh control in the reader
- [x] Keep log-write failure non-fatal for the refresh itself

## Task 4: Prompt Override Cleanup

- [x] Trim global diary prompt override input before persistence

## Task 5: Tests And Verification

- [x] Add focused tests for today automation full recovery and no-engine prompting
- [x] Add focused tests for refresh-mode load failure handling
- [x] Add focused tests for refresh-log notice and prompt trimming
- [x] Run targeted test slice
- [x] Run `xcodebuild test -scheme KnowYou -destination 'platform=macOS'`
- [x] Run `xcodebuild build -scheme KnowYou -destination 'platform=macOS'`
