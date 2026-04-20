# Sidebar Feedback Entry Implementation Plan

**Goal:** Keep the existing sidebar footer structure, add one adjacent `Feedback` menu button with three contact channels, and verify that a completed onboarding state still stays complete during a bootstrapped relaunch.

**Architecture:** Reuse the existing URLs and button titles in `AppSupportMetadata` as the shared contact source. Restore `SettingsView` contact buttons, keep `DateSidebarView` on the original compact `Menu` pattern, and add one onboarding regression test plus a safer development relaunch flow.

**Tech Stack:** SwiftUI, XCTest, shell script, `xcodebuild`

---

### Task 1: Shrink the sidebar change to the original structure

**Files:**
- Modify: `KnowYou/UI/Sidebar/DateSidebarView.swift`
- Modify: `KnowYou/UI/Settings/SettingsView.swift`

- [ ] Restore the sidebar footer to the original compact menu layout.
- [ ] Keep the existing settings/sync path unchanged.
- [ ] Add one new `Feedback` icon menu beside it.
- [ ] Wire the three menu items to X / Twitter, Email, and Discord.
- [ ] Restore the `SettingsView` contact row instead of moving support actions out of settings.

### Task 2: Lock onboarding relaunch behavior

**Files:**
- Modify: `KnowYouTests/OnboardingProgressTests.swift`

- [ ] Add a regression test that completes onboarding, relaunches `AppState` with bootstrapped services, and verifies `shouldShowOnboarding == false`.
- [ ] Run the focused onboarding test slice.

### Task 3: Reduce relaunch-side state loss risk and verify

**Files:**
- Modify: `scripts/run-dev-app.sh`

- [ ] Replace the force-first relaunch with a graceful quit attempt before fallback kill.
- [ ] Stop using `open -na` so the latest debug build reopens more conservatively.
- [ ] Run focused tests, full test/build, and launch the fresh app for manual inspection.
