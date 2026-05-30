# Diary Engine Recovery Nudge Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a persistent toolbar and popover nudge for missing or unhealthy Diary Engine state after onboarding.

**Architecture:** Add a small presentation model beside the existing diary engine selector UI, then wire `MainWindowView` and `DiaryEnginePanel` to it. The model is derived from `defaultEngine` and `engineStatuses`, so dismissing or opening UI never clears the unresolved state.

**Tech Stack:** Swift, SwiftUI, XCTest, existing `DiaryEngine`, `EngineRuntimeStatus`, `MainWindowView`, and `DiaryEnginePanel`.

---

## File Structure

- Modify: `KnowYou/UI/Reader/DiaryEngineSelectorButton.swift`
  - Add `DiaryEngineRecoveryNudgePresentation` and `DiaryEngineRecoveryNudgeKind`.
- Modify: `KnowYou/UI/Reader/DiaryEnginePanel.swift`
  - Add optional `recoveryNudge` input and render a top banner when present.
- Modify: `KnowYou/UI/MainWindowView.swift`
  - Compute recovery presentation and use it for toolbar title, state, emphasis, and popover.
- Modify: `KnowYouTests/MainWindowViewModelTests.swift`
  - Add focused tests for missing, failed, resolved, and stable unresolved nudge behavior.
- Add: `docs/superpowers/specs/2026-05-30-diary-engine-recovery-nudge-design.md`
- Add: `docs/superpowers/plans/2026-05-30-diary-engine-recovery-nudge.md`
- Add: `docs/superpowers/mockups/2026-05-30-diary-engine-recovery-nudge.svg`
- Add: `docs/superpowers/mockups/2026-05-30-diary-engine-recovery-nudge.png`

## Task 1: Add Failing Presentation Tests

**Files:**
- Modify: `KnowYouTests/MainWindowViewModelTests.swift`

- [ ] **Step 1: Write tests for recovery nudge state**

Add tests near the existing engine-selection tests:

```swift
func testEngineRecoveryNudgeRequestsSetupWhenDefaultEngineIsNone() {
    let nudge = DiaryEngineRecoveryNudgePresentation.make(
        defaultEngine: .none,
        engineStatuses: [
            .none: EngineRuntimeStatus(state: .gray, detail: "No engine selected.")
        ]
    )

    XCTAssertEqual(nudge?.kind, .setupRequired)
    XCTAssertEqual(nudge?.toolbarTitle, "Add Diary Engine")
    XCTAssertEqual(nudge?.toolbarState, .yellow)
    XCTAssertEqual(nudge?.title, "Choose a Diary Engine")
}

func testEngineRecoveryNudgeRequestsRepairWhenDefaultEngineIsNotGreen() {
    let nudge = DiaryEngineRecoveryNudgePresentation.make(
        defaultEngine: .codexCLI,
        engineStatuses: [
            .codexCLI: EngineRuntimeStatus(state: .yellow, detail: "Smoke test failed.")
        ]
    )

    XCTAssertEqual(nudge?.kind, .repairRequired)
    XCTAssertEqual(nudge?.toolbarTitle, "Fix Diary Engine")
    XCTAssertEqual(nudge?.toolbarState, .yellow)
    XCTAssertEqual(nudge?.title, "Diary Engine needs attention")
    XCTAssertEqual(
        nudge?.detail,
        "Codex (CLI) is not ready. Retest it or configure another engine."
    )
}

func testEngineRecoveryNudgeClearsWhenDefaultEngineIsGreen() {
    let nudge = DiaryEngineRecoveryNudgePresentation.make(
        defaultEngine: .codexCLI,
        engineStatuses: [
            .codexCLI: EngineRuntimeStatus(state: .green, detail: "Smoke test succeeded.")
        ]
    )

    XCTAssertNil(nudge)
}

func testEngineRecoveryNudgePersistsWhileUnderlyingStateIsUnresolved() {
    let statuses: [DiaryEngine: EngineRuntimeStatus] = [
        .none: EngineRuntimeStatus(state: .gray, detail: "No engine selected.")
    ]

    let first = DiaryEngineRecoveryNudgePresentation.make(defaultEngine: .none, engineStatuses: statuses)
    let afterPopoverDismissal = DiaryEngineRecoveryNudgePresentation.make(defaultEngine: .none, engineStatuses: statuses)

    XCTAssertEqual(first, afterPopoverDismissal)
    XCTAssertEqual(afterPopoverDismissal?.toolbarTitle, "Add Diary Engine")
}
```

- [ ] **Step 2: Run the focused test slice and verify RED**

Run:

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/MainWindowViewModelTests/testEngineRecoveryNudgeRequestsSetupWhenDefaultEngineIsNone -only-testing:KnowYouTests/MainWindowViewModelTests/testEngineRecoveryNudgeRequestsRepairWhenDefaultEngineIsNotGreen -only-testing:KnowYouTests/MainWindowViewModelTests/testEngineRecoveryNudgeClearsWhenDefaultEngineIsGreen -only-testing:KnowYouTests/MainWindowViewModelTests/testEngineRecoveryNudgePersistsWhileUnderlyingStateIsUnresolved
```

Expected: FAIL because `DiaryEngineRecoveryNudgePresentation` does not exist.

## Task 2: Implement the Presentation Model

**Files:**
- Modify: `KnowYou/UI/Reader/DiaryEngineSelectorButton.swift`

- [ ] **Step 1: Add the minimal model**

```swift
enum DiaryEngineRecoveryNudgeKind: Equatable {
    case setupRequired
    case repairRequired
}

struct DiaryEngineRecoveryNudgePresentation: Equatable {
    let kind: DiaryEngineRecoveryNudgeKind
    let toolbarTitle: String
    let toolbarState: EngineIndicatorState
    let title: String
    let detail: String

    static func make(
        defaultEngine: DiaryEngine,
        engineStatuses: [DiaryEngine: EngineRuntimeStatus]
    ) -> DiaryEngineRecoveryNudgePresentation? {
        if defaultEngine == .none {
            return DiaryEngineRecoveryNudgePresentation(
                kind: .setupRequired,
                toolbarTitle: "Add Diary Engine",
                toolbarState: .yellow,
                title: "Choose a Diary Engine",
                detail: "Connect any engine to generate and refresh diary entries."
            )
        }

        let status = engineStatuses[defaultEngine] ?? EngineRuntimeStatus()
        guard status.state != .green else { return nil }

        return DiaryEngineRecoveryNudgePresentation(
            kind: .repairRequired,
            toolbarTitle: "Fix Diary Engine",
            toolbarState: .yellow,
            title: "Diary Engine needs attention",
            detail: "\(defaultEngine.displayName) is not ready. Retest it or configure another engine."
        )
    }
}
```

- [ ] **Step 2: Run focused tests and verify GREEN**

Run the same focused `xcodebuild test` command from Task 1.

Expected: PASS for the four recovery nudge tests.

## Task 3: Wire the Toolbar and Popover UI

**Files:**
- Modify: `KnowYou/UI/MainWindowView.swift`
- Modify: `KnowYou/UI/Reader/DiaryEnginePanel.swift`

- [ ] **Step 1: Pass the nudge to the toolbar and panel**

In `MainWindowView`, add:

```swift
private var engineRecoveryNudge: DiaryEngineRecoveryNudgePresentation? {
    DiaryEngineRecoveryNudgePresentation.make(
        defaultEngine: appState.defaultEngine,
        engineStatuses: appState.engineStatuses
    )
}
```

Then update the selector button:

```swift
DiaryEngineSelectorButton(
    title: engineRecoveryNudge?.toolbarTitle ?? currentEngineTitle,
    state: engineRecoveryNudge?.toolbarState ?? currentEngineState,
    emphasized: showsOnboardingEngineButton || engineRecoveryNudge != nil,
    action: openEngineSelector
)
```

Pass `recoveryNudge: engineRecoveryNudge` into `DiaryEnginePanel`.

- [ ] **Step 2: Render the panel banner**

In `DiaryEnginePanel`, add:

```swift
let recoveryNudge: DiaryEngineRecoveryNudgePresentation?
```

Render above rows:

```swift
if let recoveryNudge {
    DiaryEngineRecoveryNudgeBanner(presentation: recoveryNudge)
}
```

Add a private SwiftUI banner view using a yellow fill for setup and a red-tinted fill for repair, with compact title/detail text.

- [ ] **Step 3: Run focused build/test**

Run:

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/MainWindowViewModelTests/testEngineRecoveryNudgeRequestsSetupWhenDefaultEngineIsNone -only-testing:KnowYouTests/MainWindowViewModelTests/testEngineRecoveryNudgeRequestsRepairWhenDefaultEngineIsNotGreen -only-testing:KnowYouTests/MainWindowViewModelTests/testEngineRecoveryNudgeClearsWhenDefaultEngineIsGreen -only-testing:KnowYouTests/MainWindowViewModelTests/testEngineRecoveryNudgePersistsWhileUnderlyingStateIsUnresolved
```

Expected: PASS.

## Task 4: Final Verification

**Files:**
- Review all modified files.

- [ ] **Step 1: Run formatting/diff check**

```bash
git diff --check
```

Expected: no whitespace errors.

- [ ] **Step 2: Run full required tests**

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS'
```

Expected: exit 0.

- [ ] **Step 3: Run full required build**

```bash
xcodebuild build -scheme KnowYou -destination 'platform=macOS'
```

Expected: exit 0.

- [ ] **Step 4: Review final diff**

```bash
git diff --stat
git diff -- docs/superpowers/specs/2026-05-30-diary-engine-recovery-nudge-design.md docs/superpowers/plans/2026-05-30-diary-engine-recovery-nudge.md KnowYou/UI/Reader/DiaryEngineSelectorButton.swift KnowYou/UI/Reader/DiaryEnginePanel.swift KnowYou/UI/MainWindowView.swift KnowYouTests/MainWindowViewModelTests.swift
```

Expected: only scoped recovery nudge, tests, spec, plan, and mockup changes.
