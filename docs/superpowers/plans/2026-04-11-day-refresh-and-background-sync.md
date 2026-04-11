# Day Refresh And Background Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make manual refresh regenerate only the selected day, add day-scoped notification sync with background incremental recovery, and auto-select a verified default engine only when the current default is `None`.

**Architecture:** Split the current refresh path into two flows: a bounded selected-day refresh path for UI actions and a separate notification background sync path for startup and periodic ingestion. Keep clipboard capture unchanged, add explicit notification sync bookkeeping in `AppState`, and make default-engine auto-selection a deterministic post-probe reconciliation step instead of an initialization side effect.

**Tech Stack:** Swift, SwiftUI, XCTest, GRDB, macOS Timer-based background polling

---

## File Structure

**Modify**

- `KnowYou/App/AppState.swift`
  Owns selected-day refresh flow, background notification sync scheduling, persisted sync bookkeeping, and default-engine auto-selection logic.
- `KnowYou/KnowYouApp.swift`
  Keeps wiring unchanged, but this file is part of validation because app startup still constructs `AppState()`.
- `KnowYou/Services/Notifications/NotificationCollector.swift`
  Needs day-window import support so selected-day refresh can sync one day without reusing global automation.
- `KnowYou/Services/Notifications/NotificationDatabaseReader.swift`
  May need a helper-oriented API for day-bounded reads if implementation is cleaner here than in `AppState`.
- `KnowYouTests/MainWindowViewModelTests.swift`
  Primary behavior tests for refresh, background sync bookkeeping, and engine auto-selection.
- `KnowYouTests/DatabaseWriterTests.swift`
  Add idempotency coverage if notification overlap behavior needs explicit persistence-level regression tests.
- `docs/architecture.md`
  Update source-ingestion and refresh architecture after implementation.
- `docs/requirements-spec.md`
  Update product requirements language for day-scoped refresh and background notification sync.

**Create**

- No new production files required unless `AppState.swift` becomes too large during implementation.

---

### Task 1: Lock Down Refresh Scope With Failing Tests

**Files:**
- Modify: `KnowYouTests/MainWindowViewModelTests.swift`
- Test: `KnowYouTests/MainWindowViewModelTests.swift`

- [ ] **Step 1: Write failing tests for selected-day-only refresh and day-window notification sync**

Add tests covering:

```swift
func testRefreshSelectedDayForTodayRequestsOnlyTodayWindow() async throws {
    let writer = try DatabaseWriter.inMemory()
    let reader = RecordingNotificationReader()
    let now = DateComponents(
        calendar: Calendar(identifier: .gregorian),
        year: 2026, month: 4, day: 11, hour: 15, minute: 30
    ).date!
    let environment = AppEnvironment(
        databaseURL: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).sqlite"),
        vaultURL: URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory),
        databaseWriter: writer,
        summarizer: nil,
        notificationReader: reader,
        dailyAutomationPlanner: DailyAutomationPlanner(
            backfillPlanner: BackfillPlanner(calendar: Calendar(identifier: .gregorian))
        )
    )
    let appState = AppState(environment: environment)

    await appState.refreshSelectedDay(now: now)

    let expectedStart = Calendar(identifier: .gregorian).startOfDay(for: now)
    XCTAssertEqual(reader.requestedSince, expectedStart)
    XCTAssertEqual(appState.selectedDate, "2026-04-11")
}

func testRefreshSelectedDayForHistoricalDateRequestsOnlyThatDayWindow() async throws {
    let writer = try DatabaseWriter.inMemory()
    let reader = RecordingNotificationReader()
    let environment = AppEnvironment(
        databaseURL: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).sqlite"),
        vaultURL: URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory),
        databaseWriter: writer,
        summarizer: nil,
        notificationReader: reader,
        dailyAutomationPlanner: DailyAutomationPlanner(
            backfillPlanner: BackfillPlanner(calendar: Calendar(identifier: .gregorian))
        )
    )
    let appState = AppState(environment: environment)
    appState.selectDate("2026-04-08")

    await appState.refreshSelectedDay(
        now: DateComponents(calendar: Calendar(identifier: .gregorian), year: 2026, month: 4, day: 11).date!
    )

    let expectedStart = DateComponents(calendar: Calendar(identifier: .gregorian), year: 2026, month: 4, day: 8).date!
    XCTAssertEqual(reader.requestedSince, expectedStart)
    XCTAssertEqual(appState.statusMessage, "Refreshed 2026-04-08")
}
```

- [ ] **Step 2: Run the targeted refresh tests and confirm the current code fails for the new expectations**

Run:

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/MainWindowViewModelTests
```

Expected:

- Existing test suite runs
- New selected-day refresh tests fail because `refreshSelectedDay()` still routes today through `runAutomation()` instead of a day-scoped notification sync path

- [ ] **Step 3: Add one more failing test proving manual refresh no longer backfills earlier days**

Append a regression test like:

```swift
func testRefreshSelectedDayDoesNotRunMultiDayAutomationBackfill() async throws {
    let writer = try DatabaseWriter.inMemory()
    let reader = RecordingNotificationReader()
    let historicalDay = "2026-04-08"
    try writer.insert(
        EventRecord(
            id: UUID(),
            sourceType: .clipboard,
            sourceApp: "Notes",
            capturedAt: DateComponents(calendar: Calendar(identifier: .gregorian), year: 2026, month: 4, day: 8, hour: 9).date!,
            dayKey: historicalDay,
            text: "Historical event",
            auditText: nil,
            privacyAction: .keep,
            contentHash: "historical-only"
        )
    )
    let environment = AppEnvironment(
        databaseURL: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).sqlite"),
        vaultURL: URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory),
        databaseWriter: writer,
        summarizer: nil,
        notificationReader: reader,
        dailyAutomationPlanner: DailyAutomationPlanner(
            backfillPlanner: BackfillPlanner(calendar: Calendar(identifier: .gregorian))
        )
    )
    let appState = AppState(environment: environment)
    appState.selectDate(historicalDay)

    await appState.refreshSelectedDay(
        now: DateComponents(calendar: Calendar(identifier: .gregorian), year: 2026, month: 4, day: 11).date!
    )

    XCTAssertEqual(try writer.fetchRuns(runType: "daily-note").map(\.dayKey), [historicalDay])
}
```

- [ ] **Step 4: Re-run the focused test slice to keep all new failures visible before implementation**

Run:

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/MainWindowViewModelTests
```

Expected:

- The new tests fail
- Existing unrelated tests remain green

- [ ] **Step 5: Commit the red test state**

```bash
git add KnowYouTests/MainWindowViewModelTests.swift
git commit -m "test: cover day scoped refresh behavior"
```

---

### Task 2: Implement Day-Scoped Refresh And Notification Window Sync

**Files:**
- Modify: `KnowYou/App/AppState.swift`
- Modify: `KnowYou/Services/Notifications/NotificationCollector.swift`
- Test: `KnowYouTests/MainWindowViewModelTests.swift`

- [ ] **Step 1: Add a day-window notification import helper in `NotificationCollector`**

Add a helper that accepts a concrete start date and keeps the current import result shape:

```swift
func importDeliveredNotifications(from startDate: Date) throws -> NotificationImportResult {
    guard let databaseReader else {
        return NotificationImportResult(importedCount: 0, importedAt: Date())
    }

    let snapshots = try databaseReader.fetchDeliveredNotifications(since: startDate)
    return NotificationImportResult(
        importedCount: ingest(snapshots),
        importedAt: Date()
    )
}
```

Then keep the existing API as a forwarding wrapper:

```swift
func importDeliveredNotifications(since: Date) throws -> NotificationImportResult {
    try importDeliveredNotifications(from: since)
}
```

- [ ] **Step 2: Refactor `AppState.refreshSelectedDay` so it never calls `runAutomation()`**

Replace the current branch that calls `refreshToday(now:environment:)` with an explicit selected-day flow:

```swift
func refreshSelectedDay(now: Date = Date()) async {
    guard let environment else {
        statusMessage = "Capture unavailable"
        return
    }

    let targetDay = selectedDate ?? ISO8601DayKey.format(now)
    if selectedDate == nil {
        selectDate(targetDay)
    }

    await refreshDay(targetDay, now: now, environment: environment)
}
```

Add a dedicated method:

```swift
func refreshDay(_ dayKey: String, now: Date, environment: AppEnvironment) async {
    do {
        let imported = try syncNotifications(for: dayKey, now: now, environment: environment)
        await generateDailyNote(for: dayKey, recordsRun: true)
        if dayRefreshStatus.lastError == nil {
            statusMessage = imported > 0
                ? "Refreshed \(dayKey) after syncing notifications"
                : "Refreshed \(dayKey)"
        }
    } catch {
        dayRefreshStatus.lastRequestedDay = dayKey
        dayRefreshStatus.lastRefreshedAt = Date()
        dayRefreshStatus.lastError = error.localizedDescription
        statusMessage = "Refresh failed for \(dayKey): \(error.localizedDescription)"
    }
}
```

- [ ] **Step 3: Implement a bounded selected-day notification sync helper**

In `AppState.swift`, add a helper like:

```swift
func syncNotifications(
    for dayKey: String,
    now: Date,
    environment: AppEnvironment
) throws -> Int {
    guard let windowStart = ISO8601DayKey.parse(dayKey) else {
        return 0
    }

    let calendar = Calendar(identifier: .gregorian)
    let dayStart = calendar.startOfDay(for: windowStart)
    let effectiveStart = dayKey == ISO8601DayKey.format(now) ? dayStart : dayStart
    let result = try environment.notificationCollector.importDeliveredNotifications(from: effectiveStart)
    notificationStatus.lastImportedAt = result.importedAt
    notificationStatus.lastImportedCount = result.importedCount
    if notificationStatus.isDatabaseAvailable {
        notificationStatus.lastError = nil
    }
    return result.importedCount
}
```

Do not call `dailyAutomationPlanner.pendingDays(...)` anywhere in this path.

- [ ] **Step 4: Run the targeted refresh tests and verify they now pass**

Run:

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/MainWindowViewModelTests
```

Expected:

- The new refresh tests pass
- Existing refresh-related tests continue to pass

- [ ] **Step 5: Commit the bounded refresh implementation**

```bash
git add KnowYou/App/AppState.swift KnowYou/Services/Notifications/NotificationCollector.swift KnowYouTests/MainWindowViewModelTests.swift
git commit -m "feat: make manual refresh day scoped"
```

---

### Task 3: Add Background Notification Recovery And Idempotency Coverage

**Files:**
- Modify: `KnowYou/App/AppState.swift`
- Modify: `KnowYouTests/MainWindowViewModelTests.swift`
- Modify: `KnowYouTests/DatabaseWriterTests.swift`
- Test: `KnowYouTests/MainWindowViewModelTests.swift`
- Test: `KnowYouTests/DatabaseWriterTests.swift`

- [ ] **Step 1: Write failing tests for cold-start recovery and overlapping sync deduplication**

Add tests such as:

```swift
func testStartAutomationRecoversTodayNotificationsFromStartOfDay() async throws {
    let writer = try DatabaseWriter.inMemory()
    let reader = RecordingNotificationReader()
    let now = DateComponents(calendar: Calendar(identifier: .gregorian), year: 2026, month: 4, day: 11, hour: 13).date!
    reader.snapshots = [
        NotificationSnapshot(appName: "Calendar", deliveredAt: now, body: "Standup in 5")
    ]

    let environment = AppEnvironment(
        databaseURL: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).sqlite"),
        vaultURL: URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory),
        databaseWriter: writer,
        summarizer: nil,
        notificationReader: reader,
        dailyAutomationPlanner: DailyAutomationPlanner(
            backfillPlanner: BackfillPlanner(calendar: Calendar(identifier: .gregorian))
        )
    )
    let appState = AppState(environment: environment)

    await appState.runNotificationCatchUp(now: now)

    XCTAssertEqual(reader.requestedSince, Calendar(identifier: .gregorian).startOfDay(for: now))
    XCTAssertEqual(try writer.fetchEvents(dayKey: "2026-04-11").count, 1)
}
```

And a persistence test:

```swift
func testInsertIgnoresDuplicateNotificationContentHash() throws {
    let writer = try DatabaseWriter.inMemory()
    let capturedAt = DateComponents(calendar: Calendar(identifier: .gregorian), year: 2026, month: 4, day: 11, hour: 10).date!
    let event = EventRecord(
        id: UUID(),
        sourceType: .notification,
        sourceApp: "com.apple.MobileSMS",
        capturedAt: capturedAt,
        dayKey: "2026-04-11",
        text: "hello",
        auditText: nil,
        privacyAction: .keep,
        contentHash: "same-hash"
    )

    try writer.insert(event)
    try writer.insert(event)

    XCTAssertEqual(try writer.fetchEvents(dayKey: "2026-04-11").count, 1)
}
```

- [ ] **Step 2: Run the new background-sync and idempotency tests and confirm they fail where behavior is still missing**

Run:

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/MainWindowViewModelTests -only-testing:KnowYouTests/DatabaseWriterTests
```

Expected:

- The duplicate content-hash test may already pass
- The cold-start background recovery test fails until explicit notification catch-up bookkeeping exists

- [ ] **Step 3: Add notification sync bookkeeping and a dedicated background catch-up path in `AppState`**

Introduce state for last successful notification import and a narrow background runner:

```swift
var lastNotificationImportAt: Date?
private let notificationSyncInterval: TimeInterval = 30
private let notificationOverlapBuffer: TimeInterval = 30

func runNotificationCatchUp(now: Date = Date()) async {
    guard let environment else { return }

    let todayStart = Calendar(identifier: .gregorian).startOfDay(for: now)
    let importStart = max(
        todayStart,
        (lastNotificationImportAt ?? todayStart).addingTimeInterval(-notificationOverlapBuffer)
    )

    do {
        let result = try environment.notificationCollector.importDeliveredNotifications(from: importStart)
        lastNotificationImportAt = result.importedAt
        notificationStatus.lastImportedAt = result.importedAt
        notificationStatus.lastImportedCount = result.importedCount
        if notificationStatus.isDatabaseAvailable {
            notificationStatus.lastError = nil
        }
    } catch {
        notificationStatus.lastError = error.localizedDescription
    }
}
```

Then update timer scheduling so the background timer calls `runNotificationCatchUp()` instead of `runAutomation()`, while startup still performs one immediate catch-up.

- [ ] **Step 4: Re-run the targeted background-sync tests and verify the new behavior passes**

Run:

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/MainWindowViewModelTests -only-testing:KnowYouTests/DatabaseWriterTests
```

Expected:

- Cold-start recovery test passes
- Deduplication regression remains green

- [ ] **Step 5: Commit the background notification sync changes**

```bash
git add KnowYou/App/AppState.swift KnowYouTests/MainWindowViewModelTests.swift KnowYouTests/DatabaseWriterTests.swift
git commit -m "feat: add incremental background notification sync"
```

---

### Task 4: Auto-Select A Verified Engine Only When Default Is `None`

**Files:**
- Modify: `KnowYou/App/AppState.swift`
- Modify: `KnowYouTests/MainWindowViewModelTests.swift`
- Test: `KnowYouTests/MainWindowViewModelTests.swift`

- [ ] **Step 1: Write failing tests for `None`-only auto-selection and no override of explicit choices**

Add tests like:

```swift
func testRetestAllEnginesAutoSelectsHighestPriorityGreenEngineWhenDefaultIsNone() async throws {
    let appState = AppState(
        bootstrapServices: false,
        summarizerConfig: .default,
        probeEngine: { engine, _, _ in
            switch engine {
            case .codexCLI:
                return EngineProbeResult(engine: engine, state: .green, detail: "OK", verifiedAt: Date())
            case .geminiCLI:
                return EngineProbeResult(engine: engine, state: .green, detail: "OK", verifiedAt: Date())
            default:
                return EngineProbeResult(engine: engine, state: .gray, detail: "Missing", verifiedAt: nil)
            }
        },
        userDefaults: engineDefaults,
        keychain: engineKeychain,
        keychainService: "MainWindowViewModelTests"
    )

    await appState.retestAllEngines()

    XCTAssertEqual(appState.defaultEngine, .codexCLI)
}

func testRetestAllEnginesDoesNotOverrideExplicitDefaultEngine() async throws {
    var config = SummarizerConfig.default
    config.defaultEngine = .geminiCLI
    let appState = AppState(
        bootstrapServices: false,
        summarizerConfig: config,
        probeEngine: { engine, _, _ in
            let state: EngineIndicatorState = (engine == .codexCLI || engine == .geminiCLI) ? .green : .gray
            return EngineProbeResult(engine: engine, state: state, detail: "OK", verifiedAt: Date())
        },
        userDefaults: engineDefaults,
        keychain: engineKeychain,
        keychainService: "MainWindowViewModelTests"
    )

    await appState.retestAllEngines()

    XCTAssertEqual(appState.defaultEngine, .geminiCLI)
}
```

- [ ] **Step 2: Run the engine-selection test slice and verify the new tests fail**

Run:

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/MainWindowViewModelTests
```

Expected:

- Auto-selection tests fail because the current code preserves `None` after probing

- [ ] **Step 3: Implement deterministic engine auto-selection in `AppState`**

Add a helper:

```swift
private static let autoSelectionPriority: [DiaryEngine] = [
    .claudeCLI, .codexCLI, .geminiCLI, .openclawCLI, .openAI
]

func reconcileDefaultEngineAfterStatusChange() {
    guard defaultEngine == .none else { return }
    guard let preferred = Self.autoSelectionPriority.first(where: { engineStatuses[$0]?.state == .green }) else {
        return
    }
    selectDefaultEngine(preferred)
}
```

Call it after:

```swift
refreshEngineStatuses()
await retestAllEngines()
await retestEngine(_:)
```

Do not call it from paths where `defaultEngine` is already non-`None`.

- [ ] **Step 4: Re-run the engine-selection tests and verify they pass**

Run:

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/MainWindowViewModelTests
```

Expected:

- New auto-selection tests pass
- Existing onboarding/default-engine persistence tests remain green

- [ ] **Step 5: Commit the engine auto-selection implementation**

```bash
git add KnowYou/App/AppState.swift KnowYouTests/MainWindowViewModelTests.swift
git commit -m "feat: auto select verified engine from none"
```

---

### Task 5: Update Product Docs And Run Full Verification

**Files:**
- Modify: `docs/architecture.md`
- Modify: `docs/requirements-spec.md`
- Modify: `docs/superpowers/specs/2026-04-11-day-refresh-and-background-sync-design.md`

- [ ] **Step 1: Update architecture and requirements docs to match implemented behavior**

Add concise updates covering:

```md
- manual refresh is day-scoped and never triggers historical backfill
- selected-day refresh may sync notifications for that same day only
- clipboard remains background-capture-only
- background notification sync runs every 30 seconds with overlap-safe deduplication
- default engine auto-selection runs only when the persisted default is `None`
```

- [ ] **Step 2: Run targeted test slices before the full suite**

Run:

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/MainWindowViewModelTests -only-testing:KnowYouTests/DatabaseWriterTests
```

Expected:

- PASS

- [ ] **Step 3: Run full required verification**

Run:

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS'
xcodebuild build -scheme KnowYou -destination 'platform=macOS'
```

Expected:

- Both commands succeed
- No regressions in onboarding, refresh, or engine-selection tests

- [ ] **Step 4: Commit docs and final verification-backed implementation state**

```bash
git add docs/architecture.md docs/requirements-spec.md docs/superpowers/specs/2026-04-11-day-refresh-and-background-sync-design.md
git commit -m "docs: align refresh and sync architecture"
```

---

## Self-Review

### Spec Coverage

- Manual refresh scoped to selected day: covered in Tasks 1 and 2
- Notification day-window sync for today and historical dates: covered in Tasks 1 and 2
- Clipboard remains background-only: covered in Task 5 docs and preserved by Task 2 implementation boundaries
- 30-second notification background sync: covered in Task 3
- Cold-start recovery for today: covered in Task 3
- Deduplication requirements: covered in Task 3
- `None`-only engine auto-selection: covered in Task 4
- Shared onboarding/main-window default engine semantics: covered in Task 4 and Task 5 docs

### Placeholder Scan

- No `TODO`/`TBD` placeholders remain
- Every task lists exact files and commands
- Code-changing steps include concrete code snippets

### Type Consistency

- Plan consistently uses `refreshSelectedDay`, `refreshDay`, `syncNotifications`, `runNotificationCatchUp`, and `reconcileDefaultEngineAfterStatusChange`
- Notification sync bookkeeping is described only through `lastNotificationImportAt`, not mixed with the existing automation planner

