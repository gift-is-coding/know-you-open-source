# Daily Review Reminder Onboarding-Only Plan

**Goal:** Simplify the daily review reminder permission flow so onboarding remains the primary place to request notifications, while the rest of the app keeps only settings-based management.

**Architecture:** Remove the post-onboarding toolbar CTA and its persistence state, keep onboarding permission UI wired to `requestDailyReviewReminderAuthorization()`, and keep settings as the fallback place to inspect status or jump to Notification Settings.

**Tech Stack:** SwiftUI, Foundation, UserDefaults, XCTest, `xcodebuild`

---

### Task 1: Remove toolbar CTA state and UI

**Files:**
- Modify: `KnowYou/App/AppState.swift`
- Modify: `KnowYou/UI/MainWindowView.swift`

- [ ] Delete CTA-specific computed properties and dismiss methods from `AppState`.
- [ ] Delete CTA persistence state from `UserDefaults`.
- [ ] Remove the reminder CTA from the main window toolbar.

### Task 2: Keep onboarding and settings as the only permission surfaces

**Files:**
- Modify: `KnowYou/UI/Onboarding/OnboardingView.swift`
- Modify: `KnowYou/UI/Settings/SettingsView.swift`

- [ ] Preserve onboarding notification explanation and permission button.
- [ ] Preserve settings reminder status, toggle, and test action.
- [ ] Ensure denied users still have a clear path to Notification Settings.

### Task 3: Align reminder tests and docs

**Files:**
- Modify: `KnowYouTests/EndOfDayReminderAppStateTests.swift`
- Modify: `docs/requirements-spec.md`
- Modify: `docs/architecture.md`
- Create: `docs/superpowers/specs/2026-04-26-daily-review-reminder-onboarding-only.md`
- Create: `docs/superpowers/plans/2026-04-26-daily-review-reminder-onboarding-only.md`

- [ ] Remove CTA-specific tests.
- [ ] Add/keep coverage for onboarding-triggered authorization and non-auto-enable refresh behavior.
- [ ] Update product docs so they no longer mention the removed toolbar CTA.
