# Details Paragraph Splitting Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Make `# Details` selectable per workstream by keeping the existing paragraph-level source-link model and changing generation plus one-time legacy-story migration.

**Architecture:** Update `DailyMarkdownComposer` prompt and normalization behavior, apply normalization in `AppState` load/generation paths, extend regression coverage, and synchronize product docs.

**Tech Stack:** Swift 6, XCTest, `xcodebuild`

---

## Files Changed

- Modify: `KnowYou/Services/Composer/DailyMarkdownComposer.swift`
- Modify: `KnowYou/Services/Summary/CLISummarizer.swift`
- Modify: `KnowYou/App/AppState.swift`
- Modify: `KnowYouTests/CLISummarizerTests.swift`
- Modify: `KnowYouTests/DailyMarkdownComposerTests.swift`
- Modify: `KnowYouTests/MainWindowViewModelTests.swift`
- Modify: `KnowYouTests/DailyMarkdownViewTests.swift`
- Modify: `docs/architecture.md`
- Modify: `docs/requirements-spec.md`
- Create: `docs/superpowers/specs/2026-04-13-details-paragraph-splitting-design.md`
- Create: `docs/superpowers/plans/2026-04-13-details-paragraph-splitting.md`

## Task 1: Lock In The New Contract

**Files:**

- Modify: `KnowYou/Services/Composer/DailyMarkdownComposer.swift`
- Modify: `KnowYou/Services/Summary/CLISummarizer.swift`

- [x] Remove the hard paragraph-count cap from the structured story schema
- [x] Update the canonical prompt so each Details workstream becomes its own paragraph
- [x] Keep the prompt qualitative: reasonable grouping, no hard 6-10 limit

## Task 2: Normalize Legacy Stories

**Files:**

- Modify: `KnowYou/Services/Composer/DailyMarkdownComposer.swift`
- Modify: `KnowYou/App/AppState.swift`

- [x] Add normalization that splits legacy single-paragraph Details blocks into per-workstream paragraphs
- [x] Keep derived paragraph ids stable
- [x] Apply normalization when writing a newly generated story and migrate legacy stored stories on load
- [x] Narrow legacy subsection source ids heuristically, with fallback to the original full source list

## Task 3: Add Regression Coverage

**Files:**

- Modify: `KnowYouTests/CLISummarizerTests.swift`
- Modify: `KnowYouTests/DailyMarkdownComposerTests.swift`
- Modify: `KnowYouTests/MainWindowViewModelTests.swift`
- Modify: `KnowYouTests/DailyMarkdownViewTests.swift`

- [x] Add a schema regression showing multi-paragraph Details JSON is accepted
- [x] Add composer tests for prompt wording, legacy split behavior, source narrowing, and markdown composition
- [x] Add app-state coverage showing old Details blocks become separately selectable paragraphs
- [x] Rename the renderer regression so it describes legacy markdown preservation rather than product-level single-paragraph behavior

## Task 4: Sync Product Docs

**Files:**

- Modify: `docs/architecture.md`
- Modify: `docs/requirements-spec.md`
- Create: `docs/superpowers/specs/2026-04-13-details-paragraph-splitting-design.md`
- Create: `docs/superpowers/plans/2026-04-13-details-paragraph-splitting.md`

- [x] Record the new Details paragraph contract
- [x] Document one-time legacy migration and paragraph-level source linking
- [x] Save a matching spec and implementation plan artifact

## Task 5: Run Verification

**Files:**

- Modify: none

- [x] Run targeted tests for the touched story and reader areas
- [x] Run `xcodebuild test -scheme KnowYou -destination 'platform=macOS'`
- [x] Run `xcodebuild build -scheme KnowYou -destination 'platform=macOS'`
