import XCTest
@testable import KnowYou

private struct ThrowingSummarizer: SummaryGenerating {
    func summarize(dayKey: String, markdown: String) async throws -> String {
        throw URLError(.cannotConnectToHost)
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

@MainActor
final class MainWindowViewModelTests: XCTestCase {
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
        let appState = AppState(bootstrapServices: false)
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
}
