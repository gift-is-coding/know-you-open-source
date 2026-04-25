# Default Launch At Login Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Register KnowYou as a macOS login item by default after first interactive launch, with a Settings toggle to disable it.

**Architecture:** Keep the feature small: a `LoginItemManaging` abstraction wraps `SMAppService.mainApp`; `AppState` owns persistence and UI-facing state; `KnowYouApp` triggers one-time default registration for interactive launches only.

**Tech Stack:** SwiftUI, ServiceManagement, UserDefaults, XCTest.

---

### Task 1: Add Tests First

**Files:**
- Modify: `KnowYouTests/MainWindowViewModelTests.swift`

- [ ] Add fake login item manager and tests for default registration, opt-out, explicit enable/disable, and failure rollback.
- [ ] Run `xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/MainWindowViewModelTests/testDefaultLaunchAtLoginRegistersOnce -only-testing:KnowYouTests/MainWindowViewModelTests/testDefaultLaunchAtLoginDoesNotReenableAfterOptOut -only-testing:KnowYouTests/MainWindowViewModelTests/testSettingLaunchAtLoginDisabledUnregistersLoginItem -only-testing:KnowYouTests/MainWindowViewModelTests/testLaunchAtLoginEnableFailureRollsBackToggle` and confirm the new tests fail before production code exists.

### Task 2: Implement Login Item State

**Files:**
- Modify: `KnowYou/App/AppState.swift`

- [ ] Add `LoginItemManaging` and `MainAppLoginItemManager`.
- [ ] Add `launchAtLoginEnabled`, `launchAtLoginStatusMessage`, `ensureDefaultLaunchAtLogin()`, and `setLaunchAtLoginEnabled(_:)`.
- [ ] Add `launchAtLoginDefaultRegistrationAttempted` to `UserDefaultsKeys`.
- [ ] Run the focused tests and confirm they pass.

### Task 3: Wire App Launch And Settings

**Files:**
- Modify: `KnowYou/KnowYouApp.swift`
- Modify: `KnowYou/UI/Settings/SettingsView.swift`

- [ ] Make `KnowYouApp` call `ensureDefaultLaunchAtLogin()` only for interactive launches.
- [ ] Add a `Launch at Login` toggle in Settings > Automation.
- [ ] Run focused tests, then `xcodebuild test -scheme KnowYou -destination 'platform=macOS'` and `xcodebuild build -scheme KnowYou -destination 'platform=macOS'`.

### Task 4: Update Product Docs

**Files:**
- Modify: `docs/requirements-spec.md`
- Modify: `docs/architecture.md`

- [ ] Document that KnowYou defaults to launching at login after first interactive launch.
- [ ] Re-run full verification after docs are updated if code changed after the prior build.

