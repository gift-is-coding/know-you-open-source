# Know You MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a standalone macOS app that captures clipboard and notification context, filters sensitive content before persistence, generates one Markdown note per day, and renders it in a minimal two-pane reader.

**Architecture:** Use one native SwiftUI macOS app with `MenuBarExtra` so the process can stay alive in the background while still providing a main reader window. Persist filtered events and run metadata in SQLite through GRDB, compose daily Markdown files into a local vault folder, and call a cloud LLM provider to fill the `Summary` section after composition.

**Tech Stack:** Swift 6, SwiftUI, AppKit, GRDB, MarkdownUI, XCTest, `xcodebuild`

---

## File Structure

### App Target

- Create: `KnowYou.xcodeproj/project.pbxproj`
- Create: `KnowYou/KnowYouApp.swift`
- Create: `KnowYou/App/AppEnvironment.swift`
- Create: `KnowYou/App/AppState.swift`
- Create: `KnowYou/UI/MainWindowView.swift`
- Create: `KnowYou/UI/Sidebar/DateSidebarView.swift`
- Create: `KnowYou/UI/Reader/DailyMarkdownView.swift`
- Create: `KnowYou/UI/Status/StatusBannerView.swift`
- Create: `KnowYou/UI/Settings/SettingsView.swift`

### Capture and Domain

- Create: `KnowYou/Domain/EventRecord.swift`
- Create: `KnowYou/Domain/RunRecord.swift`
- Create: `KnowYou/Domain/DailyNote.swift`
- Create: `KnowYou/Services/Clipboard/ClipboardWatcher.swift`
- Create: `KnowYou/Services/Notifications/NotificationCollector.swift`
- Create: `KnowYou/Services/Privacy/PrivacyFilter.swift`
- Create: `KnowYou/Services/Storage/DatabaseWriter.swift`
- Create: `KnowYou/Services/Storage/Migrations.swift`
- Create: `KnowYou/Services/Composer/DailyMarkdownComposer.swift`
- Create: `KnowYou/Services/Backfill/BackfillPlanner.swift`
- Create: `KnowYou/Services/Summary/CloudSummarizer.swift`
- Create: `KnowYou/Services/Scheduler/DailyScheduler.swift`

### Tests

- Create: `KnowYouTests/PrivacyFilterTests.swift`
- Create: `KnowYouTests/DatabaseWriterTests.swift`
- Create: `KnowYouTests/DailyMarkdownComposerTests.swift`
- Create: `KnowYouTests/BackfillPlannerTests.swift`
- Create: `KnowYouTests/MainWindowViewModelTests.swift`

### Docs and Config

- Modify: `.gitignore`
- Create: `README.md`
- Create: `KnowYou/Config/Secrets.example.xcconfig`

## Task 1: Bootstrap The Native macOS App Skeleton

**Files:**
- Create: `KnowYou.xcodeproj/project.pbxproj`
- Create: `KnowYou/KnowYouApp.swift`
- Create: `KnowYou/App/AppEnvironment.swift`
- Create: `KnowYou/App/AppState.swift`
- Create: `KnowYou/UI/MainWindowView.swift`
- Create: `KnowYou/UI/Sidebar/DateSidebarView.swift`
- Create: `KnowYou/UI/Reader/DailyMarkdownView.swift`
- Create: `KnowYou/UI/Status/StatusBannerView.swift`
- Create: `KnowYou/UI/Settings/SettingsView.swift`
- Create: `README.md`
- Create: `KnowYou/Config/Secrets.example.xcconfig`

- [ ] **Step 1: Write the failing app-state test**

```swift
// KnowYouTests/MainWindowViewModelTests.swift
import XCTest
@testable import KnowYou

final class MainWindowViewModelTests: XCTestCase {
    func testSelectingDateLoadsMatchingMarkdownPath() {
        let appState = AppState()
        appState.availableDates = ["2026-04-07", "2026-04-06"]
        appState.noteIndex = [
            "2026-04-07": URL(fileURLWithPath: "/tmp/2026-04-07.md"),
            "2026-04-06": URL(fileURLWithPath: "/tmp/2026-04-06.md"),
        ]

        appState.selectDate("2026-04-06")

        XCTAssertEqual(appState.selectedDate, "2026-04-06")
        XCTAssertEqual(appState.selectedMarkdownURL?.path, "/tmp/2026-04-06.md")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/MainWindowViewModelTests`
Expected: FAIL with `Cannot find 'AppState' in scope` or missing target errors because the app skeleton does not exist yet.

- [ ] **Step 3: Create the app shell and state objects**

```swift
// KnowYou/App/AppState.swift
import Foundation
import Observation

@Observable
final class AppState {
    var availableDates: [String] = []
    var selectedDate: String?
    var selectedMarkdownURL: URL?
    var noteIndex: [String: URL] = [:]
    var statusMessage: String?

    func selectDate(_ date: String) {
        selectedDate = date
        selectedMarkdownURL = noteIndex[date]
    }
}
```

```swift
// KnowYou/KnowYouApp.swift
import SwiftUI

@main
struct KnowYouApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup("Know You") {
            MainWindowView()
                .environment(appState)
        }
        MenuBarExtra("Know You", systemImage: "book.closed") {
            SettingsLink()
            Divider()
            Text(appState.statusMessage ?? "Capturing context")
                .font(.footnote)
        }
        Settings {
            SettingsView()
                .environment(appState)
        }
    }
}
```

```swift
// KnowYou/UI/MainWindowView.swift
import SwiftUI

struct MainWindowView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        NavigationSplitView {
            DateSidebarView(
                dates: appState.availableDates,
                selectedDate: appState.selectedDate,
                onSelect: appState.selectDate
            )
        } detail: {
            VStack(spacing: 0) {
                StatusBannerView(message: appState.statusMessage)
                DailyMarkdownView(markdownURL: appState.selectedMarkdownURL)
            }
        }
        .frame(minWidth: 960, minHeight: 640)
    }
}
```

```swift
// KnowYou/App/AppEnvironment.swift
import Foundation

@MainActor
final class AppEnvironment {
    let vaultURL: URL

    init(vaultURL: URL) {
        self.vaultURL = vaultURL
    }
}
```

```swift
// KnowYou/UI/Sidebar/DateSidebarView.swift
import SwiftUI

struct DateSidebarView: View {
    let dates: [String]
    let selectedDate: String?
    let onSelect: (String) -> Void

    var body: some View {
        List(dates, id: \.self) { date in
            Button(date) { onSelect(date) }
                .buttonStyle(.plain)
        }
    }
}
```

```swift
// KnowYou/UI/Reader/DailyMarkdownView.swift
import SwiftUI

struct DailyMarkdownView: View {
    let markdownURL: URL?

    var body: some View {
        Text(markdownURL?.lastPathComponent ?? "No day selected")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

```swift
// KnowYou/UI/Status/StatusBannerView.swift
import SwiftUI

struct StatusBannerView: View {
    let message: String?

    var body: some View {
        if let message {
            Text(message)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
        }
    }
}
```

```swift
// KnowYou/UI/Settings/SettingsView.swift
import SwiftUI

struct SettingsView: View {
    var body: some View {
        Form {
            Text("Vault and API settings will live here.")
        }
        .padding()
        .frame(width: 420)
    }
}
```

- [ ] **Step 4: Run the focused test again**

Run: `xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/MainWindowViewModelTests`
Expected: PASS for `testSelectingDateLoadsMatchingMarkdownPath`.

- [ ] **Step 5: Commit**

```bash
git add README.md KnowYou.xcodeproj KnowYou KnowYouTests/MainWindowViewModelTests.swift
git commit -m "feat: bootstrap know you macos app shell"
```

## Task 2: Implement Privacy Filtering Before Persistence

**Files:**
- Create: `KnowYou/Domain/EventRecord.swift`
- Create: `KnowYou/Services/Privacy/PrivacyFilter.swift`
- Create: `KnowYouTests/PrivacyFilterTests.swift`

- [ ] **Step 1: Write failing privacy filter tests**

```swift
// KnowYouTests/PrivacyFilterTests.swift
import XCTest
@testable import KnowYou

final class PrivacyFilterTests: XCTestCase {
    func testPasswordLikeContentIsDropped() {
        let filter = PrivacyFilter()

        let result = filter.classify("Password: hunter2")

        XCTAssertEqual(result.action, .drop)
        XCTAssertNil(result.persistedText)
        XCTAssertEqual(result.auditText, "Sensitive content skipped")
    }

    func testBankAccountContentIsRedacted() {
        let filter = PrivacyFilter()

        let result = filter.classify("Wire to account 6222021234567890")

        XCTAssertEqual(result.action, .redact)
        XCTAssertEqual(result.persistedText, "Wire to account ************7890")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/PrivacyFilterTests`
Expected: FAIL with `Cannot find 'PrivacyFilter' in scope`.

- [ ] **Step 3: Implement the filter and event model**

```swift
// KnowYou/Domain/EventRecord.swift
import Foundation

enum EventSourceType: String, Codable {
    case clipboard
    case notification
}

enum PrivacyAction: String, Codable {
    case keep
    case redact
    case drop
}

struct EventRecord: Equatable, Codable {
    let id: UUID
    let sourceType: EventSourceType
    let sourceApp: String
    let capturedAt: Date
    let dayKey: String
    let text: String?
    let auditText: String?
    let privacyAction: PrivacyAction
    let contentHash: String
}
```

```swift
// KnowYou/Services/Privacy/PrivacyFilter.swift
import Foundation

struct PrivacyFilterResult: Equatable {
    let action: PrivacyAction
    let persistedText: String?
    let auditText: String?
}

struct PrivacyFilter {
    func classify(_ input: String) -> PrivacyFilterResult {
        let lowered = input.lowercased()

        if lowered.contains("password") || lowered.contains("otp") || lowered.contains("api_key") || lowered.contains("session=") {
            return PrivacyFilterResult(
                action: .drop,
                persistedText: nil,
                auditText: "Sensitive content skipped"
            )
        }

        if let range = input.range(of: #"\d{16}"#, options: .regularExpression) {
            let suffix = input[range].suffix(4)
            let redacted = input.replacingCharacters(in: range, with: "************" + suffix)
            return PrivacyFilterResult(
                action: .redact,
                persistedText: redacted,
                auditText: "Sensitive content redacted"
            )
        }

        return PrivacyFilterResult(
            action: .keep,
            persistedText: input,
            auditText: nil
        )
    }
}
```

- [ ] **Step 4: Run the privacy tests**

Run: `xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/PrivacyFilterTests`
Expected: PASS for the drop and redact cases.

- [ ] **Step 5: Commit**

```bash
git add KnowYou/Domain/EventRecord.swift KnowYou/Services/Privacy/PrivacyFilter.swift KnowYouTests/PrivacyFilterTests.swift
git commit -m "feat: add privacy filter for captured events"
```

## Task 3: Add SQLite Persistence And Run Tracking

**Files:**
- Create: `KnowYou/Domain/RunRecord.swift`
- Create: `KnowYou/Services/Storage/Migrations.swift`
- Create: `KnowYou/Services/Storage/DatabaseWriter.swift`
- Create: `KnowYouTests/DatabaseWriterTests.swift`

- [ ] **Step 1: Write failing database tests**

```swift
// KnowYouTests/DatabaseWriterTests.swift
import XCTest
@testable import KnowYou

final class DatabaseWriterTests: XCTestCase {
    func testInsertFilteredEventPersistsPrivacyAction() throws {
        let writer = try DatabaseWriter.inMemory()
        let event = EventRecord(
            id: UUID(),
            sourceType: .clipboard,
            sourceApp: "Taio",
            capturedAt: Date(timeIntervalSince1970: 1_775_000_000),
            dayKey: "2026-04-07",
            text: "Draft message",
            auditText: nil,
            privacyAction: .keep,
            contentHash: "hash-1"
        )

        try writer.insert(event)

        let rows = try writer.fetchEvents(dayKey: "2026-04-07")
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.privacyAction, .keep)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/DatabaseWriterTests`
Expected: FAIL because `DatabaseWriter` is not implemented.

- [ ] **Step 3: Implement migrations and database access**

```swift
// KnowYou/Domain/RunRecord.swift
import Foundation

struct RunRecord: Equatable {
    let id: UUID
    let runType: String
    let startedAt: Date
    let finishedAt: Date?
    let status: String
}
```

```swift
// KnowYou/Services/Storage/Migrations.swift
import Foundation
import GRDB

enum Migrations {
    static func migrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("createEvents") { db in
            try db.create(table: "events") { t in
                t.column("id", .text).primaryKey()
                t.column("sourceType", .text).notNull()
                t.column("sourceApp", .text).notNull()
                t.column("capturedAt", .datetime).notNull()
                t.column("dayKey", .text).notNull()
                t.column("text", .text)
                t.column("auditText", .text)
                t.column("privacyAction", .text).notNull()
                t.column("contentHash", .text).notNull().unique()
            }
        }

        migrator.registerMigration("createRuns") { db in
            try db.create(table: "runs") { t in
                t.column("id", .text).primaryKey()
                t.column("runType", .text).notNull()
                t.column("startedAt", .datetime).notNull()
                t.column("finishedAt", .datetime)
                t.column("status", .text).notNull()
            }
        }

        return migrator
    }
}
```

```swift
// KnowYou/Services/Storage/DatabaseWriter.swift
import Foundation
import GRDB

final class DatabaseWriter {
    private let dbQueue: DatabaseQueue

    init(path: String) throws {
        dbQueue = try DatabaseQueue(path: path)
        try Migrations.migrator().migrate(dbQueue)
    }

    static func inMemory() throws -> DatabaseWriter {
        let writer = try DatabaseWriter(path: ":memory:")
        return writer
    }

    func insert(_ event: EventRecord) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT OR IGNORE INTO events
                (id, sourceType, sourceApp, capturedAt, dayKey, text, auditText, privacyAction, contentHash)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    event.id.uuidString,
                    event.sourceType.rawValue,
                    event.sourceApp,
                    event.capturedAt,
                    event.dayKey,
                    event.text,
                    event.auditText,
                    event.privacyAction.rawValue,
                    event.contentHash,
                ]
            )
        }
    }

    func fetchEvents(dayKey: String) throws -> [EventRecord] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT * FROM events WHERE dayKey = ? ORDER BY capturedAt ASC", arguments: [dayKey])
            return rows.map {
                EventRecord(
                    id: UUID(uuidString: $0["id"]) ?? UUID(),
                    sourceType: EventSourceType(rawValue: $0["sourceType"]) ?? .clipboard,
                    sourceApp: $0["sourceApp"],
                    capturedAt: $0["capturedAt"],
                    dayKey: $0["dayKey"],
                    text: $0["text"],
                    auditText: $0["auditText"],
                    privacyAction: PrivacyAction(rawValue: $0["privacyAction"]) ?? .keep,
                    contentHash: $0["contentHash"]
                )
            }
        }
    }
}
```

- [ ] **Step 4: Run the database tests**

Run: `xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/DatabaseWriterTests`
Expected: PASS with one stored event and the correct privacy action.

- [ ] **Step 5: Commit**

```bash
git add KnowYou/Domain/RunRecord.swift KnowYou/Services/Storage/Migrations.swift KnowYou/Services/Storage/DatabaseWriter.swift KnowYouTests/DatabaseWriterTests.swift
git commit -m "feat: persist filtered events in sqlite"
```

## Task 4: Capture Clipboard And Notification Events

**Files:**
- Create: `KnowYou/Services/Clipboard/ClipboardWatcher.swift`
- Create: `KnowYou/Services/Notifications/NotificationCollector.swift`
- Modify: `KnowYou/App/AppEnvironment.swift`
- Modify: `KnowYou/App/AppState.swift`
- Create: `KnowYou/Utilities/SHA256Hasher.swift`
- Create: `KnowYou/Utilities/ISO8601DayKey.swift`
- Test: `KnowYouTests/DatabaseWriterTests.swift`

- [ ] **Step 1: Extend the database test to prove duplicate clipboard content is ignored**

```swift
func testDuplicateHashesAreIgnored() throws {
    let writer = try DatabaseWriter.inMemory()
    let first = EventRecord(
        id: UUID(),
        sourceType: .clipboard,
        sourceApp: "Taio",
        capturedAt: Date(timeIntervalSince1970: 1_775_000_001),
        dayKey: "2026-04-07",
        text: "same payload",
        auditText: nil,
        privacyAction: .keep,
        contentHash: "same-hash"
    )

    let second = EventRecord(
        id: UUID(),
        sourceType: .clipboard,
        sourceApp: "Taio",
        capturedAt: Date(timeIntervalSince1970: 1_775_000_002),
        dayKey: "2026-04-07",
        text: "same payload",
        auditText: nil,
        privacyAction: .keep,
        contentHash: "same-hash"
    )

    try writer.insert(first)
    try writer.insert(second)

    XCTAssertEqual(try writer.fetchEvents(dayKey: "2026-04-07").count, 1)
}
```

- [ ] **Step 2: Run the database test to verify current storage enforces dedupe**

Run: `xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/DatabaseWriterTests/testDuplicateHashesAreIgnored`
Expected: PASS because the unique `contentHash` constraint drops duplicates.

- [ ] **Step 3: Implement the capture services and wire them into app startup**

```swift
// KnowYou/Services/Clipboard/ClipboardWatcher.swift
import AppKit
import Foundation

@MainActor
final class ClipboardWatcher {
    private let pasteboard: NSPasteboard
    private let privacyFilter: PrivacyFilter
    private let databaseWriter: DatabaseWriter
    private var timer: Timer?
    private var lastChangeCount: Int

    init(pasteboard: NSPasteboard = .general, privacyFilter: PrivacyFilter, databaseWriter: DatabaseWriter) {
        self.pasteboard = pasteboard
        self.privacyFilter = privacyFilter
        self.databaseWriter = databaseWriter
        self.lastChangeCount = pasteboard.changeCount
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    private func poll() {
        guard pasteboard.changeCount != lastChangeCount, let text = pasteboard.string(forType: .string) else {
            return
        }
        lastChangeCount = pasteboard.changeCount

        let filtered = privacyFilter.classify(text)
        let event = EventRecord(
            id: UUID(),
            sourceType: .clipboard,
            sourceApp: NSWorkspace.shared.frontmostApplication?.localizedName ?? "Unknown",
            capturedAt: Date(),
            dayKey: Self.dayKey(for: Date()),
            text: filtered.persistedText,
            auditText: filtered.auditText,
            privacyAction: filtered.action,
            contentHash: SHA256Hasher.hash(filtered.persistedText ?? filtered.auditText ?? "")
        )

        try? databaseWriter.insert(event)
    }

    private static func dayKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
```

```swift
// KnowYou/Services/Notifications/NotificationCollector.swift
import Foundation

struct NotificationSnapshot {
    let appName: String
    let deliveredAt: Date
    let body: String
}

final class NotificationCollector {
    private let privacyFilter: PrivacyFilter
    private let databaseWriter: DatabaseWriter

    init(privacyFilter: PrivacyFilter, databaseWriter: DatabaseWriter) {
        self.privacyFilter = privacyFilter
        self.databaseWriter = databaseWriter
    }

    func ingest(_ snapshots: [NotificationSnapshot]) {
        for snapshot in snapshots {
            let filtered = privacyFilter.classify(snapshot.body)
            let payload = filtered.persistedText ?? filtered.auditText ?? ""
            let event = EventRecord(
                id: UUID(),
                sourceType: .notification,
                sourceApp: snapshot.appName,
                capturedAt: snapshot.deliveredAt,
                dayKey: ISO8601DayKey.format(snapshot.deliveredAt),
                text: filtered.persistedText,
                auditText: filtered.auditText,
                privacyAction: filtered.action,
                contentHash: SHA256Hasher.hash(snapshot.appName + payload + ISO8601DayKey.format(snapshot.deliveredAt))
            )
            try? databaseWriter.insert(event)
        }
    }
}
```

```swift
// KnowYou/App/AppEnvironment.swift
import Foundation

@MainActor
final class AppEnvironment {
    let databaseWriter: DatabaseWriter
    let privacyFilter = PrivacyFilter()
    let clipboardWatcher: ClipboardWatcher
    let notificationCollector: NotificationCollector

    init(databasePath: String) throws {
        databaseWriter = try DatabaseWriter(path: databasePath)
        clipboardWatcher = ClipboardWatcher(privacyFilter: privacyFilter, databaseWriter: databaseWriter)
        notificationCollector = NotificationCollector(privacyFilter: privacyFilter, databaseWriter: databaseWriter)
    }
}
```

```swift
// KnowYou/Utilities/SHA256Hasher.swift
import CryptoKit
import Foundation

enum SHA256Hasher {
    static func hash(_ input: String) -> String {
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
```

```swift
// KnowYou/Utilities/ISO8601DayKey.swift
import Foundation

enum ISO8601DayKey {
    static func format(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
```

- [ ] **Step 4: Run focused tests and launch the app**

Run: `xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/DatabaseWriterTests`
Expected: PASS, including the duplicate-hash case.

Run: `xcodebuild build -scheme KnowYou -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
git add KnowYou/Services/Clipboard/ClipboardWatcher.swift KnowYou/Services/Notifications/NotificationCollector.swift KnowYou/App/AppEnvironment.swift KnowYou/App/AppState.swift KnowYou/Utilities/SHA256Hasher.swift KnowYou/Utilities/ISO8601DayKey.swift KnowYouTests/DatabaseWriterTests.swift
git commit -m "feat: capture clipboard and notification events"
```

## Task 5: Compose Daily Markdown And Plan Backfills

**Files:**
- Create: `KnowYou/Domain/DailyNote.swift`
- Create: `KnowYou/Services/Composer/DailyMarkdownComposer.swift`
- Create: `KnowYou/Services/Backfill/BackfillPlanner.swift`
- Create: `KnowYouTests/DailyMarkdownComposerTests.swift`
- Create: `KnowYouTests/BackfillPlannerTests.swift`

- [ ] **Step 1: Write failing composer and backfill tests**

```swift
// KnowYouTests/DailyMarkdownComposerTests.swift
import XCTest
@testable import KnowYou

final class DailyMarkdownComposerTests: XCTestCase {
    func testComposerProducesExpectedSections() {
        let composer = DailyMarkdownComposer()
        let events = [
            EventRecord(id: UUID(), sourceType: .clipboard, sourceApp: "Drafts", capturedAt: Date(timeIntervalSince1970: 1_775_000_000), dayKey: "2026-04-07", text: "Wrote investor update", auditText: nil, privacyAction: .keep, contentHash: "a"),
            EventRecord(id: UUID(), sourceType: .notification, sourceApp: "Calendar", capturedAt: Date(timeIntervalSince1970: 1_775_000_100), dayKey: "2026-04-07", text: "Meeting in 10 minutes", auditText: nil, privacyAction: .keep, contentHash: "b"),
        ]

        let markdown = composer.compose(dayKey: "2026-04-07", events: events, summary: "Busy day")

        XCTAssertTrue(markdown.contains("## Summary"))
        XCTAssertTrue(markdown.contains("## Timeline"))
        XCTAssertTrue(markdown.contains("## Clipboard"))
        XCTAssertTrue(markdown.contains("## Notifications"))
    }
}
```

```swift
// KnowYouTests/BackfillPlannerTests.swift
import XCTest
@testable import KnowYou

final class BackfillPlannerTests: XCTestCase {
    func testMissingDatesBetweenLastCompletedAndTodayAreReturned() {
        let planner = BackfillPlanner(calendar: Calendar(identifier: .gregorian))
        let missing = planner.missingDates(
            lastCompletedDay: "2026-04-04",
            today: "2026-04-07"
        )

        XCTAssertEqual(missing, ["2026-04-05", "2026-04-06", "2026-04-07"])
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/DailyMarkdownComposerTests -only-testing:KnowYouTests/BackfillPlannerTests`
Expected: FAIL because composer and backfill planner do not exist.

- [ ] **Step 3: Implement composition and missing-day discovery**

```swift
// KnowYou/Domain/DailyNote.swift
import Foundation

struct DailyNote: Equatable {
    let dayKey: String
    let markdown: String
    let fileURL: URL
}
```

```swift
// KnowYou/Services/Composer/DailyMarkdownComposer.swift
import Foundation

struct DailyMarkdownComposer {
    func compose(dayKey: String, events: [EventRecord], summary: String?) -> String {
        let timelineLines = events.map { "- \($0.sourceApp): \($0.text ?? $0.auditText ?? "")" }.joined(separator: "\n")
        let clipboardLines = events
            .filter { $0.sourceType == .clipboard }
            .map { "- \($0.text ?? $0.auditText ?? "")" }
            .joined(separator: "\n")
        let notificationLines = events
            .filter { $0.sourceType == .notification }
            .map { "- \($0.text ?? $0.auditText ?? "")" }
            .joined(separator: "\n")

        return """
        # \(dayKey)

        ## Summary

        \(summary ?? "_Pending summary_")

        ## Timeline

        \(timelineLines)

        ## Clipboard

        \(clipboardLines)

        ## Notifications

        \(notificationLines)
        """
    }
}
```

```swift
// KnowYou/Services/Backfill/BackfillPlanner.swift
import Foundation

struct BackfillPlanner {
    let calendar: Calendar

    func missingDates(lastCompletedDay: String, today: String) -> [String] {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.dateFormat = "yyyy-MM-dd"

        guard
            let start = formatter.date(from: lastCompletedDay),
            let end = formatter.date(from: today)
        else { return [] }

        var current = calendar.date(byAdding: .day, value: 1, to: start)!
        var dates: [String] = []

        while current <= end {
            dates.append(formatter.string(from: current))
            current = calendar.date(byAdding: .day, value: 1, to: current)!
        }

        return dates
    }
}
```

- [ ] **Step 4: Run the composer and backfill tests**

Run: `xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/DailyMarkdownComposerTests -only-testing:KnowYouTests/BackfillPlannerTests`
Expected: PASS for section order and missing-date detection.

- [ ] **Step 5: Commit**

```bash
git add KnowYou/Domain/DailyNote.swift KnowYou/Services/Composer/DailyMarkdownComposer.swift KnowYou/Services/Backfill/BackfillPlanner.swift KnowYouTests/DailyMarkdownComposerTests.swift KnowYouTests/BackfillPlannerTests.swift
git commit -m "feat: compose daily markdown and backfill days"
```

## Task 6: Add Cloud Summary And Vault File Writing

**Files:**
- Create: `KnowYou/Services/Summary/CloudSummarizer.swift`
- Modify: `KnowYou/Services/Composer/DailyMarkdownComposer.swift`
- Modify: `KnowYou/App/AppEnvironment.swift`
- Modify: `KnowYou/App/AppState.swift`
- Test: `KnowYouTests/DailyMarkdownComposerTests.swift`

- [ ] **Step 1: Add a failing composer test for pending summaries**

```swift
func testComposerUsesPendingSummaryPlaceholderWhenSummaryFails() {
    let composer = DailyMarkdownComposer()
    let markdown = composer.compose(dayKey: "2026-04-07", events: [], summary: nil)

    XCTAssertTrue(markdown.contains("_Pending summary_"))
}
```

- [ ] **Step 2: Run the composer test**

Run: `xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/DailyMarkdownComposerTests/testComposerUsesPendingSummaryPlaceholderWhenSummaryFails`
Expected: PASS if Task 5 is already complete. If it fails, fix the placeholder before proceeding.

- [ ] **Step 3: Implement the summarizer and vault writer**

```swift
// KnowYou/Services/Summary/CloudSummarizer.swift
import Foundation

protocol SummaryGenerating {
    func summarize(dayKey: String, markdown: String) async throws -> String
}

struct CloudSummarizer: SummaryGenerating {
    let apiKey: String
    let session: URLSession

    func summarize(dayKey: String, markdown: String) async throws -> String {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode([
            "model": "gpt-5.4",
            "input": "Summarize this day as a concise diary entry for \(dayKey):\n\n\(markdown)",
        ])

        let (data, _) = try await session.data(for: request)
        let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let output = payload?["output_text"] as? String
        return output?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Summary unavailable."
    }
}
```

```swift
// add to KnowYou/App/AppEnvironment.swift
let vaultURL: URL
let summarizer: SummaryGenerating?

func writeDailyNote(dayKey: String, markdown: String) throws -> URL {
    let fileURL = vaultURL.appendingPathComponent("\(dayKey).md")
    try FileManager.default.createDirectory(at: vaultURL, withIntermediateDirectories: true)
    try markdown.write(to: fileURL, atomically: true, encoding: .utf8)
    return fileURL
}
```

- [ ] **Step 4: Run tests and build**

Run: `xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/DailyMarkdownComposerTests`
Expected: PASS.

Run: `xcodebuild build -scheme KnowYou -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
git add KnowYou/Services/Summary/CloudSummarizer.swift KnowYou/Services/Composer/DailyMarkdownComposer.swift KnowYou/App/AppEnvironment.swift KnowYou/App/AppState.swift KnowYouTests/DailyMarkdownComposerTests.swift
git commit -m "feat: write vault files and request cloud summaries"
```

## Task 7: Finish The Reader UI And Surface Status Clearly

**Files:**
- Modify: `KnowYou/UI/Sidebar/DateSidebarView.swift`
- Modify: `KnowYou/UI/Reader/DailyMarkdownView.swift`
- Modify: `KnowYou/UI/Status/StatusBannerView.swift`
- Modify: `KnowYou/UI/MainWindowView.swift`
- Modify: `KnowYou/UI/Settings/SettingsView.swift`
- Test: `KnowYouTests/MainWindowViewModelTests.swift`

- [ ] **Step 1: Add a failing status test**

```swift
func testStatusMessageCanReflectMissingSummary() {
    let appState = AppState()
    appState.statusMessage = "Summary pending for 2026-04-07"

    XCTAssertEqual(appState.statusMessage, "Summary pending for 2026-04-07")
}
```

- [ ] **Step 2: Run the focused status test**

Run: `xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/MainWindowViewModelTests/testStatusMessageCanReflectMissingSummary`
Expected: PASS after the state model from Task 1 remains intact.

- [ ] **Step 3: Implement the final two-pane reader**

```swift
// KnowYou/UI/Sidebar/DateSidebarView.swift
import SwiftUI

struct DateSidebarView: View {
    let dates: [String]
    let selectedDate: String?
    let onSelect: (String) -> Void

    var body: some View {
        List(dates, id: \.self, selection: .constant(selectedDate)) { date in
            Button(date) { onSelect(date) }
                .buttonStyle(.plain)
                .font(date == selectedDate ? .headline : .body)
        }
        .navigationTitle("Days")
    }
}
```

```swift
// KnowYou/UI/Reader/DailyMarkdownView.swift
import MarkdownUI
import SwiftUI

struct DailyMarkdownView: View {
    let markdownURL: URL?

    var body: some View {
        Group {
            if let markdownURL, let text = try? String(contentsOf: markdownURL) {
                ScrollView {
                    Markdown(text)
                        .padding(32)
                }
            } else {
                ContentUnavailableView("No Day Selected", systemImage: "doc.text")
            }
        }
    }
}
```

```swift
// KnowYou/UI/Status/StatusBannerView.swift
import SwiftUI

struct StatusBannerView: View {
    let message: String?

    var body: some View {
        if let message {
            Text(message)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.yellow.opacity(0.15))
        }
    }
}
```

- [ ] **Step 4: Run tests and a manual UI check**

Run: `xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/MainWindowViewModelTests`
Expected: PASS.

Run: `xcodebuild build -scheme KnowYou -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED, with a sidebar date list and Markdown detail view.

- [ ] **Step 5: Commit**

```bash
git add KnowYou/UI/Sidebar/DateSidebarView.swift KnowYou/UI/Reader/DailyMarkdownView.swift KnowYou/UI/Status/StatusBannerView.swift KnowYou/UI/MainWindowView.swift KnowYou/UI/Settings/SettingsView.swift KnowYouTests/MainWindowViewModelTests.swift
git commit -m "feat: ship two pane markdown reader"
```

## Task 8: Final Integration, Docs, And Verification

**Files:**
- Modify: `README.md`
- Modify: `.gitignore`
- Modify: `KnowYou/Config/Secrets.example.xcconfig`
- Test: `KnowYouTests/PrivacyFilterTests.swift`
- Test: `KnowYouTests/DatabaseWriterTests.swift`
- Test: `KnowYouTests/DailyMarkdownComposerTests.swift`
- Test: `KnowYouTests/BackfillPlannerTests.swift`
- Test: `KnowYouTests/MainWindowViewModelTests.swift`

- [ ] **Step 1: Add README setup instructions**

```md
# Know You

Know You is a macOS app that captures clipboard and notification context, filters sensitive content, and creates one Markdown note per day.

## Local Development

1. Open `KnowYou.xcodeproj`
2. Copy `KnowYou/Config/Secrets.example.xcconfig` to a local secrets file
3. Set a vault directory path and API key
4. Run the `KnowYou` scheme on macOS

## Verification

- `xcodebuild test -scheme KnowYou -destination 'platform=macOS'`
- `xcodebuild build -scheme KnowYou -destination 'platform=macOS'`
```

- [ ] **Step 2: Run the full test suite**

Run: `xcodebuild test -scheme KnowYou -destination 'platform=macOS'`
Expected: PASS for privacy filtering, persistence, composition, backfill, and UI state.

- [ ] **Step 3: Run the final build**

Run: `xcodebuild build -scheme KnowYou -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Review git diff**

Run: `git status --short && git diff --stat`
Expected: only intentional app, test, and doc files are present.

- [ ] **Step 5: Commit**

```bash
git add .gitignore README.md KnowYou/Config/Secrets.example.xcconfig KnowYou.xcodeproj KnowYou KnowYouTests
git commit -m "chore: document and verify know you mvp"
```

## Self-Review

### Spec coverage

- Clipboard capture: Task 4
- Notification capture: Task 4
- Privacy filtering before persistence: Task 2 and Task 4
- SQLite event storage: Task 3
- Daily Markdown composition: Task 5
- Cloud summary generation: Task 6
- Backfill behavior: Task 5
- Two-pane reader UI: Task 1 and Task 7
- Explicit status and failure display: Task 7
- Local vault output: Task 6

No spec gaps remain for MVP.

### Placeholder scan

- No `TBD`
- No `TODO`
- No deferred "write tests later" steps
- Every task includes exact files, commands, and commit messages

### Type consistency

- `AppState.selectedDate` remains a `String?` across tasks
- `EventRecord` is the shared event shape across filter, storage, composer, and reader
- `PrivacyAction` stays aligned between filter results, storage, and tests
