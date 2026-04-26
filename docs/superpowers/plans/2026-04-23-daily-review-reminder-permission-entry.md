# Daily Review Reminder Permission Entry Plan

**Goal:** Add a lightweight notification-permission entry for the 8:30 PM daily review reminder by extending onboarding and adding a dismissible toolbar CTA after onboarding.

**Architecture:** Reuse the existing reminder authorization/service flow in `AppState`, surface the notification explanation inside the onboarding permissions card, and add a main-window toolbar CTA that can request permission, deep-link to Notification Settings after denial, and persist dismissal state.

**Tech Stack:** SwiftUI, Foundation, UserDefaults, XCTest, `xcodebuild`

---

### Task 1: Extend onboarding permission messaging

**Files:**
- Modify: `KnowYou/UI/Onboarding/OnboardingContent.swift`
- Modify: `KnowYou/UI/Onboarding/OnboardingView.swift`
- Modify: `KnowYouTests/OnboardingContentTests.swift`

- [ ] Add concise notification copy for the 8:30 PM reminder inside the existing permissions step.
- [ ] Show notification authorization status alongside Full Disk Access.
- [ ] Add the correct permission action button for `notDetermined`, `authorized`, and `denied`.

### Task 2: Add a post-onboarding toolbar CTA

**Files:**
- Modify: `KnowYou/App/AppState.swift`
- Modify: `KnowYou/UI/MainWindowView.swift`
- Modify: `KnowYouTests/EndOfDayReminderAppStateTests.swift`

- [ ] Persist whether the user has dismissed the CTA.
- [ ] Show `Enable Daily Review Reminder` in the main toolbar when onboarding is complete and notification permission is still missing.
- [ ] Allow the CTA to request permission or open Notification Settings depending on current authorization status.
- [ ] Hide the CTA after authorization succeeds or after the user dismisses it.

### Task 3: Keep reminder state and docs aligned

**Files:**
- Modify: `docs/requirements-spec.md`
- Modify: `docs/architecture.md`
- Create: `docs/superpowers/specs/2026-04-23-daily-review-reminder-permission-entry.md`
- Create: `docs/superpowers/plans/2026-04-23-daily-review-reminder-permission-entry.md`

- [ ] Document that onboarding now explains notification use for the evening reminder.
- [ ] Document that the toolbar exposes a dismissible reminder-permission CTA after onboarding.
- [ ] Verify that authorization success auto-enables the reminder.

### Task 4: Full verification

**Files:**
- No additional source files

- [ ] Run focused onboarding/reminder tests.
- [ ] Run full `xcodebuild test -scheme KnowYou -destination 'platform=macOS'`.
- [ ] Run full `xcodebuild build -scheme KnowYou -destination 'platform=macOS'`.
