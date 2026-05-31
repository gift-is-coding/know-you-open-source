# Onboarding History Bootstrap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the first onboarding bootstrap from today+yesterday with a confirmed local-only 3-day generation flow.

**Architecture:** Add a small onboarding confirmation copy model, expand AppState bootstrap day planning to 3 days, and track lightweight per-day progress for the existing main-window notice. Keep generation on the existing serial refresh pipeline and reuse existing 50-event chunking.

**Tech Stack:** SwiftUI, Observation/AppState, XCTest, existing KnowYou refresh pipeline.

---

### Task 1: Red Tests

- [x] Update onboarding progress tests to expect three bootstrap day keys.
- [x] Update content/layout tests to expect 3-day and local-only copy.
- [x] Update notice tests to expect progress-aware presentation.
- [x] Update main-window tests to expect 3-day serial generation, progress, and completion notification behavior.

### Task 2: App State

- [x] Add `OnboardingBootstrapProgress`.
- [x] Generate three bootstrap days.
- [x] Update progress before each active day and after completion.
- [x] Update notice and completion notification copy.

### Task 3: Onboarding UI

- [x] Add confirmation copy model with local-only text.
- [x] Present confirmation dialog before completing onboarding.
- [x] Update generating step copy.

### Task 4: Docs And Verification

- [x] Update requirements and architecture docs.
- [x] Run focused onboarding/bootstrap tests.
- [x] Run full `xcodebuild test` and `xcodebuild build`.
