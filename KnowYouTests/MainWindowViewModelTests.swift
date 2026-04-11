import XCTest
@testable import KnowYou

private struct ThrowingSummarizer: SummaryGenerating {
    func summarize(dayKey: String, markdown: String) async throws -> String {
        throw URLError(.cannotConnectToHost)
    }
}

private struct StaticSummarizer: SummaryGenerating {
    let response: String

    func summarize(dayKey: String, markdown: String) async throws -> String {
        response
    }
}

private final class RecordingNotificationReader: NotificationDatabaseReading, @unchecked Sendable {
    private(set) var requestedSince: Date?
    var snapshots: [NotificationSnapshot] = []
    var fetchError: Error?

    func fetchDeliveredNotifications(since: Date) throws -> [NotificationSnapshot] {
        requestedSince = since
        if let fetchError {
            throw fetchError
        }
        return snapshots
    }
}

private final class AppStateTestKeychainStore: KeychainStoring, @unchecked Sendable {
    private var values: [String: String] = [:]

    func save(_ value: String, forKey key: String, service: String) {
        values["\(service):\(key)"] = value
    }

    func load(forKey key: String, service: String) -> String? {
        values["\(service):\(key)"]
    }

    func delete(forKey key: String, service: String) {
        values.removeValue(forKey: "\(service):\(key)")
    }
}

private actor ProbeGate {
    private var hasStarted = false
    private var startedContinuation: CheckedContinuation<Void, Never>?
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func markStarted() {
        hasStarted = true
        startedContinuation?.resume()
        startedContinuation = nil
    }

    func waitUntilStarted() async {
        guard !hasStarted else { return }
        await withCheckedContinuation { continuation in
            startedContinuation = continuation
        }
    }

    func waitForRelease() async {
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

private actor ProbeStartTracker {
    private var started: Set<DiaryEngine> = []
    private var waiters: [(Set<DiaryEngine>, CheckedContinuation<Void, Never>)] = []

    func markStarted(_ engine: DiaryEngine) {
        started.insert(engine)
        var remaining: [(Set<DiaryEngine>, CheckedContinuation<Void, Never>)] = []
        for (required, continuation) in waiters {
            if required.isSubset(of: started) {
                continuation.resume()
            } else {
                remaining.append((required, continuation))
            }
        }
        waiters = remaining
    }

    func waitUntilStarted(_ engines: Set<DiaryEngine>) async {
        guard !engines.isSubset(of: started) else { return }
        await withCheckedContinuation { continuation in
            waiters.append((engines, continuation))
        }
    }
}

@MainActor
final class MainWindowViewModelTests: XCTestCase {
    private var engineDefaultsSuiteName: String!
    private var engineDefaults: UserDefaults!
    private var engineKeychain: AppStateTestKeychainStore!

    override func setUp() {
        super.setUp()
        engineDefaultsSuiteName = "MainWindowViewModelTests-\(UUID().uuidString)"
        engineDefaults = UserDefaults(suiteName: engineDefaultsSuiteName)!
        engineKeychain = AppStateTestKeychainStore()
    }

    override func tearDown() {
        if let engineDefaultsSuiteName {
            engineDefaults.removePersistentDomain(forName: engineDefaultsSuiteName)
        }
        super.tearDown()
    }

    func testSelectingDateLoadsMatchingMarkdownPath() {
        let appState = AppState(bootstrapServices: false)
        appState.availableDates = ["2026-04-07", "2026-04-06"]
        appState.noteIndex = [
            "2026-04-07": URL(fileURLWithPath: "/tmp/2026-04-07.md"),
            "2026-04-06": URL(fileURLWithPath: "/tmp/2026-04-06.md"),
        ]

        appState.selectDate("2026-04-06")

        XCTAssertEqual(appState.selectedDate, "2026-04-06")
        XCTAssertEqual(appState.selectedMarkdownURL?.path, "/tmp/2026-04-06.md")
    }

    func testSelectingDateWithoutIndexedFileClearsMarkdownPath() {
        let appState = AppState(bootstrapServices: false)
        appState.selectedMarkdownURL = URL(fileURLWithPath: "/tmp/existing.md")

        appState.selectDate("2026-04-08")

        XCTAssertEqual(appState.selectedDate, "2026-04-08")
        XCTAssertNil(appState.selectedMarkdownURL)
    }

    func testSelectingDateLoadsSourceNotesMarkdownFromSavedFile() throws {
        let environment = try makeReaderEnvironment()
        let appState = AppState(environment: environment)

        appState.selectDate("2026-04-08")

        XCTAssertEqual(
            appState.selectedSourceNotesMarkdown,
            """
            ## Source Notes

            - [09:00] Notes (clipboard): Important note
            - [09:15] Mail (notification): Investor replied

            Saved in the source notebook.
            """
        )
    }

    func testSelectingDateFallsBackToGeneratedSourceNotesWhenMarkdownFileIsMissing() throws {
        let environment = try makeReaderEnvironment()
        let appState = AppState(environment: environment)
        let fileURL = environment.vaultURL.appending(path: "2026-04-08.md")
        try FileManager.default.removeItem(at: fileURL)

        appState.selectDate("2026-04-08")

        XCTAssertEqual(
            appState.selectedSourceNotesMarkdown,
            """
            ## Source Notes

            - [09:00] Notes (clipboard): Important note
            - [09:15] Mail (notification): Investor replied
            """
        )
    }

    func testSelectingDateFallsBackToGeneratedSourceNotesWhenSavedMarkdownHasNoSourceNotesSection() throws {
        let environment = try makeReaderEnvironment()
        let appState = AppState(environment: environment)
        let fileURL = environment.vaultURL.appending(path: "2026-04-08.md")
        try """
        # 2026-04-08

        ## Story

        First paragraph with **bold** emphasis.

        ## Appendix

        This file was saved without source notes.
        """.write(to: fileURL, atomically: true, encoding: .utf8)

        appState.selectDate("2026-04-08")

        XCTAssertEqual(
            appState.selectedSourceNotesMarkdown,
            """
            ## Source Notes

            - [09:00] Notes (clipboard): Important note
            - [09:15] Mail (notification): Investor replied
            """
        )
    }

    func testSelectingChineseDateLoadsLocalizedSourceNotesMarkdown() throws {
        let environment = try makeChineseReaderEnvironment()
        let appState = AppState(environment: environment)

        appState.selectDate("2026-04-09")

        XCTAssertEqual(
            appState.selectedSourceNotesMarkdown,
            """
            ## 线索来源

            - [10:00] 微信 (clipboard): 今天要先处理发货
            - [10:15] 邮件 (notification): 客户确认了收货时间
            """
        )
    }

    func testSelectingChineseDateFallsBackToLocalizedGeneratedSourceNotesWhenMarkdownFileIsMissing() throws {
        let environment = try makeChineseReaderEnvironment()
        let appState = AppState(environment: environment)
        let fileURL = environment.vaultURL.appending(path: "2026-04-09.md")
        try FileManager.default.removeItem(at: fileURL)

        appState.selectDate("2026-04-09")

        XCTAssertEqual(
            appState.selectedSourceNotesMarkdown,
            """
            ## 线索来源

            - [10:00] 微信 (clipboard): 今天要先处理发货
            - [10:15] 邮件 (notification): 客户确认了收货时间
            """
        )
    }

    func testAutomationStatusTextReflectsBackfillDays() {
        let appState = AppState(bootstrapServices: false)
        appState.lastImportedNotificationCount = 3
        appState.pendingBackfillDays = ["2026-04-06", "2026-04-07"]

        XCTAssertTrue(appState.automationStatusText.contains("Notifications: 3"))
        XCTAssertTrue(appState.automationStatusText.contains("2026-04-06"))
        XCTAssertTrue(appState.automationStatusText.contains("2026-04-07"))
    }

    func testGenerateDailyNotePersistsMarkdownWhenSummarizerFails() async throws {
        let writer = try DatabaseWriter.inMemory()
        let capturedAt = Date(timeIntervalSince1970: 1_775_000_000)
        try writer.insert(
            EventRecord(
                id: UUID(),
                sourceType: .clipboard,
                sourceApp: "Notes",
                capturedAt: capturedAt,
                dayKey: "2026-04-07",
                text: "Ship feature",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "note-hash"
            )
        )

        let vaultURL = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let environment = AppEnvironment(
            databaseURL: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).sqlite"),
            vaultURL: vaultURL,
            databaseWriter: writer,
            summarizer: ThrowingSummarizer(),
            notificationReader: RecordingNotificationReader(),
            dailyAutomationPlanner: DailyAutomationPlanner(
                backfillPlanner: BackfillPlanner(calendar: Calendar(identifier: .gregorian))
            )
        )
        let appState = AppState(environment: environment)

        await appState.generateDailyNote(for: "2026-04-07")

        let savedURL = vaultURL.appending(path: "2026-04-07.md")
        let storyURL = vaultURL.appending(path: "2026-04-07.story.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: savedURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: storyURL.path))
        XCTAssertEqual(appState.statusMessage, "Refreshed 2026-04-07; story fell back to local summary")
        XCTAssertEqual(appState.summarizerStatus.lastError, URLError(.cannotConnectToHost).localizedDescription)
        XCTAssertEqual(appState.selectedStory?.dayKey, "2026-04-07")
        XCTAssertEqual(appState.selectedStoryParagraphID, appState.selectedStory?.sections.first?.paragraphs.first?.id)
        XCTAssertFalse(appState.selectedStorySourceEvents.isEmpty)
        XCTAssertEqual(try writer.fetchRuns(runType: "daily-note").last?.status, "succeeded")
    }

    func testRunAutomationImportsNotificationsFromOldestPendingDay() async throws {
        let writer = try DatabaseWriter.inMemory()
        let completedRun = try writer.startRun(runType: "daily-note", dayKey: "2026-04-01")
        try writer.finishRun(id: completedRun, status: "succeeded")

        let reader = RecordingNotificationReader()
        let vaultURL = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let environment = AppEnvironment(
            databaseURL: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).sqlite"),
            vaultURL: vaultURL,
            databaseWriter: writer,
            summarizer: nil,
            notificationReader: reader,
            dailyAutomationPlanner: DailyAutomationPlanner(
                backfillPlanner: BackfillPlanner(calendar: Calendar(identifier: .gregorian))
            )
        )
        let appState = AppState(environment: environment)

        await appState.runAutomation(now: DateComponents(calendar: Calendar(identifier: .gregorian), year: 2026, month: 4, day: 7).date!)

        XCTAssertEqual(
            ISO8601DayKey.format(reader.requestedSince ?? .distantPast),
            "2026-04-02"
        )
    }

    func testRunAutomationRebuildsTodayEvenWhenNoteAlreadyExists() async throws {
        let writer = try DatabaseWriter.inMemory()
        let today = "2026-04-07"
        let capturedAt = DateComponents(
            calendar: Calendar(identifier: .gregorian),
            year: 2026,
            month: 4,
            day: 7,
            hour: 9
        ).date!

        try writer.insert(
            EventRecord(
                id: UUID(),
                sourceType: .clipboard,
                sourceApp: "Notes",
                capturedAt: capturedAt,
                dayKey: today,
                text: "Fresh clipboard entry",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "fresh-entry"
            )
        )

        let vaultURL = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: vaultURL, withIntermediateDirectories: true)
        let existingNoteURL = vaultURL.appending(path: "\(today).md")
        try "stale note".write(to: existingNoteURL, atomically: true, encoding: .utf8)

        let environment = AppEnvironment(
            databaseURL: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).sqlite"),
            vaultURL: vaultURL,
            databaseWriter: writer,
            summarizer: nil,
            notificationReader: RecordingNotificationReader(),
            dailyAutomationPlanner: DailyAutomationPlanner(
                backfillPlanner: BackfillPlanner(calendar: Calendar(identifier: .gregorian))
            )
        )
        let appState = AppState(environment: environment)

        await appState.runAutomation(now: capturedAt)

        let rebuiltMarkdown = try String(contentsOf: existingNoteURL)
        XCTAssertTrue(rebuiltMarkdown.contains("Fresh clipboard entry"))
        XCTAssertEqual(appState.selectedDate, today)
        XCTAssertEqual(try writer.fetchRuns(runType: "daily-note").last?.dayKey, today)
    }

    func testRefreshSelectedDayUsesTodayWhenNoSelectionExists() async throws {
        let writer = try DatabaseWriter.inMemory()
        let reader = RecordingNotificationReader()
        let now = DateComponents(calendar: Calendar(identifier: .gregorian), year: 2026, month: 4, day: 7, hour: 10).date!
        let dayKey = ISO8601DayKey.format(now)
        try writer.insert(
            EventRecord(
                id: UUID(),
                sourceType: .clipboard,
                sourceApp: "Notes",
                capturedAt: now,
                dayKey: dayKey,
                text: "Today event",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "today-event"
            )
        )
        reader.snapshots = [
            NotificationSnapshot(appName: "Calendar", deliveredAt: now, body: "Standup in 5")
        ]

        let vaultURL = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let environment = AppEnvironment(
            databaseURL: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).sqlite"),
            vaultURL: vaultURL,
            databaseWriter: writer,
            summarizer: nil,
            notificationReader: reader,
            dailyAutomationPlanner: DailyAutomationPlanner(
                backfillPlanner: BackfillPlanner(calendar: Calendar(identifier: .gregorian))
            )
        )
        let appState = AppState(environment: environment)

        await appState.refreshSelectedDay(now: now)

        XCTAssertEqual(appState.selectedDate, dayKey)
        XCTAssertEqual(appState.notificationStatus.lastImportedCount, 1)
        XCTAssertEqual(appState.statusMessage, "Imported 1 notifications and refreshed today")
    }

    func testRefreshSelectedDayForHistoricalSelectionSkipsNotificationImport() async throws {
        let writer = try DatabaseWriter.inMemory()
        let reader = RecordingNotificationReader()
        let historicalDay = "2026-04-06"
        let capturedAt = DateComponents(calendar: Calendar(identifier: .gregorian), year: 2026, month: 4, day: 6, hour: 9).date!
        try writer.insert(
            EventRecord(
                id: UUID(),
                sourceType: .clipboard,
                sourceApp: "Notes",
                capturedAt: capturedAt,
                dayKey: historicalDay,
                text: "Backfill me",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "historical-event"
            )
        )

        let vaultURL = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let environment = AppEnvironment(
            databaseURL: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).sqlite"),
            vaultURL: vaultURL,
            databaseWriter: writer,
            summarizer: nil,
            notificationReader: reader,
            dailyAutomationPlanner: DailyAutomationPlanner(
                backfillPlanner: BackfillPlanner(calendar: Calendar(identifier: .gregorian))
            )
        )
        let appState = AppState(environment: environment)
        appState.selectDate(historicalDay)

        await appState.refreshSelectedDay(now: DateComponents(calendar: Calendar(identifier: .gregorian), year: 2026, month: 4, day: 7).date!)

        XCTAssertNil(reader.requestedSince)
        XCTAssertEqual(appState.statusMessage, "Refreshed 2026-04-06")
    }

    func testReaderNavigationRestoresPerDayParagraphMemory() throws {
        let environment = try makeReaderEnvironment()
        let appState = AppState(environment: environment)
        appState.refreshNotesIndex()

        XCTAssertEqual(appState.readerFocus, .dateList)
        XCTAssertEqual(appState.selectedDate, "2026-04-08")

        appState.handleReaderMove(.right)
        appState.selectStoryParagraph("daily-journal-1")
        XCTAssertEqual(appState.readerFocus, .storyParagraphs)
        XCTAssertEqual(appState.selectedStoryParagraphID, "daily-journal-1")

        appState.handleReaderMove(.left)
        XCTAssertEqual(appState.readerFocus, .dateList)

        appState.handleReaderMove(.down)
        XCTAssertEqual(appState.selectedDate, "2026-04-07")
        appState.handleReaderMove(.right)
        XCTAssertEqual(appState.readerFocus, .storyParagraphs)
        XCTAssertEqual(appState.selectedStoryParagraphID, "daily-journal-0")

        appState.handleReaderMove(.left)
        appState.handleReaderMove(.up)
        XCTAssertEqual(appState.selectedDate, "2026-04-08")
        appState.handleReaderMove(.right)
        XCTAssertEqual(appState.selectedStoryParagraphID, "daily-journal-1")
    }

    func testEscapeReturnsStoryFocusToDateList() throws {
        let environment = try makeReaderEnvironment()
        let appState = AppState(environment: environment)
        appState.refreshNotesIndex()

        appState.handleReaderMove(.right)
        XCTAssertEqual(appState.readerFocus, .storyParagraphs)

        appState.handleReaderExit()

        XCTAssertEqual(appState.readerFocus, .dateList)
        XCTAssertEqual(appState.selectedDate, "2026-04-08")
    }

    func testStatusDetailsExplainClipboardAndNotificationSources() {
        let appState = AppState(bootstrapServices: false)
        appState.clipboardStatus.isActive = true
        appState.notificationStatus.isDatabaseAvailable = false
        appState.notificationStatus.availabilityMessage = "Notification Center database not found on this Mac."

        let details = appState.statusDetails

        XCTAssertTrue(details.contains(where: { $0.localizedCaseInsensitiveContains("pasteboard") }))
        XCTAssertTrue(details.contains(where: { $0.localizedCaseInsensitiveContains("not maccy") }))
        XCTAssertTrue(details.contains(where: { $0.localizedCaseInsensitiveContains("notification center") }))
    }

    private func makeReaderEnvironment() throws -> AppEnvironment {
        let writer = try DatabaseWriter.inMemory()
        let vaultURL = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: vaultURL, withIntermediateDirectories: true)

        let environment = AppEnvironment(
            databaseURL: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).sqlite"),
            vaultURL: vaultURL,
            databaseWriter: writer,
            summarizer: nil,
            notificationReader: RecordingNotificationReader(),
            dailyAutomationPlanner: DailyAutomationPlanner(
                backfillPlanner: BackfillPlanner(calendar: Calendar(identifier: .gregorian))
            )
        )

        let firstID = UUID()
        let secondID = UUID()
        let baseCalendar = Calendar(identifier: .gregorian)
        try writer.insert(
            EventRecord(
                id: firstID,
                sourceType: .clipboard,
                sourceApp: "Notes",
                capturedAt: DateComponents(calendar: baseCalendar, year: 2026, month: 4, day: 8, hour: 9, minute: 0).date!,
                dayKey: "2026-04-08",
                text: "Important note",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "source-note-first"
            )
        )
        try writer.insert(
            EventRecord(
                id: secondID,
                sourceType: .notification,
                sourceApp: "Mail",
                capturedAt: DateComponents(calendar: baseCalendar, year: 2026, month: 4, day: 8, hour: 9, minute: 15).date!,
                dayKey: "2026-04-08",
                text: "Investor replied",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "source-note-second"
            )
        )

        try writeStoryDay(
            dayKey: "2026-04-08",
            markdown: """
            # 2026-04-08

            ## Story

            First paragraph with **bold** emphasis.

            Second paragraph with a [link](https://example.com).

            ---

            ## Source Notes

            - [09:00] Notes (clipboard): Important note
            - [09:15] Mail (notification): Investor replied

            Saved in the source notebook.
            """,
            story: DailyStory(
                dayKey: "2026-04-08",
                generatedAt: Date(timeIntervalSince1970: 1_775_000_000),
                sections: [
                    DailyStorySection(
                        id: "daily-journal",
                        title: "",
                        paragraphs: [
                            DailyStoryParagraph(id: "daily-journal-0", text: "First paragraph with **bold** emphasis.", sourceEventIDs: [firstID]),
                            DailyStoryParagraph(id: "daily-journal-1", text: "Second paragraph with a [link](https://example.com).", sourceEventIDs: [secondID]),
                        ]
                    )
                ]
            ),
            environment: environment
        )

        try writeStoryDay(
            dayKey: "2026-04-07",
            markdown: "# 2026-04-07\n\nStory",
            story: DailyStory(
                dayKey: "2026-04-07",
                generatedAt: Date(timeIntervalSince1970: 1_775_000_000),
                sections: [
                    DailyStorySection(
                        id: "daily-journal",
                        title: "",
                        paragraphs: [
                            DailyStoryParagraph(id: "daily-journal-0", text: "Only paragraph", sourceEventIDs: [UUID()])
                        ]
                    )
                ]
            ),
            environment: environment
        )

        return environment
    }

    private func makeChineseReaderEnvironment() throws -> AppEnvironment {
        let writer = try DatabaseWriter.inMemory()
        let vaultURL = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: vaultURL, withIntermediateDirectories: true)

        let environment = AppEnvironment(
            databaseURL: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).sqlite"),
            vaultURL: vaultURL,
            databaseWriter: writer,
            summarizer: nil,
            notificationReader: RecordingNotificationReader(),
            dailyAutomationPlanner: DailyAutomationPlanner(
                backfillPlanner: BackfillPlanner(calendar: Calendar(identifier: .gregorian))
            )
        )

        let firstID = UUID()
        let secondID = UUID()
        let baseCalendar = Calendar(identifier: .gregorian)
        try writer.insert(
            EventRecord(
                id: firstID,
                sourceType: .clipboard,
                sourceApp: "微信",
                capturedAt: DateComponents(calendar: baseCalendar, year: 2026, month: 4, day: 9, hour: 10, minute: 0).date!,
                dayKey: "2026-04-09",
                text: "今天要先处理发货",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "cn-source-note-first"
            )
        )
        try writer.insert(
            EventRecord(
                id: secondID,
                sourceType: .notification,
                sourceApp: "邮件",
                capturedAt: DateComponents(calendar: baseCalendar, year: 2026, month: 4, day: 9, hour: 10, minute: 15).date!,
                dayKey: "2026-04-09",
                text: "客户确认了收货时间",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "cn-source-note-second"
            )
        )

        try writeStoryDay(
            dayKey: "2026-04-09",
            markdown: """
            # 2026-04-09

            ## 今日小记

            上午主要在处理发货和确认时间。

            ---

            ## 线索来源

            - [10:00] 微信 (clipboard): 今天要先处理发货
            - [10:15] 邮件 (notification): 客户确认了收货时间
            """,
            story: DailyStory(
                dayKey: "2026-04-09",
                generatedAt: Date(timeIntervalSince1970: 1_775_000_000),
                sections: [
                    DailyStorySection(
                        id: "daily-journal",
                        title: "",
                        paragraphs: [
                            DailyStoryParagraph(id: "daily-journal-0", text: "上午主要在处理发货和确认时间。", sourceEventIDs: [firstID, secondID]),
                        ]
                    )
                ]
            ),
            environment: environment
        )

        return environment
    }

    private func writeStoryDay(dayKey: String, markdown: String, story: DailyStory, environment: AppEnvironment) throws {
        _ = try environment.writeDailyNote(dayKey: dayKey, markdown: markdown)
        _ = try environment.writeDailyStory(story)
    }

    func testRunAutomationSurfacesNotificationImportError() async throws {
        let writer = try DatabaseWriter.inMemory()
        let reader = RecordingNotificationReader()
        reader.fetchError = CocoaError(.fileReadUnknown)

        let vaultURL = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let environment = AppEnvironment(
            databaseURL: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).sqlite"),
            vaultURL: vaultURL,
            databaseWriter: writer,
            summarizer: nil,
            notificationReader: reader,
            dailyAutomationPlanner: DailyAutomationPlanner(
                backfillPlanner: BackfillPlanner(calendar: Calendar(identifier: .gregorian))
            )
        )
        let appState = AppState(environment: environment)

        await appState.runAutomation(now: DateComponents(calendar: Calendar(identifier: .gregorian), year: 2026, month: 4, day: 7).date!)

        XCTAssertEqual(appState.notificationStatus.lastError, CocoaError(.fileReadUnknown).localizedDescription)
    }

    func testRefreshSelectedDayDoesNotMaskTodayGenerationFailure() async throws {
        let writer = try DatabaseWriter.inMemory()
        let now = DateComponents(calendar: Calendar(identifier: .gregorian), year: 2026, month: 4, day: 7, hour: 10).date!
        let dayKey = ISO8601DayKey.format(now)
        try writer.insert(
            EventRecord(
                id: UUID(),
                sourceType: .clipboard,
                sourceApp: "Notes",
                capturedAt: now,
                dayKey: dayKey,
                text: "Today event",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "today-failure"
            )
        )

        let vaultFileURL = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try "not a directory".write(to: vaultFileURL, atomically: true, encoding: .utf8)

        let environment = AppEnvironment(
            databaseURL: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).sqlite"),
            vaultURL: vaultFileURL,
            databaseWriter: writer,
            summarizer: nil,
            notificationReader: RecordingNotificationReader(),
            dailyAutomationPlanner: DailyAutomationPlanner(
                backfillPlanner: BackfillPlanner(calendar: Calendar(identifier: .gregorian))
            )
        )
        let appState = AppState(environment: environment)

        await appState.refreshSelectedDay(now: now)

        XCTAssertTrue(appState.statusMessage?.contains("Daily note failed:") == true)
        XCTAssertNotNil(appState.dayRefreshStatus.lastError)
    }

    func testRefreshServiceStatusesPreservesSummarizerRuntimeHistory() {
        var config = SummarizerConfig.default
        config.defaultEngine = .openAI
        let appState = AppState(
            bootstrapServices: false,
            summarizerConfig: config,
            userDefaults: engineDefaults,
            keychain: engineKeychain,
            keychainService: "MainWindowViewModelTests"
        )
        let completedAt = Date(timeIntervalSince1970: 1_775_000_000)
        appState.summarizerStatus = SummarizerRuntimeStatus(
            mode: "OpenAI API",
            isConfigured: true,
            lastCompletedAt: completedAt,
            lastError: "timed out"
        )

        appState.refreshServiceStatuses()

        XCTAssertEqual(appState.summarizerStatus.lastCompletedAt, completedAt)
        XCTAssertEqual(appState.summarizerStatus.lastError, "timed out")
    }

    func testRefreshEngineStatusesPreservesLastVerifiedStateForUnchangedEngine() {
        let executableURL = try! makeStubExecutable(named: "codex")
        var config = SummarizerConfig.default
        config.defaultEngine = .codexCLI
        config.codexCLIPath = executableURL.path

        let verifiedAt = Date(timeIntervalSince1970: 1_775_100_000)
        let appState = AppState(
            bootstrapServices: false,
            summarizerConfig: config,
            userDefaults: engineDefaults,
            keychain: engineKeychain,
            keychainService: "MainWindowViewModelTests"
        )
        appState.engineStatuses[.codexCLI] = EngineRuntimeStatus(
            state: .green,
            detail: "Smoke test succeeded.",
            lastVerifiedAt: verifiedAt
        )

        appState.refreshEngineStatuses()

        XCTAssertEqual(appState.engineStatuses[.codexCLI]?.state, .green)
        XCTAssertEqual(appState.engineStatuses[.codexCLI]?.detail, "Smoke test succeeded.")
        XCTAssertEqual(appState.engineStatuses[.codexCLI]?.lastVerifiedAt, verifiedAt)
    }

    func testAppStateExposesDefaultEngineAndStatusesForSelectorUI() {
        var config = SummarizerConfig.default
        config.defaultEngine = .codexCLI

        let appState = AppState(
            bootstrapServices: false,
            summarizerConfig: config,
            userDefaults: engineDefaults,
            keychain: engineKeychain,
            keychainService: "MainWindowViewModelTests"
        )
        appState.engineStatuses[.codexCLI] = EngineRuntimeStatus(
            state: .green,
            detail: "Smoke test succeeded.",
            lastVerifiedAt: Date(timeIntervalSince1970: 1_775_150_000),
            configurationSignature: "codex|/tmp/codex"
        )
        appState.engineStatuses[.openAI] = EngineRuntimeStatus(
            state: .yellow,
            detail: "API configuration changed. Retest required.",
            lastVerifiedAt: nil,
            configurationSignature: "https://api.openai.com/v1/responses|gpt-5|"
        )

        XCTAssertEqual(appState.defaultEngine.displayName, "Codex (CLI)")
        XCTAssertEqual(appState.engineStatuses[.codexCLI]?.state, .green)
        XCTAssertEqual(appState.engineStatuses[.openAI]?.state, .yellow)
    }

    func testApplyEngineConfigKeepsGreenDefaultActiveWhenNewEngineProbeFails() async throws {
        let executableURL = try makeStubExecutable(named: "codex")
        var initialConfig = SummarizerConfig.default
        initialConfig.defaultEngine = .codexCLI
        initialConfig.codexCLIPath = executableURL.path

        let environment = try makeEngineEnvironment()
        let appState = AppState(
            environment: environment,
            summarizerConfig: initialConfig,
            probeEngine: { engine, _, _ in
                EngineProbeResult(
                    engine: engine,
                    state: .yellow,
                    detail: "API request failed.",
                    verifiedAt: Date(timeIntervalSince1970: 1_775_200_000)
                )
            },
            userDefaults: engineDefaults,
            keychain: engineKeychain,
            keychainService: "MainWindowViewModelTests"
        )
        appState.engineStatuses[.codexCLI] = EngineRuntimeStatus(
            state: .green,
            detail: "Smoke test succeeded.",
            lastVerifiedAt: Date(timeIntervalSince1970: 1_775_190_000),
            configurationSignature: "codex|\(executableURL.path)"
        )
        appState.selectDefaultEngine(.codexCLI)

        var editedConfig = initialConfig
        editedConfig.defaultEngine = .openAI
        editedConfig.apiBaseURL = "https://example.com/v1/responses"
        editedConfig.apiModel = "gpt-5"
        editedConfig.apiToken = "token-test-123"

        appState.applyEngineConfig(editedConfig)
        await appState.retestEngine(.openAI)

        XCTAssertEqual(appState.defaultEngine, .codexCLI)
        XCTAssertEqual(appState.engineStatuses[.openAI]?.state, .yellow)

        let activeSummarizer = try XCTUnwrap(appState.environment?.summarizer as? CLISummarizer)
        XCTAssertEqual(activeSummarizer.tool, .codex)
        XCTAssertEqual(activeSummarizer.executablePath, executableURL.path)

        XCTAssertEqual(
            SummarizerConfig.load(
                from: engineDefaults,
                keychain: engineKeychain,
                keychainService: "MainWindowViewModelTests"
            ).defaultEngine,
            .codexCLI
        )
    }

    func testApplySummarizerConfigKeepsLegacyRequestedEnginePendingUntilVerified() throws {
        let executableURL = try makeStubExecutable(named: "codex")
        var config = SummarizerConfig.default
        config.defaultEngine = .codexCLI
        config.codexCLIPath = executableURL.path

        let environment = try makeEngineEnvironment()
        let appState = AppState(
            environment: environment,
            userDefaults: engineDefaults,
            keychain: engineKeychain,
            keychainService: "MainWindowViewModelTests"
        )

        appState.applySummarizerConfig(config)

        XCTAssertEqual(appState.defaultEngine, .none)
        XCTAssertEqual(appState.summarizerStatus.mode, DiaryEngine.none.displayName)
        XCTAssertNil(appState.environment?.summarizer)
        XCTAssertEqual(appState.engineStatuses[.codexCLI]?.state, .yellow)
        XCTAssertEqual(appState.engineStatuses[.codexCLI]?.detail, "Executable found. Retest required.")

        let persistedConfig = SummarizerConfig.load(
            from: engineDefaults,
            keychain: engineKeychain,
            keychainService: "MainWindowViewModelTests"
        )
        XCTAssertEqual(persistedConfig.defaultEngine, .none)
        XCTAssertEqual(persistedConfig.codexCLIPath, executableURL.path)
    }

    func testApplySummarizerConfigAllowsLegacyDisableException() throws {
        let executableURL = try makeStubExecutable(named: "codex")
        var activeConfig = SummarizerConfig.default
        activeConfig.defaultEngine = .codexCLI
        activeConfig.codexCLIPath = executableURL.path

        let environment = try makeEngineEnvironment()
        let appState = AppState(
            environment: environment,
            summarizerConfig: activeConfig,
            userDefaults: engineDefaults,
            keychain: engineKeychain,
            keychainService: "MainWindowViewModelTests"
        )
        appState.engineStatuses[.codexCLI] = EngineRuntimeStatus(
            state: .green,
            detail: "Smoke test succeeded.",
            lastVerifiedAt: Date(timeIntervalSince1970: 1_775_205_000),
            configurationSignature: "codex|\(executableURL.path)"
        )
        appState.selectDefaultEngine(.codexCLI)

        var disabledConfig = activeConfig
        disabledConfig.defaultEngine = .none
        appState.applySummarizerConfig(disabledConfig)

        XCTAssertEqual(appState.defaultEngine, .none)
        XCTAssertEqual(appState.summarizerStatus.mode, DiaryEngine.none.displayName)
        XCTAssertNil(appState.environment?.summarizer)

        XCTAssertEqual(
            SummarizerConfig.load(
                from: engineDefaults,
                keychain: engineKeychain,
                keychainService: "MainWindowViewModelTests"
            ).defaultEngine,
            .none
        )
    }

    func testOnlyGreenEngineCanBecomeDefault() {
        var config = SummarizerConfig.default
        config.defaultEngine = .openAI
        config.apiBaseURL = "https://example.com/v1/responses"
        config.apiModel = "gpt-5"
        config.apiToken = "token-test-123"

        let appState = AppState(
            bootstrapServices: false,
            summarizerConfig: config,
            userDefaults: engineDefaults,
            keychain: engineKeychain,
            keychainService: "MainWindowViewModelTests"
        )
        appState.applyEngineConfig(config)
        appState.engineStatuses[.codexCLI] = EngineRuntimeStatus(state: .yellow, detail: "Smoke test failed.", lastVerifiedAt: nil)
        appState.engineStatuses[.geminiCLI] = EngineRuntimeStatus(state: .green, detail: "Smoke test succeeded.", lastVerifiedAt: nil)

        appState.selectDefaultEngine(.codexCLI)
        XCTAssertEqual(appState.defaultEngine, .openAI)
        XCTAssertEqual(
            SummarizerConfig.load(
                from: engineDefaults,
                keychain: engineKeychain,
                keychainService: "MainWindowViewModelTests"
            ).defaultEngine,
            .openAI
        )

        appState.selectDefaultEngine(.geminiCLI)
        XCTAssertEqual(appState.defaultEngine, .geminiCLI)
        XCTAssertEqual(
            SummarizerConfig.load(
                from: engineDefaults,
                keychain: engineKeychain,
                keychainService: "MainWindowViewModelTests"
            ).defaultEngine,
            .geminiCLI
        )
    }

    func testSelectingNoneDisablesActiveSummarizerAndPersistsNoneAsDefault() throws {
        let executableURL = try makeStubExecutable(named: "codex")
        var config = SummarizerConfig.default
        config.defaultEngine = .codexCLI
        config.codexCLIPath = executableURL.path

        let environment = try makeEngineEnvironment()
        let appState = AppState(
            environment: environment,
            summarizerConfig: config,
            userDefaults: engineDefaults,
            keychain: engineKeychain,
            keychainService: "MainWindowViewModelTests"
        )
        appState.engineStatuses[.codexCLI] = EngineRuntimeStatus(
            state: .green,
            detail: "Smoke test succeeded.",
            lastVerifiedAt: Date(timeIntervalSince1970: 1_775_400_000),
            configurationSignature: "codex|\(executableURL.path)"
        )
        appState.selectDefaultEngine(.codexCLI)

        XCTAssertNotNil(appState.environment?.summarizer)

        appState.selectDefaultEngine(.none)

        XCTAssertEqual(appState.defaultEngine, .none)
        XCTAssertNil(appState.environment?.summarizer)
        XCTAssertEqual(
            SummarizerConfig.load(
                from: engineDefaults,
                keychain: engineKeychain,
                keychainService: "MainWindowViewModelTests"
            ).defaultEngine,
            .none
        )
    }

    func testEditingAPIConfigReturnsAPIRowToYellowUntilRetested() async throws {
        let executableURL = try makeStubExecutable(named: "codex")
        var config = SummarizerConfig.default
        config.defaultEngine = .openAI
        config.apiBaseURL = "https://example.com/v1/responses"
        config.apiModel = "gpt-5"
        config.apiToken = "token-test-123"
        config.codexCLIPath = executableURL.path

        let verifiedAt = Date(timeIntervalSince1970: 1_775_300_000)
        let environment = try makeEngineEnvironment()
        let appState = AppState(
            environment: environment,
            summarizerConfig: config,
            userDefaults: engineDefaults,
            keychain: engineKeychain,
            keychainService: "MainWindowViewModelTests"
        )
        appState.engineStatuses[.openAI] = EngineRuntimeStatus(
            state: .green,
            detail: "API returned an expected acknowledgement.",
            lastVerifiedAt: verifiedAt,
            configurationSignature: "https://example.com/v1/responses|gpt-5|token-test-123"
        )
        appState.engineStatuses[.codexCLI] = EngineRuntimeStatus(
            state: .green,
            detail: "Smoke test succeeded.",
            lastVerifiedAt: verifiedAt,
            configurationSignature: "codex|\(executableURL.path)"
        )

        config.apiModel = "gpt-5-mini"
        appState.applyEngineConfig(config)

        XCTAssertEqual(appState.engineStatuses[.openAI]?.state, .yellow)
        XCTAssertEqual(appState.engineStatuses[.openAI]?.lastVerifiedAt, verifiedAt)
        XCTAssertEqual(appState.engineStatuses[.codexCLI]?.state, .green)
        XCTAssertEqual(appState.engineStatuses[.codexCLI]?.lastVerifiedAt, verifiedAt)

        let summarizer = try XCTUnwrap(appState.environment?.summarizer as? CloudSummarizer)
        XCTAssertEqual(summarizer.model, "gpt-5-mini")
    }

    func testRetestEngineDiscardsStaleProbeResultWhenConfigChangesMidFlight() async throws {
        let originalExecutableURL = try makeStubExecutable(named: "codex")
        let updatedExecutableURL = try makeStubExecutable(named: "codex")
        let verifiedAt = Date(timeIntervalSince1970: 1_775_310_000)
        let probeGate = ProbeGate()

        var config = SummarizerConfig.default
        config.defaultEngine = .codexCLI
        config.codexCLIPath = originalExecutableURL.path

        let appState = AppState(
            bootstrapServices: false,
            summarizerConfig: config,
            probeEngine: { engine, _, _ in
                await probeGate.markStarted()
                await probeGate.waitForRelease()
                return EngineProbeResult(
                    engine: engine,
                    state: .green,
                    detail: "Smoke test succeeded.",
                    verifiedAt: verifiedAt
                )
            },
            userDefaults: engineDefaults,
            keychain: engineKeychain,
            keychainService: "MainWindowViewModelTests"
        )

        let retestTask = Task {
            await appState.retestEngine(.codexCLI)
        }

        await probeGate.waitUntilStarted()

        config.codexCLIPath = updatedExecutableURL.path
        appState.applyEngineConfig(config)

        XCTAssertEqual(appState.engineStatuses[.codexCLI]?.state, .yellow)
        XCTAssertEqual(appState.engineStatuses[.codexCLI]?.detail, "Executable found. Retest required.")

        await probeGate.release()
        await retestTask.value

        XCTAssertEqual(appState.engineStatuses[.codexCLI]?.state, .yellow)
        XCTAssertEqual(appState.engineStatuses[.codexCLI]?.detail, "Executable found. Retest required.")
        XCTAssertEqual(appState.engineStatuses[.codexCLI]?.lastVerifiedAt, nil)
        XCTAssertEqual(appState.engineStatuses[.codexCLI]?.configurationSignature, "codex|\(updatedExecutableURL.path)")
    }

    func testRetestAllEnginesStartsProbesInParallel() async {
        let codexGate = ProbeGate()
        let tracker = ProbeStartTracker()

        let appState = AppState(
            bootstrapServices: false,
            probeEngine: { engine, _, _ in
                await tracker.markStarted(engine)
                if engine == .codexCLI {
                    await codexGate.markStarted()
                    await codexGate.waitForRelease()
                }
                return EngineProbeResult(
                    engine: engine,
                    state: .green,
                    detail: "Smoke test succeeded.",
                    verifiedAt: Date(timeIntervalSince1970: 1_775_310_000)
                )
            },
            userDefaults: engineDefaults,
            keychain: engineKeychain,
            keychainService: "MainWindowViewModelTests"
        )

        let retestTask = Task {
            await appState.retestAllEngines()
        }

        await codexGate.waitUntilStarted()
        await tracker.waitUntilStarted([.codexCLI, .geminiCLI])

        XCTAssertTrue(appState.isRetestingEngines)
        XCTAssertTrue(appState.retestingEngines.contains(.codexCLI))

        await codexGate.release()
        await retestTask.value

        XCTAssertFalse(appState.isRetestingEngines)
        XCTAssertTrue(appState.retestingEngines.isEmpty)
        XCTAssertEqual(appState.engineStatuses[.codexCLI]?.state, .green)
        XCTAssertEqual(appState.engineStatuses[.geminiCLI]?.state, .green)
    }

    func testGenerateStoryFallsBackWithoutEngineAndAnnotatesFallbackProvenance() async throws {
        let writer = try DatabaseWriter.inMemory()
        let dayKey = "2026-04-11"
        let eventID = UUID()
        let capturedAt = Date(timeIntervalSince1970: 1_775_600_000)
        try writer.insert(
            EventRecord(
                id: eventID,
                sourceType: .clipboard,
                sourceApp: "Notes",
                capturedAt: capturedAt,
                dayKey: dayKey,
                text: "Closed the loop on the shipping checklist",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "fallback-provenance"
            )
        )

        let environment = AppEnvironment(
            databaseURL: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).sqlite"),
            vaultURL: URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory),
            databaseWriter: writer,
            summarizer: nil,
            notificationReader: RecordingNotificationReader(),
            dailyAutomationPlanner: DailyAutomationPlanner(
                backfillPlanner: BackfillPlanner(calendar: Calendar(identifier: .gregorian))
            )
        )
        let appState = AppState(
            environment: environment,
            userDefaults: engineDefaults,
            keychain: engineKeychain,
            keychainService: "MainWindowViewModelTests"
        )
        let events = try writer.fetchEvents(dayKey: dayKey)

        let story = await appState.generateStory(dayKey: dayKey, events: events, environment: environment)

        XCTAssertFalse(story.sections.flatMap(\.paragraphs).isEmpty)
        XCTAssertEqual(story.provenance?.generationMode, .fallback)
        XCTAssertEqual(story.provenance?.engineKind, DiaryEngine.none.rawValue)
        XCTAssertEqual(story.provenance?.engineLabel, DiaryEngine.none.displayName)
        XCTAssertEqual(story.provenance?.curatedEventCount, 1)
    }

    func testGenerateStoryAnnotatesModelProvenanceWhenSummarizerSucceeds() async throws {
        let writer = try DatabaseWriter.inMemory()
        let dayKey = "2026-04-11"
        let eventID = UUID()
        try writer.insert(
            EventRecord(
                id: eventID,
                sourceType: .clipboard,
                sourceApp: "Notes",
                capturedAt: Date(timeIntervalSince1970: 1_775_600_500),
                dayKey: dayKey,
                text: "Summarized a clean planning thread",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "model-provenance"
            )
        )

        let response = """
        {"sections":[{"id":"daily-journal","paragraphs":[{"text":"# Summary\\n- Summarized a clean planning thread","sourceEventIDs":["\(eventID.uuidString)"]}]}]}
        """
        let executableURL = try makeStubExecutable(named: "codex")
        let environment = AppEnvironment(
            databaseURL: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).sqlite"),
            vaultURL: URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory),
            databaseWriter: writer,
            summarizer: nil,
            notificationReader: RecordingNotificationReader(),
            dailyAutomationPlanner: DailyAutomationPlanner(
                backfillPlanner: BackfillPlanner(calendar: Calendar(identifier: .gregorian))
            )
        )
        var config = SummarizerConfig.default
        config.defaultEngine = .codexCLI
        config.codexCLIPath = executableURL.path
        let appState = AppState(
            environment: environment,
            summarizerConfig: config,
            userDefaults: engineDefaults,
            keychain: engineKeychain,
            keychainService: "MainWindowViewModelTests"
        )
        environment.summarizer = StaticSummarizer(response: response)
        let events = try writer.fetchEvents(dayKey: dayKey)

        let story = await appState.generateStory(dayKey: dayKey, events: events, environment: environment)

        XCTAssertEqual(story.provenance?.generationMode, .model)
        XCTAssertEqual(story.provenance?.engineKind, DiaryEngine.codexCLI.rawValue)
        XCTAssertEqual(story.provenance?.engineLabel, DiaryEngine.codexCLI.displayName)
        XCTAssertEqual(story.provenance?.curatedEventCount, 1)
    }

    func testCompleteOnboardingPersistsVaultAndSelectedVerifiedEngine() throws {
        let executableURL = try makeStubExecutable(named: "gemini")
        var config = SummarizerConfig.default
        config.geminiCLIPath = executableURL.path

        let environment = try makeEngineEnvironment()
        let appState = AppState(
            environment: environment,
            summarizerConfig: config,
            userDefaults: engineDefaults,
            keychain: engineKeychain,
            keychainService: "MainWindowViewModelTests"
        )
        appState.engineStatuses[.geminiCLI] = EngineRuntimeStatus(
            state: .green,
            detail: "Smoke test succeeded.",
            lastVerifiedAt: Date(timeIntervalSince1970: 1_775_610_000),
            configurationSignature: "gemini|\(executableURL.path)"
        )
        let vaultURL = URL(fileURLWithPath: "/tmp/\(UUID().uuidString)", isDirectory: true)

        appState.completeOnboarding(vaultURL: vaultURL, preferredEngine: .geminiCLI)

        XCTAssertEqual(appState.defaultEngine, .geminiCLI)
        XCTAssertEqual(environment.vaultURL, vaultURL)
        XCTAssertEqual(engineDefaults.string(forKey: AppState.UserDefaultsKeys.vaultPath), vaultURL.path)
        XCTAssertEqual(
            SummarizerConfig.load(
                from: engineDefaults,
                keychain: engineKeychain,
                keychainService: "MainWindowViewModelTests"
            ).defaultEngine,
            .geminiCLI
        )
        XCTAssertEqual(
            engineDefaults.bool(forKey: AppState.UserDefaultsKeys.hasCompletedOnboarding),
            true
        )
    }

    func testDailyStoryDecodingBackfillsLegacyProvenanceWhenMissingFromPayload() throws {
        let json = """
        {
          "dayKey": "2026-04-11",
          "generatedAt": 1775600000,
          "sections": [
            {
              "id": "daily-journal",
              "title": "",
              "paragraphs": [
                {
                  "id": "daily-journal-0",
                  "text": "Legacy paragraph",
                  "sourceEventIDs": ["\(UUID().uuidString)"]
                }
              ]
            }
          ]
        }
        """

        let story = try JSONDecoder().decode(DailyStory.self, from: Data(json.utf8))

        XCTAssertEqual(story.provenance?.generationMode, .legacy)
        XCTAssertEqual(story.provenance?.engineKind, "legacy")
        XCTAssertEqual(story.provenance?.engineLabel, "Legacy Story")
        XCTAssertEqual(story.provenance?.pipelineVersion, "legacy")
    }

    func testSummarizerStatusReflectsDegradedActiveEngineAfterConfigInvalidation() throws {
        let originalExecutableURL = try makeStubExecutable(named: "codex")
        let updatedExecutableURL = try makeStubExecutable(named: "codex")
        let verifiedAt = Date(timeIntervalSince1970: 1_775_320_000)

        var config = SummarizerConfig.default
        config.defaultEngine = .codexCLI
        config.codexCLIPath = originalExecutableURL.path

        let appState = AppState(
            bootstrapServices: false,
            summarizerConfig: config,
            userDefaults: engineDefaults,
            keychain: engineKeychain,
            keychainService: "MainWindowViewModelTests"
        )
        appState.engineStatuses[.codexCLI] = EngineRuntimeStatus(
            state: .green,
            detail: "Smoke test succeeded.",
            lastVerifiedAt: verifiedAt,
            configurationSignature: "codex|\(originalExecutableURL.path)"
        )

        config.codexCLIPath = updatedExecutableURL.path
        appState.applyEngineConfig(config)

        XCTAssertEqual(appState.summarizerStatus.mode, DiaryEngine.codexCLI.displayName)
        XCTAssertTrue(appState.summarizerStatus.isConfigured)
        XCTAssertEqual(appState.summarizerStatus.lastCompletedAt, verifiedAt)
        XCTAssertEqual(appState.summarizerStatus.lastError, "Executable found. Retest required.")
    }

    func testEnvironmentInitInfersRuntimeEngineFromInjectedSummarizerForStatusBookkeeping() async throws {
        var persistedConfig = SummarizerConfig.default
        persistedConfig.defaultEngine = .openAI
        persistedConfig.apiBaseURL = "https://example.com/v1/responses"
        persistedConfig.apiModel = "gpt-5"
        persistedConfig.apiToken = "token-test-123"
        persistedConfig.save(
            to: engineDefaults,
            keychain: engineKeychain,
            keychainService: "MainWindowViewModelTests"
        )

        let executableURL = try makeStubExecutable(named: "codex")
        let environment = try makeEngineEnvironment()
        environment.summarizer = CLISummarizer(tool: .codex, executablePath: executableURL.path)

        let appState = AppState(
            environment: environment,
            userDefaults: engineDefaults,
            keychain: engineKeychain,
            keychainService: "MainWindowViewModelTests"
        )

        XCTAssertEqual(appState.defaultEngine, .codexCLI)
        XCTAssertEqual(appState.summarizerStatus.mode, DiaryEngine.codexCLI.displayName)
        XCTAssertEqual(appState.engineStatuses[.codexCLI]?.state, .yellow)
        XCTAssertEqual(appState.engineStatuses[.codexCLI]?.detail, "Executable found. Retest required.")
        XCTAssertEqual(appState.engineStatuses[.codexCLI]?.configurationSignature, "codex|\(executableURL.path)")

        let verifiedAt = Date(timeIntervalSince1970: 1_775_330_000)
        appState.summarizerStatus = SummarizerRuntimeStatus(
            mode: DiaryEngine.codexCLI.displayName,
            isConfigured: true,
            lastCompletedAt: verifiedAt,
            lastError: nil
        )

        XCTAssertEqual(appState.engineStatuses[.codexCLI]?.state, .green)
        XCTAssertEqual(appState.engineStatuses[.codexCLI]?.lastVerifiedAt, verifiedAt)
        XCTAssertEqual(appState.engineStatuses[.codexCLI]?.configurationSignature, "codex|\(executableURL.path)")
        XCTAssertEqual(appState.engineStatuses[.openAI]?.lastVerifiedAt, nil)
    }

    func testInitDoesNotReactivatePersistedUnverifiedDefaultEngine() throws {
        let executableURL = try makeStubExecutable(named: "codex")
        var persistedConfig = SummarizerConfig.default
        persistedConfig.defaultEngine = .codexCLI
        persistedConfig.codexCLIPath = executableURL.path
        persistedConfig.save(
            to: engineDefaults,
            keychain: engineKeychain,
            keychainService: "MainWindowViewModelTests"
        )

        let appState = AppState(
            bootstrapServices: false,
            userDefaults: engineDefaults,
            keychain: engineKeychain,
            keychainService: "MainWindowViewModelTests"
        )

        XCTAssertEqual(appState.defaultEngine, .none)
        XCTAssertEqual(appState.summarizerStatus.mode, DiaryEngine.none.displayName)
        XCTAssertFalse(appState.summarizerStatus.isConfigured)
        XCTAssertEqual(appState.engineStatuses[.codexCLI]?.state, .yellow)
        XCTAssertEqual(appState.engineStatuses[.codexCLI]?.detail, "Executable found. Retest required.")
        XCTAssertEqual(
            SummarizerConfig.load(
                from: engineDefaults,
                keychain: engineKeychain,
                keychainService: "MainWindowViewModelTests"
            ).defaultEngine,
            .none
        )
    }

    func testRestartAfterActiveEngineDegradesDoesNotReactivatePersistedYellowEngine() throws {
        let originalExecutableURL = try makeStubExecutable(named: "codex")
        let updatedExecutableURL = try makeStubExecutable(named: "codex")

        var config = SummarizerConfig.default
        config.defaultEngine = .codexCLI
        config.codexCLIPath = originalExecutableURL.path

        let environment = try makeEngineEnvironment()
        let appState = AppState(
            environment: environment,
            summarizerConfig: config,
            userDefaults: engineDefaults,
            keychain: engineKeychain,
            keychainService: "MainWindowViewModelTests"
        )
        appState.engineStatuses[.codexCLI] = EngineRuntimeStatus(
            state: .green,
            detail: "Smoke test succeeded.",
            lastVerifiedAt: Date(timeIntervalSince1970: 1_775_340_000),
            configurationSignature: "codex|\(originalExecutableURL.path)"
        )
        appState.selectDefaultEngine(.codexCLI)

        config.codexCLIPath = updatedExecutableURL.path
        appState.applyEngineConfig(config)

        let relaunched = AppState(
            bootstrapServices: false,
            userDefaults: engineDefaults,
            keychain: engineKeychain,
            keychainService: "MainWindowViewModelTests"
        )

        XCTAssertEqual(relaunched.defaultEngine, .none)
        XCTAssertNil(relaunched.environment?.summarizer)
        XCTAssertEqual(relaunched.engineStatuses[.codexCLI]?.state, .yellow)
        XCTAssertEqual(relaunched.engineStatuses[.codexCLI]?.detail, "Executable found. Retest required.")
    }

    func testSelectStoryParagraphUpdatesVisibleSourceEvents() async throws {
        let writer = try DatabaseWriter.inMemory()
        let dayKey = "2026-04-07"
        let baseDate = DateComponents(calendar: Calendar(identifier: .gregorian), year: 2026, month: 4, day: 7, hour: 9).date!
        try writer.insert(
            EventRecord(
                id: UUID(),
                sourceType: .clipboard,
                sourceApp: "Drafts",
                capturedAt: baseDate,
                dayKey: dayKey,
                text: "Outlined launch story",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "story-a"
            )
        )
        try writer.insert(
            EventRecord(
                id: UUID(),
                sourceType: .notification,
                sourceApp: "Calendar",
                capturedAt: baseDate.addingTimeInterval(300),
                dayKey: dayKey,
                text: "Design review in 10 minutes",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "story-b"
            )
        )

        let vaultURL = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let environment = AppEnvironment(
            databaseURL: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).sqlite"),
            vaultURL: vaultURL,
            databaseWriter: writer,
            summarizer: nil,
            notificationReader: RecordingNotificationReader(),
            dailyAutomationPlanner: DailyAutomationPlanner(
                backfillPlanner: BackfillPlanner(calendar: Calendar(identifier: .gregorian))
            )
        )
        let appState = AppState(environment: environment)

        await appState.generateDailyNote(for: dayKey)

        let paragraphIDs = appState.selectedStory?.sections.flatMap(\.paragraphs).map(\.id) ?? []
        XCTAssertGreaterThanOrEqual(paragraphIDs.count, 2)

        appState.selectStoryParagraph(paragraphIDs[1])

        XCTAssertEqual(appState.selectedStoryParagraphID, paragraphIDs[1])
        XCTAssertEqual(appState.selectedStorySourceEvents.count, 1)
        XCTAssertEqual(appState.selectedStorySourceEvents.first?.sourceType, .notification)
    }

    private func makeEngineEnvironment() throws -> AppEnvironment {
        let writer = try DatabaseWriter.inMemory()
        let vaultURL = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        return AppEnvironment(
            databaseURL: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).sqlite"),
            vaultURL: vaultURL,
            databaseWriter: writer,
            summarizer: nil,
            notificationReader: RecordingNotificationReader(),
            dailyAutomationPlanner: DailyAutomationPlanner(
                backfillPlanner: BackfillPlanner(calendar: Calendar(identifier: .gregorian))
            )
        )
    }

    private func makeStubExecutable(named name: String) throws -> URL {
        let directoryURL = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let executableURL = directoryURL.appending(path: name)
        try "#!/bin/sh\nexit 0\n".write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)
        return executableURL
    }
}
