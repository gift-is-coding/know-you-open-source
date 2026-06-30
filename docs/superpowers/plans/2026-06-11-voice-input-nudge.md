# Voice Input Nudge Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Add a visible non-error voice input nudge beside the Diary Engine selector; when no known voice input app is running, show a popover with Typeless and 闪电说 recommendations, real logos, download links, `Later`, and `Don't show again`.

**Architecture:** Split the feature into pure presentation/detection, AppState persistence, and SwiftUI toolbar/popover layers. Detection only reads `NSWorkspace.runningApplications` metadata; dismiss/snooze use the current profile's UserDefaults through AppState; the UI does not change Diary Engine status semantics.

**Tech Stack:** Swift 6, SwiftUI, AppKit `NSWorkspace`, XCTest, KnowYou profile-aware `AppState`.

---

### Task 1: Failing Presentation And Detector Tests

**Files:**
- Modify: `KnowYouTests/MainWindowViewModelTests.swift`

- [x] **Step 1: Add tests before production code**

```swift
func testVoiceInputNudgeShowsWhenNoKnownVoiceInputAppIsRunning() {
    let presentation = VoiceInputNudgePresentation.make(
        runningApplications: [],
        isPermanentlyDismissed: false,
        snoozedUntil: nil,
        now: Date(timeIntervalSince1970: 100)
    )

    XCTAssertNotNil(presentation)
    XCTAssertEqual(presentation?.title, "Use voice input")
    XCTAssertEqual(presentation?.recommendations.map(\.name), ["Typeless", "闪电说"])
    XCTAssertEqual(presentation?.recommendations.map(\.logoAssetName), [
        "VoiceInputLogoTypeless",
        "VoiceInputLogoShandianshuo"
    ])
}

func testVoiceInputNudgeClearsWhenKnownVoiceInputAppIsRunning() {
    let app = VoiceInputRunningApplication(
        localizedName: "Wispr Flow",
        bundleIdentifier: "ai.wispr.flow",
        bundlePath: "/Applications/Wispr Flow.app"
    )

    let presentation = VoiceInputNudgePresentation.make(
        runningApplications: [app],
        isPermanentlyDismissed: false,
        snoozedUntil: nil,
        now: Date(timeIntervalSince1970: 100)
    )

    XCTAssertNil(presentation)
}

func testVoiceInputNudgeRespectsSnoozeAndPermanentDismissal() {
    let now = Date(timeIntervalSince1970: 100)

    XCTAssertNil(VoiceInputNudgePresentation.make(
        runningApplications: [],
        isPermanentlyDismissed: false,
        snoozedUntil: Date(timeIntervalSince1970: 200),
        now: now
    ))
    XCTAssertNotNil(VoiceInputNudgePresentation.make(
        runningApplications: [],
        isPermanentlyDismissed: false,
        snoozedUntil: Date(timeIntervalSince1970: 50),
        now: now
    ))
    XCTAssertNil(VoiceInputNudgePresentation.make(
        runningApplications: [],
        isPermanentlyDismissed: true,
        snoozedUntil: nil,
        now: now
    ))
}
```

- [x] **Step 2: Run tests and confirm RED**

Run:

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' \
  -only-testing:KnowYouTests/MainWindowViewModelTests/testVoiceInputNudgeShowsWhenNoKnownVoiceInputAppIsRunning \
  -only-testing:KnowYouTests/MainWindowViewModelTests/testVoiceInputNudgeClearsWhenKnownVoiceInputAppIsRunning \
  -only-testing:KnowYouTests/MainWindowViewModelTests/testVoiceInputNudgeRespectsSnoozeAndPermanentDismissal
```

Expected: fails because `VoiceInputNudgePresentation` and `VoiceInputRunningApplication` do not exist.

### Task 2: Implement Presentation And Detection Model

**Files:**
- Create: `KnowYou/UI/Reader/VoiceInputNudge.swift`
- Modify: `KnowYou.xcodeproj/project.pbxproj`

- [x] **Step 1: Add model and recommendation data**

Implement:

- `VoiceInputRunningApplication`
- `VoiceInputRecommendation`
- `VoiceInputNudgePresentation`
- `VoiceInputAppDetector`

Keep matching deterministic and conservative: lowercase app name, bundle id, and path. The popover recommendations stay focused on `Typeless` and `闪电说`, while detection may also suppress the nudge for other known voice input tools so existing users are not interrupted.

Recommendation rows use asset catalog images:

- `VoiceInputLogoTypeless`
- `VoiceInputLogoShandianshuo`

- [x] **Step 2: Add file to Xcode sources**

Update `project.pbxproj` with file reference and source build phase for `VoiceInputNudge.swift`.

- [x] **Step 3: Run Task 1 tests and confirm GREEN**

Run the same focused `xcodebuild test` command from Task 1. Expected: all three tests pass.

### Task 3: Failing AppState Persistence Tests

**Files:**
- Modify: `KnowYouTests/MainWindowViewModelTests.swift`

- [x] **Step 1: Add persistence tests**

```swift
func testVoiceInputNudgeSnoozePersistsSevenDays() {
    let defaults = UserDefaults(suiteName: "MainWindowViewModelTests-\(UUID().uuidString)")!
    markOnboardingComplete(in: defaults)
    let appState = AppState(bootstrapServices: false, userDefaults: defaults, keychainService: "MainWindowViewModelTests")
    let now = Date(timeIntervalSince1970: 1_000)

    appState.snoozeVoiceInputNudge(now: now)

    let stored = defaults.object(forKey: AppState.UserDefaultsKeys.voiceInputNudgeSnoozedUntil) as? Date
    XCTAssertEqual(stored?.timeIntervalSince1970, now.addingTimeInterval(7 * 24 * 60 * 60).timeIntervalSince1970)
    XCTAssertFalse(appState.shouldShowVoiceInputNudge(runningApplications: [], now: now))
}

func testVoiceInputNudgePermanentDismissPersists() {
    let defaults = UserDefaults(suiteName: "MainWindowViewModelTests-\(UUID().uuidString)")!
    markOnboardingComplete(in: defaults)
    let appState = AppState(bootstrapServices: false, userDefaults: defaults, keychainService: "MainWindowViewModelTests")

    appState.dismissVoiceInputNudgePermanently()

    XCTAssertTrue(defaults.bool(forKey: AppState.UserDefaultsKeys.voiceInputNudgePermanentlyDismissed))
    XCTAssertFalse(appState.shouldShowVoiceInputNudge(runningApplications: [], now: Date()))
}
```

- [x] **Step 2: Run tests and confirm RED**

Expected: fails because AppState keys and methods do not exist.

### Task 4: Implement AppState Persistence

**Files:**
- Modify: `KnowYou/App/AppState.swift`

- [x] **Step 1: Add UserDefaults keys and methods**

Add:

- `voiceInputNudgeSnoozedUntil`
- `voiceInputNudgePermanentlyDismissed`
- `voiceInputNudgeSnoozeDuration = 7 days`
- `voiceInputNudgePresentation(runningApplications:now:)`
- `shouldShowVoiceInputNudge(runningApplications:now:)`
- `snoozeVoiceInputNudge(now:)`
- `dismissVoiceInputNudgePermanently()`

- [x] **Step 2: Run Task 3 tests and confirm GREEN**

Run the two AppState-focused tests. Expected: both pass.

### Task 5: SwiftUI Toolbar And Popover

**Files:**
- Modify: `KnowYou/UI/MainWindowView.swift`
- Modify: `KnowYou/UI/Reader/VoiceInputNudge.swift`

- [x] **Step 1: Add toolbar state**

Add `@State private var isShowingVoiceInputNudge = false` and `@State private var runningVoiceInputApplications: [VoiceInputRunningApplication] = []`.

- [x] **Step 2: Refresh detection on appear and activation**

Use `VoiceInputAppDetector.detectRunningApplications()` on `.onAppear` and when opening the popover. Keep it read-only and cheap.

- [x] **Step 3: Render beside Diary Engine**

Replace the single primary toolbar item content with:

```swift
HStack(spacing: 8) {
    if let voiceInputNudgePresentation {
        VoiceInputNudgeButton {
            refreshRunningVoiceInputApplications()
            isShowingVoiceInputNudge = true
        }
        .popover(isPresented: $isShowingVoiceInputNudge, arrowEdge: .top) {
            VoiceInputNudgePopover(
                presentation: voiceInputNudgePresentation,
                onOpen: { url in NSWorkspace.shared.open(url) },
                onLater: {
                    appState.snoozeVoiceInputNudge()
                    isShowingVoiceInputNudge = false
                },
                onNever: {
                    appState.dismissVoiceInputNudgePermanently()
                    isShowingVoiceInputNudge = false
                }
            )
        }
    }
    diaryEngineToolbarSelector
}
```

- [x] **Step 4: Implement views**

Implement `VoiceInputNudgeButton`, `VoiceInputNudgePopover`, `VoiceInputRecommendationRow`, and `VoiceInputLogo` in `VoiceInputNudge.swift`. The toolbar button uses a more visible amber `exclamationmark.circle.fill` badge, and all user-visible popover copy is English.

### Task 6: Verification

**Files:**
- Review: `docs/architecture.md`
- Review: `docs/requirements-spec.md`

- [x] **Step 1: Run focused tests**

Run:

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' \
  -only-testing:KnowYouTests/MainWindowViewModelTests/testVoiceInputNudgeShowsWhenNoKnownVoiceInputAppIsRunning \
  -only-testing:KnowYouTests/MainWindowViewModelTests/testVoiceInputNudgeClearsWhenKnownVoiceInputAppIsRunning \
  -only-testing:KnowYouTests/MainWindowViewModelTests/testVoiceInputNudgeRespectsSnoozeAndPermanentDismissal \
  -only-testing:KnowYouTests/MainWindowViewModelTests/testVoiceInputNudgeSnoozePersistsSevenDays \
  -only-testing:KnowYouTests/MainWindowViewModelTests/testVoiceInputNudgePermanentDismissPersists
```

- [x] **Step 2: Run full required verification**

Run:

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS'
xcodebuild build -scheme KnowYou -destination 'platform=macOS'
```

- [x] **Step 3: Check diff and docs**

Run:

```bash
git diff --check
git status --short
```

If `docs/architecture.md` or `docs/requirements-spec.md` need product-contract updates for this toolbar nudge, update them before final handoff.
