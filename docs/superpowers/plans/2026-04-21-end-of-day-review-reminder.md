# End-of-Day Review Reminder Implementation Plan

**Goal:** Add a gentle evening review reminder that uses macOS local notifications to bring the user back to today’s diary at a fixed local 8:30 PM reminder time.

**Architecture:** Introduce a pure `EndOfDayReminderPlanner`, a local-notification-backed `EndOfDayReminderService`, persistent reminder config plus per-day review state in `AppState`, and a small Settings section for the feature toggle and permission status. If today’s story is missing at 8:30 PM, `AppState` should trigger one refresh and only schedule the reminder after the refresh succeeds, using a fixed 10-minute delay.

**Tech Stack:** SwiftUI, UserNotifications, Foundation, XCTest, `xcodebuild`

---

### Task 1: Add reminder domain types and planner tests

**Files:**
- Create: `KnowYou/Domain/EndOfDayReminder.swift`
- Create: `KnowYou/Services/Reminders/EndOfDayReminderPlanner.swift`
- Create: `KnowYouTests/EndOfDayReminderPlannerTests.swift`

- [ ] Add config, authorization enum, and per-day review state models.
- [ ] Add planner inputs/outputs for schedule, trigger-refresh, cancel, and no-op.
- [ ] Lock the fixed `20:30`, refresh fallback, and once-per-day rules with focused tests.

### Task 2: Add the local notification service

**Files:**
- Create: `KnowYou/Services/Reminders/EndOfDayReminderService.swift`
- Create: `KnowYouTests/EndOfDayReminderServiceTests.swift`

- [ ] Wrap `UNUserNotificationCenter` behind a small scheduler protocol.
- [ ] Map system permission status into app-owned authorization state.
- [ ] Schedule and cancel one deterministic request per day.
- [ ] Use a stable, warm copy template pool.

### Task 3: Wire reminder state into AppState

**Files:**
- Modify: `KnowYou/App/AppState.swift`
- Modify: `KnowYouTests/MainWindowViewModelTests.swift`

- [ ] Persist `EndOfDayReminderConfig` and `[dayKey: DayReviewState]`.
- [ ] Refresh reminder authorization status during startup and service refresh.
- [ ] Re-evaluate today’s reminder after startup, permission refresh, and successful story generation.
- [ ] Trigger a single refresh when `20:30` arrives without a story, then schedule the reminder `10` minutes later if refresh succeeds.
- [ ] Add integration tests for generation-triggered scheduling, refresh fallback scheduling, denied-permission behavior, and relaunch deduplication.

### Task 4: Add Settings UI

**Files:**
- Modify: `KnowYou/UI/Settings/SettingsView.swift`

- [ ] Add an `Evening Review Reminder` section with a toggle, permission detail, and rule copy.
- [ ] Route toggle changes through `AppState` so enabling can request authorization and disabling cancels today’s pending reminder.

### Task 5: Update docs and verify

**Files:**
- Modify: `docs/requirements-spec.md`
- Modify: `docs/architecture.md`
- Modify: `KnowYou.xcodeproj/project.pbxproj`

- [ ] Document the new reminder capability and architecture.
- [ ] Register new source and test files in the Xcode project.
- [ ] Run focused reminder tests first, then full `xcodebuild test` and `xcodebuild build`.
