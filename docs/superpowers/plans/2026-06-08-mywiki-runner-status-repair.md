# MyWiki Runner Status Repair Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix MyWiki runner availability diagnosis and make update timestamps distinguish successful ingest from failed attempts.

**Architecture:** Keep the product runner model unchanged: `KnowYou.app` owns a bundled `MyWikiRunner` directory and bridges LLM calls to the existing Diary Engine. Presentation logic stays in `MyWikiDigestSchedulePresentation`; runner validation stays in `MyWikiRunnerBundle` and `MyWikiPipelineBridge`.

**Tech Stack:** SwiftUI, XCTest, Bash packaging scripts, bundled Node runner.

---

### Task 1: Status Presentation Tests

**Files:**
- Modify: `KnowYouTests/KnowledgeOntologyPanelTests.swift`
- Modify: `KnowYou/UI/MyWiki/MyWikiModels.swift`

- [x] Add failing tests that a failed ingest with `updatedAt` shows `Last successful update` as `Not updated yet` and surfaces `Last attempt failed`.
- [x] Add failing tests that a succeeded ingest still shows the success time.
- [x] Implement minimal presentation changes.
- [x] Run `xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/KnowledgeOntologyPanelTests`.

### Task 2: Runner Diagnostic Tests

**Files:**
- Modify: `KnowYouTests/MyWikiPipelineBridgeTests.swift`
- Modify: `KnowYou/Services/MyWiki/MyWikiRunnerBundle.swift`
- Modify: `KnowYou/UI/MyWiki/MyWikiPanel.swift`

- [x] Add failing tests for missing runner status copy that explains the app bundle is missing its built-in runner.
- [x] Make missing runner diagnostics specific without reintroducing development `npm`.
- [x] Run `xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/MyWikiPipelineBridgeTests`.

### Task 3: Real Runner Verification

**Files:**
- Verify: `scripts/build-mywiki-runner.sh`
- Verify: `scripts/test-mywiki-runner-package.sh`
- Verify: `scripts/verify-mywiki-real-diary.sh`

- [x] Run runner package verification.
- [x] Run three-Diary ontology verification.
- [x] If verification fails, fix only the runner bridge/package path needed for the real diary run.

### Task 4: Onboarding Titlebar Engine Verification

**Files:**
- Modify: `KnowYou/App/AppState.swift`
- Modify: `KnowYou/UI/Onboarding/OnboardingView.swift`
- Modify: `KnowYou/UI/Reader/DiaryEngineSelectorButton.swift`
- Modify: `KnowYouTests/OnboardingProgressTests.swift`
- Modify: `KnowYouTests/OnboardingViewLayoutTests.swift`

- [x] Add tests that the titlebar Diary Engine button advances onboarding from `enginePrompt` to `engineSetup`.
- [x] Add tests that the engine coachmark falls back to the right side of the titlebar area when the AppKit-hosted selector cannot publish a SwiftUI anchor.
- [x] Implement the titlebar handoff without adding a duplicate in-page or bottom toolbar engine selector.
- [x] Run `xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/OnboardingProgressTests -only-testing:KnowYouTests/OnboardingViewLayoutTests`.

### Task 5: Full Verification

**Files:**
- Verify: project build and tests

- [x] Run `xcodebuild build -scheme KnowYou -destination 'platform=macOS'`.
- [x] Run `xcodebuild test -scheme KnowYou -destination 'platform=macOS'`.
- [x] Report exact evidence, including whether real Diary fixture generated source/entity/concept outputs.
