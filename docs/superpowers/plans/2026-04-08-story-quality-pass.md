# Story Quality Pass Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Improve fallback story synthesis so noisy days become a few thematic story paragraphs instead of a long loose-fragment dump.

**Architecture:** Keep the existing `DailyStory` and three-column reader intact, and change only the fallback composition logic in `DailyMarkdownComposer` plus targeted regression coverage. Theme classification and grouped loose-fragment paragraphs should remain deterministic and source-linked.

**Tech Stack:** Swift 6, XCTest, `xcodebuild`

---

## Files Changed

- Modify: `KnowYou/Services/Composer/DailyMarkdownComposer.swift`
- Modify: `KnowYouTests/DailyMarkdownComposerTests.swift`
- Create: `docs/superpowers/specs/2026-04-08-story-quality-pass.md`
- Create: `docs/superpowers/plans/2026-04-08-story-quality-pass.md`

## Task 1: Add A Failing Noisy-Day Regression Test

**Files:**

- Modify: `KnowYouTests/DailyMarkdownComposerTests.swift`

- [x] Add a test that constructs a noisy mixed-context day
- [x] Assert that loose fragments are compressed into a small number of grouped paragraphs
- [x] Assert that verification noise and reference links are summarized into grouped paragraphs
- [x] Run the targeted test and confirm it fails before implementation

## Task 2: Implement Theme-Aware Fallback Compression

**Files:**

- Modify: `KnowYou/Services/Composer/DailyMarkdownComposer.swift`

- [x] Add fallback theme classification for references, verification, logistics, communication, and context
- [x] Stop generating one loose-fragment paragraph per leftover event
- [x] Group leftovers by theme and merge to a capped number of paragraphs
- [x] Keep grouped paragraph source ids intact

## Task 3: Re-Verify Composer Behavior

**Files:**

- Modify: `KnowYouTests/DailyMarkdownComposerTests.swift`
- Modify: `KnowYou/Services/Composer/DailyMarkdownComposer.swift`

- [x] Run `DailyMarkdownComposerTests`
- [x] Confirm the new regression test passes
- [x] Confirm existing composer tests still pass

## Task 4: Run Full Verification

**Files:**

- Modify: none

- [ ] Run `xcodebuild test -scheme KnowYou -destination 'platform=macOS'`
- [ ] Run `xcodebuild build -scheme KnowYou -destination 'platform=macOS'`

## Notes

- This pass intentionally does not change the UI surface.
- This pass raises story quality specifically for the no-summarizer or parse-failure path.
