# 8:30 PM Background Review Reminder Plan

**Goal:** Add a real background 8:30 PM reminder flow that sends one of two English notifications depending on whether today's diary already exists, and routes notification clicks back into the correct in-app action.

**Architecture:** Extend `LaunchAgentManager` so it can register a reminder-specific launch agent, add a headless `--end-of-day-reminder-now` app mode that runs `EndOfDayReminderRunner`, teach `EndOfDayReminderService` to send `review` vs `generate` payloads, and route notification clicks through `AppState.openDayFromEndOfDayReminder(_:action:)`.

**Tech Stack:** SwiftUI, AppKit, UserNotifications, Foundation, launchd, XCTest, `xcodebuild`

---

### Task 1: Add background launch mode and launch-agent support

**Files:**
- Modify: `KnowYou/KnowYouApp.swift`
- Modify: `KnowYou/Services/SyncMemory/LaunchAgentManager.swift`

- [ ] Add a new app launch mode for `--end-of-day-reminder-now`.
- [ ] Run a headless reminder runner in that mode and terminate afterward.
- [ ] Extend launch-agent rendering so different agents can use different program arguments and `RunAtLoad` behavior.
- [ ] Register the reminder agent for daily local `20:30`.

### Task 2: Add reminder runner and dual notification payloads

**Files:**
- Modify: `KnowYou/Domain/EndOfDayReminder.swift`
- Modify: `KnowYou/Services/Reminders/EndOfDayReminderService.swift`
- Create: `KnowYou/Services/Reminders/EndOfDayReminderRunner.swift`

- [ ] Add an `EndOfDayReminderAction` model.
- [ ] Send `Come review today's diary.` when today's diary exists.
- [ ] Send `Come generate today's diary.` when today's diary does not exist.
- [ ] Persist same-day delivery state so the runner does not send duplicates.

### Task 3: Route reminder clicks back into the app

**Files:**
- Modify: `KnowYou/KnowYouApp.swift`
- Modify: `KnowYou/App/AppState.swift`

- [ ] Carry `dayKey + action` in notification payloads.
- [ ] Reuse an existing main window when possible.
- [ ] Open today's diary for `review`.
- [ ] Open today and start generating immediately for `generate`.

### Task 4: Cover the behavior with tests and docs

**Files:**
- Modify: `KnowYouTests/EndOfDayReminderServiceTests.swift`
- Modify: `KnowYouTests/EndOfDayReminderAppStateTests.swift`
- Modify: `KnowYouTests/LaunchAgentManagerTests.swift`
- Create: `KnowYouTests/EndOfDayReminderRunnerTests.swift`
- Modify: `docs/requirements-spec.md`
- Modify: `docs/architecture.md`
- Create: `docs/superpowers/specs/2026-04-27-8-30-pm-background-review-reminder.md`
- Create: `docs/superpowers/plans/2026-04-27-8-30-pm-background-review-reminder.md`

- [ ] Add focused tests for `review` vs `generate` payloads.
- [ ] Add focused tests for runner same-day dedupe behavior.
- [ ] Add focused tests for launch-agent registration behavior.
- [ ] Update product and architecture docs so they describe the new background reminder flow instead of the old planner-driven one.
