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

private final class RecordingPromptSummarizer: SummaryGenerating, @unchecked Sendable {
    let response: String
    private(set) var capturedDayKey: String?
    private(set) var capturedMarkdown: String?

    init(response: String) {
        self.response = response
    }

    func summarize(dayKey: String, markdown: String) async throws -> String {
        capturedDayKey = dayKey
        capturedMarkdown = markdown
        return response
    }
}

private final class RecordingNotificationReader: NotificationDatabaseReading, @unchecked Sendable {
    private(set) var requestedSince: Date?
    private(set) var requestedUpperBound: NotificationFetchUpperBound?
    var snapshots: [NotificationSnapshot] = []
    var fetchError: Error?
    var fetchHandler: ((Date, NotificationFetchUpperBound?) throws -> [NotificationSnapshot])?
    var accessStatusValue = NotificationDatabaseAccessStatus(
        state: .available,
        databaseURL: URL(fileURLWithPath: "/tmp/notification-center.sqlite")
    )

    func accessStatus() -> NotificationDatabaseAccessStatus {
        accessStatusValue
    }

    func fetchDeliveredNotifications(from startDate: Date, upperBound: NotificationFetchUpperBound?) throws -> [NotificationSnapshot] {
        requestedSince = startDate
        requestedUpperBound = upperBound
        if let fetchError {
            throw fetchError
        }
        let snapshots: [NotificationSnapshot]
        if let fetchHandler {
            snapshots = try fetchHandler(startDate, upperBound)
        } else {
            snapshots = self.snapshots
        }

        return snapshots.filter { snapshot in
            guard snapshot.deliveredAt >= startDate else {
                return false
            }

            switch upperBound {
            case .exclusive(let endDate):
                return snapshot.deliveredAt < endDate
            case .inclusive(let endDate):
                return snapshot.deliveredAt <= endDate
            case nil:
                return true
            }
        }
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

private actor RefreshBlockGate {
    private var startedCounts: [String: Int] = [:]
    private var startedWaiters: [String: CheckedContinuation<Void, Never>] = [:]
    private var releaseWaiters: [String: CheckedContinuation<Void, Never>] = [:]

    func markStarted(dayKey: String) {
        startedCounts[dayKey, default: 0] += 1
        startedWaiters[dayKey]?.resume()
        startedWaiters[dayKey] = nil
    }

    func waitUntilStarted(dayKey: String) async {
        guard startedCounts[dayKey] == nil else { return }
        await withCheckedContinuation { continuation in
            startedWaiters[dayKey] = continuation
        }
    }

    func waitForRelease(dayKey: String) async {
        await withCheckedContinuation { continuation in
            releaseWaiters[dayKey] = continuation
        }
    }

    func release(dayKey: String) {
        releaseWaiters[dayKey]?.resume()
        releaseWaiters[dayKey] = nil
    }

    func startCount(for dayKey: String) -> Int {
        startedCounts[dayKey] ?? 0
    }
}

private struct BlockingSummarizer: SummaryGenerating {
    let gate: RefreshBlockGate

    func summarize(dayKey: String, markdown: String) async throws -> String {
        await gate.markStarted(dayKey: dayKey)
        await gate.waitForRelease(dayKey: dayKey)
        return """
        {"sections":[{"id":"daily-journal","paragraphs":[{"text":"# Summary\\n- \(dayKey)","sourceEventIDs":[]}]}]}
        """
    }
}

@MainActor
private func makeBlockingRefreshEnvironment() throws -> (AppEnvironment, RefreshBlockGate) {
    let gate = RefreshBlockGate()
    let writer = try DatabaseWriter.inMemory()
    let environment = AppEnvironment(
        databaseURL: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).sqlite"),
        vaultURL: URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory),
        databaseWriter: writer,
        summarizer: BlockingSummarizer(gate: gate),
        notificationReader: RecordingNotificationReader(),
        dailyAutomationPlanner: DailyAutomationPlanner(
            backfillPlanner: BackfillPlanner(calendar: Calendar(identifier: .gregorian))
        )
    )
    return (environment, gate)
}

@MainActor
private final class RefreshStageRecorder {
    private(set) var stages: [DayRefreshStage] = []

    func record(_ job: DayRefreshJob) {
        stages.append(job.stage)
    }
}

private func waitUntil(
    timeoutNanoseconds: UInt64 = 1_000_000_000,
    pollNanoseconds: UInt64 = 10_000_000,
    condition: @escaping @MainActor () -> Bool
) async -> Bool {
    let start = DispatchTime.now().uptimeNanoseconds
    while DispatchTime.now().uptimeNanoseconds - start < timeoutNanoseconds {
        if await condition() {
            return true
        }
        try? await Task.sleep(nanoseconds: pollNanoseconds)
    }
    return await condition()
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

    func testRunNotificationCatchUpRecoversTodayNotificationsFromStartOfDay() async throws {
        let writer = try DatabaseWriter.inMemory()
        let reader = RecordingNotificationReader()
        let calendar = Calendar(identifier: .gregorian)
        let now = DateComponents(calendar: calendar, year: 2026, month: 4, day: 11, hour: 13).date!
        let dayKey = ISO8601DayKey.format(now)
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
                backfillPlanner: BackfillPlanner(calendar: calendar)
            )
        )
        let appState = AppState(
            environment: environment,
            userDefaults: engineDefaults,
            keychain: engineKeychain,
            keychainService: "MainWindowViewModelTests"
        )

        await appState.runNotificationCatchUp(now: now)

        XCTAssertEqual(reader.requestedSince, calendar.startOfDay(for: now))
        XCTAssertEqual(reader.requestedUpperBound, .inclusive(now))
        XCTAssertEqual(try writer.fetchEvents(dayKey: dayKey).count, 1)
        XCTAssertEqual(appState.lastNotificationImportAt, now)
        XCTAssertEqual(appState.notificationStatus.lastImportedCount, 1)
    }

    func testRunNotificationCatchUpUsesOverlapBufferWithoutDuplicatingNotifications() async throws {
        let writer = try DatabaseWriter.inMemory()
        let reader = RecordingNotificationReader()
        let calendar = Calendar(identifier: .gregorian)
        let firstNow = DateComponents(calendar: calendar, year: 2026, month: 4, day: 11, hour: 13, minute: 0, second: 0).date!
        let secondNow = firstNow.addingTimeInterval(120)
        let repeatedNotification = NotificationSnapshot(
            appName: "Mail",
            deliveredAt: firstNow.addingTimeInterval(-15),
            body: "Same delivered notification"
        )
        reader.fetchHandler = { startDate, upperBound in
            switch upperBound {
            case .inclusive(let endDate):
                if endDate == firstNow {
                    return [repeatedNotification]
                }
                if endDate == secondNow {
                    XCTAssertEqual(startDate, firstNow.addingTimeInterval(-30))
                    return [repeatedNotification]
                }
                return []
            case .exclusive, nil:
                return []
            }
        }

        let environment = AppEnvironment(
            databaseURL: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).sqlite"),
            vaultURL: URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory),
            databaseWriter: writer,
            summarizer: nil,
            notificationReader: reader,
            dailyAutomationPlanner: DailyAutomationPlanner(
                backfillPlanner: BackfillPlanner(calendar: calendar)
            )
        )
        let appState = AppState(
            environment: environment,
            userDefaults: engineDefaults,
            keychain: engineKeychain,
            keychainService: "MainWindowViewModelTests"
        )

        await appState.runNotificationCatchUp(now: firstNow)
        await appState.runNotificationCatchUp(now: secondNow)

        let events = try writer.fetchEvents(dayKey: ISO8601DayKey.format(firstNow))
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(reader.requestedUpperBound, .inclusive(secondNow))
        XCTAssertEqual(appState.lastNotificationImportAt, secondNow)
        XCTAssertEqual(appState.notificationStatus.lastImportedCount, 1)
    }

    func testRunNotificationCatchUpDoesNotPersistWatermarkWhenNotificationDatabaseUnavailable() async throws {
        let writer = try DatabaseWriter.inMemory()
        let reader = RecordingNotificationReader()
        reader.accessStatusValue = NotificationDatabaseAccessStatus(state: .missing, databaseURL: nil)
        let calendar = Calendar(identifier: .gregorian)
        let now = DateComponents(calendar: calendar, year: 2026, month: 4, day: 11, hour: 13).date!
        let environment = AppEnvironment(
            databaseURL: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).sqlite"),
            vaultURL: URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory),
            databaseWriter: writer,
            summarizer: nil,
            notificationReader: reader,
            dailyAutomationPlanner: DailyAutomationPlanner(
                backfillPlanner: BackfillPlanner(calendar: calendar)
            )
        )
        let appState = AppState(
            environment: environment,
            userDefaults: engineDefaults,
            keychain: engineKeychain,
            keychainService: "MainWindowViewModelTests"
        )

        await appState.runNotificationCatchUp(now: now)

        XCTAssertNil(appState.lastNotificationImportAt)
        XCTAssertNil(engineDefaults.object(forKey: AppState.UserDefaultsKeys.lastNotificationImportAt))
        XCTAssertEqual(appState.notificationStatus.lastImportedCount, 0)
    }

    func testStartAutomationStillRunsAutomationWhileSchedulingCatchUp() async throws {
        let writer = try DatabaseWriter.inMemory()
        let calendar = Calendar(identifier: .gregorian)
        let now = DateComponents(calendar: calendar, year: 2026, month: 4, day: 11, hour: 13).date!
        let dayKey = ISO8601DayKey.format(now)
        let reader = RecordingNotificationReader()
        reader.snapshots = [
            NotificationSnapshot(appName: "Calendar", deliveredAt: now, body: "Standup in 5")
        ]
        try writer.insert(
            EventRecord(
                id: UUID(),
                sourceType: .clipboard,
                sourceApp: "Notes",
                capturedAt: now,
                dayKey: dayKey,
                text: "Clipboard event for automation",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "automation-startup-event"
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
                backfillPlanner: BackfillPlanner(calendar: calendar)
            )
        )
        let appState = AppState(
            environment: environment,
            currentDate: { now },
            userDefaults: engineDefaults,
            keychain: engineKeychain,
            keychainService: "MainWindowViewModelTests"
        )

        appState.startAutomation()

        let automationStarted = await waitUntil {
            appState.lastAutomationRunAt == now
        }
        XCTAssertTrue(automationStarted)
        let noteWritten = await waitUntil {
            FileManager.default.fileExists(atPath: vaultURL.appending(path: "\(dayKey).md").path)
        }
        XCTAssertTrue(noteWritten)
        XCTAssertEqual(appState.lastAutomationRunAt, now)
        XCTAssertEqual(appState.notificationStatus.lastImportedCount, 1)
        XCTAssertEqual(try writer.fetchRuns(runType: "daily-note").last?.dayKey, dayKey)
    }

    func testRelaunchRestoresPersistedLastNotificationImportAtForCatchUpWindow() async throws {
        let writer = try DatabaseWriter.inMemory()
        let calendar = Calendar(identifier: .gregorian)
        let firstReader = RecordingNotificationReader()
        let initialNow = DateComponents(calendar: calendar, year: 2026, month: 4, day: 11, hour: 13, minute: 0, second: 0).date!
        let resumedNow = initialNow.addingTimeInterval(120)
        let overlapStart = initialNow.addingTimeInterval(-30)
        let sharedDatabaseURL = URL(fileURLWithPath: "/tmp/\(UUID().uuidString).sqlite")
        let repeatedNotification = NotificationSnapshot(
            appName: "Mail",
            deliveredAt: initialNow.addingTimeInterval(-10),
            body: "Persist across relaunch"
        )
        firstReader.snapshots = [repeatedNotification]

        let environment = AppEnvironment(
            databaseURL: sharedDatabaseURL,
            vaultURL: URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory),
            databaseWriter: writer,
            summarizer: nil,
            notificationReader: firstReader,
            dailyAutomationPlanner: DailyAutomationPlanner(
                backfillPlanner: BackfillPlanner(calendar: calendar)
            )
        )
        let original = AppState(
            environment: environment,
            currentDate: { initialNow },
            userDefaults: engineDefaults,
            keychain: engineKeychain,
            keychainService: "MainWindowViewModelTests"
        )

        await original.runNotificationCatchUp(now: initialNow)

        let secondReader = RecordingNotificationReader()
        secondReader.fetchHandler = { startDate, upperBound in
            XCTAssertEqual(startDate, overlapStart)
            XCTAssertEqual(upperBound, .inclusive(resumedNow))
            return [repeatedNotification]
        }
        let relaunchedEnvironment = AppEnvironment(
            databaseURL: sharedDatabaseURL,
            vaultURL: URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory),
            databaseWriter: writer,
            summarizer: nil,
            notificationReader: secondReader,
            dailyAutomationPlanner: DailyAutomationPlanner(
                backfillPlanner: BackfillPlanner(calendar: calendar)
            )
        )
        let relaunched = AppState(
            environment: relaunchedEnvironment,
            currentDate: { resumedNow },
            userDefaults: engineDefaults,
            keychain: engineKeychain,
            keychainService: "MainWindowViewModelTests"
        )

        XCTAssertEqual(relaunched.lastNotificationImportAt, initialNow)

        await relaunched.runNotificationCatchUp(now: resumedNow)

        let events = try writer.fetchEvents(dayKey: ISO8601DayKey.format(initialNow))
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(relaunched.lastNotificationImportAt, resumedNow)
    }

    func testRelaunchWithFreshStoreIgnoresPersistedNotificationWatermark() async throws {
        let calendar = Calendar(identifier: .gregorian)
        let initialNow = DateComponents(calendar: calendar, year: 2026, month: 4, day: 11, hour: 13, minute: 0, second: 0).date!
        let resumedNow = initialNow.addingTimeInterval(120)
        let sharedDatabaseURL = URL(fileURLWithPath: "/tmp/\(UUID().uuidString).sqlite")
        let originalWriter = try DatabaseWriter.inMemory()
        let originalReader = RecordingNotificationReader()
        let originalNotification = NotificationSnapshot(
            appName: "Mail",
            deliveredAt: initialNow.addingTimeInterval(-10),
            body: "Persist across relaunch"
        )
        originalReader.snapshots = [originalNotification]
        let originalEnvironment = AppEnvironment(
            databaseURL: sharedDatabaseURL,
            vaultURL: URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory),
            databaseWriter: originalWriter,
            summarizer: nil,
            notificationReader: originalReader,
            dailyAutomationPlanner: DailyAutomationPlanner(
                backfillPlanner: BackfillPlanner(calendar: calendar)
            )
        )
        let original = AppState(
            environment: originalEnvironment,
            currentDate: { initialNow },
            userDefaults: engineDefaults,
            keychain: engineKeychain,
            keychainService: "MainWindowViewModelTests"
        )

        await original.runNotificationCatchUp(now: initialNow)

        let freshWriter = try DatabaseWriter.inMemory()
        let freshReader = RecordingNotificationReader()
        let freshNotification = NotificationSnapshot(
            appName: "Calendar",
            deliveredAt: DateComponents(calendar: calendar, year: 2026, month: 4, day: 11, hour: 9, minute: 0).date!,
            body: "Earlier same-day notification in fresh store"
        )
        freshReader.fetchHandler = { startDate, upperBound in
            XCTAssertEqual(startDate, calendar.startOfDay(for: resumedNow))
            XCTAssertEqual(upperBound, .inclusive(resumedNow))
            return [freshNotification]
        }
        let freshEnvironment = AppEnvironment(
            databaseURL: sharedDatabaseURL,
            vaultURL: URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory),
            databaseWriter: freshWriter,
            summarizer: nil,
            notificationReader: freshReader,
            dailyAutomationPlanner: DailyAutomationPlanner(
                backfillPlanner: BackfillPlanner(calendar: calendar)
            )
        )
        let relaunched = AppState(
            environment: freshEnvironment,
            currentDate: { resumedNow },
            userDefaults: engineDefaults,
            keychain: engineKeychain,
            keychainService: "MainWindowViewModelTests"
        )

        XCTAssertNil(relaunched.lastNotificationImportAt)

        await relaunched.runNotificationCatchUp(now: resumedNow)

        let events = try freshWriter.fetchEvents(dayKey: ISO8601DayKey.format(initialNow))
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.text, freshNotification.body)
        XCTAssertEqual(relaunched.lastNotificationImportAt, resumedNow)
    }

    func testRefreshSelectedDayForTodayRequestsOnlyTodayWindow() async throws {
        let writer = try DatabaseWriter.inMemory()
        let reader = RecordingNotificationReader()
        let calendar = Calendar(identifier: .gregorian)
        let priorRun = try writer.startRun(runType: "daily-note", dayKey: "2026-04-09")
        try writer.finishRun(id: priorRun, status: "succeeded")
        let now = DateComponents(calendar: calendar, year: 2026, month: 4, day: 11, hour: 15, minute: 30).date!
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
                backfillPlanner: BackfillPlanner(calendar: calendar)
            )
        )
        let appState = AppState(environment: environment)

        await appState.refreshSelectedDay(now: now)

        XCTAssertEqual(reader.requestedSince, calendar.startOfDay(for: now))
        XCTAssertEqual(reader.requestedUpperBound, .inclusive(now))
        XCTAssertEqual(appState.selectedDate, "2026-04-11")
    }

    func testRefreshSelectedDayForTodayIgnoresFutureNotificationsLaterThatDay() async throws {
        let writer = try DatabaseWriter.inMemory()
        let reader = RecordingNotificationReader()
        let calendar = Calendar(identifier: .gregorian)
        let now = DateComponents(calendar: calendar, year: 2026, month: 4, day: 11, hour: 15, minute: 30).date!
        let dayKey = ISO8601DayKey.format(now)
        let beforeNowNotification = NotificationSnapshot(
            appName: "Calendar",
            deliveredAt: DateComponents(calendar: calendar, year: 2026, month: 4, day: 11, hour: 14, minute: 45).date!,
            body: "Already happened"
        )
        let afterNowNotification = NotificationSnapshot(
            appName: "Mail",
            deliveredAt: DateComponents(calendar: calendar, year: 2026, month: 4, day: 11, hour: 18, minute: 0).date!,
            body: "Future in day"
        )
        reader.fetchHandler = { _, _ in [beforeNowNotification, afterNowNotification] }

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
                contentHash: "today-event-with-future-filter"
            )
        )

        let environment = AppEnvironment(
            databaseURL: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).sqlite"),
            vaultURL: URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory),
            databaseWriter: writer,
            summarizer: nil,
            notificationReader: reader,
            dailyAutomationPlanner: DailyAutomationPlanner(
                backfillPlanner: BackfillPlanner(calendar: calendar)
            )
        )
        let appState = AppState(environment: environment)

        await appState.refreshSelectedDay(now: now)

        let events = try writer.fetchEvents(dayKey: dayKey)
        XCTAssertEqual(appState.notificationStatus.lastImportedCount, 1)
        XCTAssertEqual(reader.requestedUpperBound, .inclusive(now))
        XCTAssertTrue(events.contains(where: { $0.sourceType == .notification && $0.text == beforeNowNotification.body }))
        XCTAssertFalse(events.contains(where: { $0.sourceType == .notification && $0.text == afterNowNotification.body }))
    }

    func testRefreshSelectedDayForHistoricalDateRequestsOnlyThatDayWindow() async throws {
        let writer = try DatabaseWriter.inMemory()
        let reader = RecordingNotificationReader()
        let calendar = Calendar(identifier: .gregorian)
        let environment = AppEnvironment(
            databaseURL: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).sqlite"),
            vaultURL: URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory),
            databaseWriter: writer,
            summarizer: nil,
            notificationReader: reader,
            dailyAutomationPlanner: DailyAutomationPlanner(
                backfillPlanner: BackfillPlanner(calendar: calendar)
            )
        )
        let appState = AppState(environment: environment)
        appState.selectDate("2026-04-08")

        await appState.refreshSelectedDay(
            now: DateComponents(calendar: calendar, year: 2026, month: 4, day: 11).date!
        )

        let expectedStart = DateComponents(calendar: calendar, year: 2026, month: 4, day: 8).date!
        let expectedEnd = calendar.date(byAdding: .day, value: 1, to: expectedStart)
        XCTAssertEqual(reader.requestedSince, expectedStart)
        XCTAssertEqual(reader.requestedUpperBound, expectedEnd.map(NotificationFetchUpperBound.exclusive))
        XCTAssertEqual(appState.selectedDate, "2026-04-08")
    }

    func testRefreshSelectedDayDoesNotRunMultiDayAutomationBackfill() async throws {
        let writer = try DatabaseWriter.inMemory()
        let reader = RecordingNotificationReader()
        let calendar = Calendar(identifier: .gregorian)
        let priorRun = try writer.startRun(runType: "daily-note", dayKey: "2026-04-09")
        try writer.finishRun(id: priorRun, status: "succeeded")
        let selectedDay = "2026-04-08"
        let now = DateComponents(calendar: calendar, year: 2026, month: 4, day: 11, hour: 15, minute: 30).date!
        reader.snapshots = [
            NotificationSnapshot(
                appName: "Calendar",
                deliveredAt: DateComponents(calendar: calendar, year: 2026, month: 4, day: 8, hour: 9).date!,
                body: "Standup in 5"
            )
        ]

        let environment = AppEnvironment(
            databaseURL: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).sqlite"),
            vaultURL: URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory),
            databaseWriter: writer,
            summarizer: nil,
            notificationReader: reader,
            dailyAutomationPlanner: DailyAutomationPlanner(
                backfillPlanner: BackfillPlanner(calendar: calendar)
            )
        )
        let appState = AppState(environment: environment)
        appState.selectDate(selectedDay)

        let runsBeforeRefresh = try writer.fetchRuns(runType: "daily-note").count

        await appState.refreshSelectedDay(now: now)

        let runDaysAfterRefresh = try writer.fetchRuns(runType: "daily-note").map(\.dayKey)
        XCTAssertEqual(runDaysAfterRefresh.count, runsBeforeRefresh + 1)
        XCTAssertEqual(runDaysAfterRefresh.last, selectedDay)
        XCTAssertEqual(appState.selectedDate, selectedDay)
    }

    func testRefreshSelectedDayDoesNotCallAutomationPath() async throws {
        let writer = try DatabaseWriter.inMemory()
        let reader = RecordingNotificationReader()
        let calendar = Calendar(identifier: .gregorian)
        let now = DateComponents(calendar: calendar, year: 2026, month: 4, day: 11, hour: 15, minute: 30).date!
        reader.snapshots = [
            NotificationSnapshot(
                appName: "Calendar",
                deliveredAt: now,
                body: "Standup in 5"
            )
        ]

        let environment = AppEnvironment(
            databaseURL: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).sqlite"),
            vaultURL: URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory),
            databaseWriter: writer,
            summarizer: nil,
            notificationReader: reader,
            dailyAutomationPlanner: DailyAutomationPlanner(
                backfillPlanner: BackfillPlanner(calendar: calendar)
            )
        )
        let appState = AppState(environment: environment)

        await appState.refreshSelectedDay(now: now)

        XCTAssertNil(appState.lastAutomationRunAt)
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

    func testRefreshSelectedDayForHistoricalSelectionImportsOnlyThatDayNotifications() async throws {
        let writer = try DatabaseWriter.inMemory()
        let reader = RecordingNotificationReader()
        let calendar = Calendar(identifier: .gregorian)
        let historicalDay = "2026-04-06"
        let historicalStart = DateComponents(calendar: calendar, year: 2026, month: 4, day: 6).date!
        let capturedAt = DateComponents(calendar: calendar, year: 2026, month: 4, day: 6, hour: 9).date!
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
        let historicalNotification = NotificationSnapshot(
            appName: "Mail",
            deliveredAt: DateComponents(calendar: calendar, year: 2026, month: 4, day: 6, hour: 14).date!,
            body: "Historical notification"
        )
        let outsideDayNotification = NotificationSnapshot(
            appName: "Calendar",
            deliveredAt: DateComponents(calendar: calendar, year: 2026, month: 4, day: 7, hour: 8).date!,
            body: "Should not leak into 2026-04-06"
        )
        reader.fetchHandler = { _, _ in [historicalNotification, outsideDayNotification] }

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

        await appState.refreshSelectedDay(now: DateComponents(calendar: calendar, year: 2026, month: 4, day: 7).date!)

        let historicalEvents = try writer.fetchEvents(dayKey: historicalDay)
        XCTAssertEqual(reader.requestedSince, historicalStart)
        XCTAssertEqual(
            reader.requestedUpperBound,
            calendar.date(byAdding: .day, value: 1, to: historicalStart).map(NotificationFetchUpperBound.exclusive)
        )
        XCTAssertEqual(appState.notificationStatus.lastImportedCount, 1)
        XCTAssertEqual(historicalEvents.count, 2)
        XCTAssertTrue(historicalEvents.contains(where: { $0.sourceType == .notification && $0.text == historicalNotification.body }))
        XCTAssertEqual(try writer.fetchEvents(dayKey: "2026-04-07").count, 0)
        XCTAssertFalse(historicalEvents.contains(where: { $0.sourceType == .notification && $0.text == outsideDayNotification.body }))
        XCTAssertEqual(appState.selectedDate, historicalDay)
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

    func testRefreshSelectedDayStillGeneratesTodayWhenNotificationImportFails() async throws {
        let writer = try DatabaseWriter.inMemory()
        let reader = RecordingNotificationReader()
        reader.fetchError = CocoaError(.fileReadUnknown)
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
                contentHash: "today-import-failure"
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

        await appState.refreshSelectedDay(now: now)

        XCTAssertTrue(FileManager.default.fileExists(atPath: vaultURL.appending(path: "\(dayKey).md").path))
        XCTAssertEqual(appState.dayRefreshStatus.lastError, nil)
        XCTAssertEqual(reader.requestedUpperBound, .inclusive(now))
        XCTAssertEqual(appState.notificationStatus.lastError, CocoaError(.fileReadUnknown).localizedDescription)
        XCTAssertEqual(
            appState.statusMessage,
            "Refreshed today without notifications: \(CocoaError(.fileReadUnknown).localizedDescription)"
        )
    }

    func testRefreshSelectedDayPublishesVisibleStages() async throws {
        let writer = try DatabaseWriter.inMemory()
        let now = DateComponents(calendar: Calendar(identifier: .gregorian), year: 2026, month: 4, day: 11, hour: 10).date!
        try writer.insert(
            EventRecord(
                id: UUID(),
                sourceType: .clipboard,
                sourceApp: "Notes",
                capturedAt: now,
                dayKey: "2026-04-09",
                text: "Refresh this day",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "refresh-visible-stages"
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
        let recorder = RefreshStageRecorder()
        let appState = AppState(
            environment: environment,
            onRefreshStageChange: recorder.record
        )
        appState.selectDate("2026-04-09")

        await appState.refreshSelectedDay(
            now: DateComponents(calendar: Calendar(identifier: .gregorian), year: 2026, month: 4, day: 11).date!
        )

        XCTAssertEqual(
            recorder.stages,
            [.syncingNotifications, .loadingEvents, .preparingStory, .generatingStory, .writingFiles, .completed]
        )
    }

    func testRefreshSelectedDayRejectsDuplicateInFlightRefreshForSameDay() async throws {
        let (environment, gate) = try makeBlockingRefreshEnvironment()
        let appState = AppState(environment: environment)
        appState.selectDate("2026-04-09")
        let now = DateComponents(calendar: Calendar(identifier: .gregorian), year: 2026, month: 4, day: 11, hour: 15, minute: 30).date!

        let first = Task {
            await appState.refreshSelectedDay(now: now)
        }

        await gate.waitUntilStarted(dayKey: "2026-04-09")
        let second = Task {
            await appState.refreshSelectedDay(now: now)
        }

        await Task.yield()

        let startCount = await gate.startCount(for: "2026-04-09")
        XCTAssertEqual(startCount, 1)

        await gate.release(dayKey: "2026-04-09")
        _ = await (first.value, second.value)
    }

    func testRefreshDifferentDaysCanRunConcurrently() async throws {
        let (environment, gate) = try makeBlockingRefreshEnvironment()
        let appState = AppState(environment: environment)
        let now = DateComponents(calendar: Calendar(identifier: .gregorian), year: 2026, month: 4, day: 11, hour: 15, minute: 30).date!

        async let refreshNine: Void = appState.refreshDay("2026-04-09", now: now, environment: environment)
        async let refreshTen: Void = appState.refreshDay("2026-04-10", now: now, environment: environment)

        await gate.waitUntilStarted(dayKey: "2026-04-09")
        await gate.waitUntilStarted(dayKey: "2026-04-10")

        let startCountNine = await gate.startCount(for: "2026-04-09")
        let startCountTen = await gate.startCount(for: "2026-04-10")
        XCTAssertEqual(startCountNine, 1)
        XCTAssertEqual(startCountTen, 1)
        XCTAssertEqual(appState.refreshJob(for: "2026-04-09")?.stage, .generatingStory)
        XCTAssertEqual(appState.refreshJob(for: "2026-04-10")?.stage, .generatingStory)

        await gate.release(dayKey: "2026-04-09")
        await gate.release(dayKey: "2026-04-10")
        _ = await (refreshNine, refreshTen)
    }

    func testRefreshSelectedDayFor20260409CompletesWithVisibleTerminalState() async throws {
        let writer = try DatabaseWriter.inMemory()
        let capturedAt = DateComponents(calendar: Calendar(identifier: .gregorian), year: 2026, month: 4, day: 9, hour: 9).date!
        try writer.insert(
            EventRecord(
                id: UUID(),
                sourceType: .clipboard,
                sourceApp: "Notes",
                capturedAt: capturedAt,
                dayKey: "2026-04-09",
                text: "Regression refresh event",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "refresh-2026-04-09-terminal"
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
        let appState = AppState(environment: environment)
        appState.selectDate("2026-04-09")

        await appState.refreshSelectedDay(
            now: DateComponents(calendar: Calendar(identifier: .gregorian), year: 2026, month: 4, day: 11).date!
        )

        XCTAssertEqual(appState.refreshJob(for: "2026-04-09")?.stage, .completed)
    }

    func testRefreshSelectedDayTracksCompletedStagesAndTerminalSummary() async throws {
        let writer = try DatabaseWriter.inMemory()
        let capturedAt = DateComponents(calendar: Calendar(identifier: .gregorian), year: 2026, month: 4, day: 9, hour: 9).date!
        try writer.insert(
            EventRecord(
                id: UUID(),
                sourceType: .clipboard,
                sourceApp: "Notes",
                capturedAt: capturedAt,
                dayKey: "2026-04-09",
                text: "Regression refresh event",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "refresh-2026-04-09-summary"
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
        let appState = AppState(environment: environment)
        appState.selectDate("2026-04-09")

        await appState.refreshSelectedDay(
            now: DateComponents(calendar: Calendar(identifier: .gregorian), year: 2026, month: 4, day: 11).date!
        )

        XCTAssertEqual(
            appState.refreshJob(for: "2026-04-09")?.completedStages,
            [.syncingNotifications, .loadingEvents, .preparingStory, .generatingStory, .writingFiles]
        )
        XCTAssertEqual(
            appState.refreshJob(for: "2026-04-09")?.summary,
            "Completed · local fallback"
        )
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

    func testLoadsPersistedGlobalDiaryPromptOverrideState() {
        var config = SummarizerConfig.default
        config.globalDiaryPromptOverride = "Persisted custom diary prompt"
        config.save(
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

        XCTAssertTrue(appState.hasActiveGlobalDiaryPromptOverride)
        XCTAssertEqual(appState.activeGlobalDiaryPromptOverride, "Persisted custom diary prompt")
        XCTAssertTrue(appState.defaultGlobalDiaryPromptPreview.contains("English default prompt"))
        XCTAssertTrue(appState.defaultGlobalDiaryPromptPreview.contains("# You did a good job today"))
        XCTAssertTrue(appState.defaultGlobalDiaryPromptPreview.contains("中文默认 prompt"))
        XCTAssertTrue(appState.defaultGlobalDiaryPromptPreview.contains("# 你今天做得很棒"))
    }

    func testApplyingGlobalDiaryPromptOverridePersistsWithoutMutatingSelectedDayState() {
        let appState = AppState(
            bootstrapServices: false,
            userDefaults: engineDefaults,
            keychain: engineKeychain,
            keychainService: "MainWindowViewModelTests"
        )
        appState.selectedDate = "2026-04-12"
        appState.selectedMarkdownURL = URL(fileURLWithPath: "/tmp/2026-04-12.md")
        appState.selectedContentVersion = 7
        appState.selectedStoryParagraphID = "daily-journal-0"
        appState.selectedStory = DailyStory(
            dayKey: "2026-04-12",
            generatedAt: Date(timeIntervalSince1970: 1_776_000_000),
            sections: [
                DailyStorySection(
                    id: "daily-journal",
                    title: "",
                    paragraphs: [
                        DailyStoryParagraph(
                            id: "daily-journal-0",
                            text: "Existing paragraph",
                            sourceEventIDs: []
                        )
                    ]
                )
            ]
        )

        appState.applyGlobalDiaryPromptOverride("Custom global diary prompt")

        XCTAssertTrue(appState.hasActiveGlobalDiaryPromptOverride)
        XCTAssertEqual(appState.activeGlobalDiaryPromptOverride, "Custom global diary prompt")
        XCTAssertEqual(appState.selectedDate, "2026-04-12")
        XCTAssertEqual(appState.selectedMarkdownURL?.path, "/tmp/2026-04-12.md")
        XCTAssertEqual(appState.selectedContentVersion, 7)
        XCTAssertEqual(appState.selectedStoryParagraphID, "daily-journal-0")
        XCTAssertEqual(appState.selectedStory?.sections.first?.paragraphs.first?.text, "Existing paragraph")

        let persistedConfig = SummarizerConfig.load(
            from: engineDefaults,
            keychain: engineKeychain,
            keychainService: "MainWindowViewModelTests"
        )
        XCTAssertEqual(persistedConfig.globalDiaryPromptOverride, "Custom global diary prompt")
    }

    func testRestoringDefaultGlobalDiaryPromptClearsPersistedOverrideWithoutMutatingSelectedDayState() {
        var config = SummarizerConfig.default
        config.globalDiaryPromptOverride = "Old custom prompt"
        let appState = AppState(
            bootstrapServices: false,
            summarizerConfig: config,
            userDefaults: engineDefaults,
            keychain: engineKeychain,
            keychainService: "MainWindowViewModelTests"
        )
        appState.selectedDate = "2026-04-12"
        appState.selectedMarkdownURL = URL(fileURLWithPath: "/tmp/2026-04-12.md")
        appState.selectedContentVersion = 11
        appState.selectedStoryParagraphID = "daily-journal-0"

        appState.restoreDefaultGlobalDiaryPrompt()

        XCTAssertFalse(appState.hasActiveGlobalDiaryPromptOverride)
        XCTAssertEqual(appState.activeGlobalDiaryPromptOverride, "")
        XCTAssertEqual(appState.selectedDate, "2026-04-12")
        XCTAssertEqual(appState.selectedMarkdownURL?.path, "/tmp/2026-04-12.md")
        XCTAssertEqual(appState.selectedContentVersion, 11)
        XCTAssertEqual(appState.selectedStoryParagraphID, "daily-journal-0")

        let persistedConfig = SummarizerConfig.load(
            from: engineDefaults,
            keychain: engineKeychain,
            keychainService: "MainWindowViewModelTests"
        )
        XCTAssertNil(persistedConfig.globalDiaryPromptOverride)
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

    func testRetestAllEnginesAutoSelectsHighestPriorityGreenEngineWhenDefaultIsNone() async {
        let verifiedAt = Date(timeIntervalSince1970: 1_775_350_000)
        let appState = AppState(
            bootstrapServices: false,
            summarizerConfig: .default,
            probeEngine: { engine, _, _ in
                switch engine {
                case .codexCLI, .geminiCLI:
                    return EngineProbeResult(
                        engine: engine,
                        state: .green,
                        detail: "Smoke test succeeded.",
                        verifiedAt: verifiedAt
                    )
                default:
                    return EngineProbeResult(
                        engine: engine,
                        state: .gray,
                        detail: "Executable not found.",
                        verifiedAt: nil
                    )
                }
            },
            userDefaults: engineDefaults,
            keychain: engineKeychain,
            keychainService: "MainWindowViewModelTests"
        )

        await appState.retestAllEngines()

        XCTAssertEqual(appState.defaultEngine, .codexCLI)
        XCTAssertEqual(
            SummarizerConfig.load(
                from: engineDefaults,
                keychain: engineKeychain,
                keychainService: "MainWindowViewModelTests"
            ).defaultEngine,
            .codexCLI
        )
    }

    func testRetestAllEnginesDoesNotOverrideExplicitDefaultEngine() async throws {
        let codexURL = try makeStubExecutable(named: "codex")
        let geminiURL = try makeStubExecutable(named: "gemini")
        var config = SummarizerConfig.default
        config.defaultEngine = .geminiCLI
        config.codexCLIPath = codexURL.path
        config.geminiCLIPath = geminiURL.path
        let verifiedAt = Date(timeIntervalSince1970: 1_775_360_000)

        let appState = AppState(
            bootstrapServices: false,
            summarizerConfig: config,
            probeEngine: { engine, _, _ in
                let state: EngineIndicatorState = switch engine {
                case .codexCLI, .geminiCLI:
                    .green
                default:
                    .gray
                }
                return EngineProbeResult(
                    engine: engine,
                    state: state,
                    detail: state == .green ? "Smoke test succeeded." : "Executable not found.",
                    verifiedAt: state == .green ? verifiedAt : nil
                )
            },
            userDefaults: engineDefaults,
            keychain: engineKeychain,
            keychainService: "MainWindowViewModelTests"
        )

        await appState.retestAllEngines()

        XCTAssertEqual(appState.defaultEngine, .geminiCLI)
        XCTAssertEqual(appState.engineStatuses[.geminiCLI]?.state, .green)
        XCTAssertEqual(appState.engineStatuses[.codexCLI]?.state, .green)
    }

    func testExplicitlyDisabledEngineStaysNoneAcrossRefreshAndRetestReconciliation() async throws {
        let codexURL = try makeStubExecutable(named: "codex")
        var config = SummarizerConfig.default
        config.codexCLIPath = codexURL.path

        let verifiedAt = Date(timeIntervalSince1970: 1_775_370_000)
        let appState = AppState(
            bootstrapServices: false,
            summarizerConfig: config,
            probeEngine: { engine, _, _ in
                let state: EngineIndicatorState = engine == .codexCLI ? .green : .gray
                return EngineProbeResult(
                    engine: engine,
                    state: state,
                    detail: state == .green ? "Smoke test succeeded." : "Executable not found.",
                    verifiedAt: state == .green ? verifiedAt : nil
                )
            },
            userDefaults: engineDefaults,
            keychain: engineKeychain,
            keychainService: "MainWindowViewModelTests"
        )
        appState.engineStatuses[.codexCLI] = EngineRuntimeStatus(
            state: .green,
            detail: "Smoke test succeeded.",
            lastVerifiedAt: verifiedAt,
            configurationSignature: "codex|\(codexURL.path)"
        )

        appState.selectDefaultEngine(.codexCLI)
        appState.selectDefaultEngine(.none)
        appState.refreshEngineStatuses()

        XCTAssertEqual(appState.defaultEngine, .none)
        XCTAssertEqual(
            SummarizerConfig.load(
                from: engineDefaults,
                keychain: engineKeychain,
                keychainService: "MainWindowViewModelTests"
            ).defaultEngine,
            .none
        )

        await appState.retestAllEngines()

        XCTAssertEqual(appState.defaultEngine, .none)
        XCTAssertEqual(
            SummarizerConfig.load(
                from: engineDefaults,
                keychain: engineKeychain,
                keychainService: "MainWindowViewModelTests"
            ).defaultEngine,
            .none
        )
        XCTAssertEqual(appState.engineStatuses[.codexCLI]?.state, .green)
    }

    func testLoadedDefaultNoneAutoPicksVerifiedEngineWhenSuppressionWasNeverSaved() async throws {
        let codexURL = try makeStubExecutable(named: "codex")
        var config = SummarizerConfig.default
        config.defaultEngine = .none
        config.codexCLIPath = codexURL.path
        config.save(
            to: engineDefaults,
            keychain: engineKeychain,
            keychainService: "MainWindowViewModelTests"
        )
        engineDefaults.removeObject(forKey: AppState.UserDefaultsKeys.explicitlyDisabledSummarizerAutoSelection)

        let verifiedAt = Date(timeIntervalSince1970: 1_775_380_000)
        let appState = AppState(
            bootstrapServices: false,
            probeEngine: { engine, _, _ in
                let state: EngineIndicatorState = engine == .codexCLI ? .green : .gray
                return EngineProbeResult(
                    engine: engine,
                    state: state,
                    detail: state == .green ? "Smoke test succeeded." : "Executable not found.",
                    verifiedAt: state == .green ? verifiedAt : nil
                )
            },
            userDefaults: engineDefaults,
            keychain: engineKeychain,
            keychainService: "MainWindowViewModelTests"
        )

        XCTAssertEqual(appState.defaultEngine, .none)
        XCTAssertNil(
            engineDefaults.object(forKey: AppState.UserDefaultsKeys.explicitlyDisabledSummarizerAutoSelection)
        )

        await appState.retestAllEngines()

        XCTAssertEqual(appState.defaultEngine, .codexCLI)
        XCTAssertEqual(
            SummarizerConfig.load(
                from: engineDefaults,
                keychain: engineKeychain,
                keychainService: "MainWindowViewModelTests"
            ).defaultEngine,
            .codexCLI
        )
        XCTAssertEqual(
            engineDefaults.object(forKey: AppState.UserDefaultsKeys.explicitlyDisabledSummarizerAutoSelection) as? Bool,
            false
        )
    }

    func testLoadedDefaultNoneRemainsEligibleForAutoPickWhenSuppressionWasNeverSaved() async throws {
        let codexURL = try makeStubExecutable(named: "codex")
        var config = SummarizerConfig.default
        config.defaultEngine = .none
        config.codexCLIPath = codexURL.path
        config.save(
            to: engineDefaults,
            keychain: engineKeychain,
            keychainService: "MainWindowViewModelTests"
        )

        let verifiedAt = Date(timeIntervalSince1970: 1_775_381_000)
        let appState = AppState(
            bootstrapServices: false,
            probeEngine: { engine, _, _ in
                let state: EngineIndicatorState = engine == .codexCLI ? .green : .gray
                return EngineProbeResult(
                    engine: engine,
                    state: state,
                    detail: state == .green ? "Smoke test succeeded." : "Executable not found.",
                    verifiedAt: state == .green ? verifiedAt : nil
                )
            },
            userDefaults: engineDefaults,
            keychain: engineKeychain,
            keychainService: "MainWindowViewModelTests"
        )

        XCTAssertEqual(appState.defaultEngine, .none)
        XCTAssertNil(
            engineDefaults.object(forKey: AppState.UserDefaultsKeys.explicitlyDisabledSummarizerAutoSelection)
        )

        await appState.retestEngine(.codexCLI)

        XCTAssertEqual(appState.defaultEngine, .codexCLI)
        XCTAssertEqual(
            SummarizerConfig.load(
                from: engineDefaults,
                keychain: engineKeychain,
                keychainService: "MainWindowViewModelTests"
            ).defaultEngine,
            .codexCLI
        )
        XCTAssertEqual(
            engineDefaults.object(forKey: AppState.UserDefaultsKeys.explicitlyDisabledSummarizerAutoSelection) as? Bool,
            false
        )
    }

    func testRetestRebuildsActiveSummarizerWhenCurrentDefaultTurnsGreen() async throws {
        let executableDirectory = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: executableDirectory, withIntermediateDirectories: true)
        let codexURL = executableDirectory.appending(path: "codex")
        var initialConfig = SummarizerConfig.default
        initialConfig.defaultEngine = .codexCLI
        initialConfig.codexCLIPath = codexURL.path

        let verifiedAt = Date(timeIntervalSince1970: 1_775_382_000)
        let environment = try makeEngineEnvironment()
        let appState = AppState(
            environment: environment,
            summarizerConfig: initialConfig,
            probeEngine: { engine, config, _ in
                let state: EngineIndicatorState = engine == .codexCLI &&
                    FileManager.default.isExecutableFile(atPath: config.codexCLIPath)
                    ? .green
                    : .gray
                return EngineProbeResult(
                    engine: engine,
                    state: state,
                    detail: state == .green ? "Smoke test succeeded." : "Executable not found.",
                    verifiedAt: state == .green ? verifiedAt : nil
                )
            },
            userDefaults: engineDefaults,
            keychain: engineKeychain,
            keychainService: "MainWindowViewModelTests"
        )

        XCTAssertEqual(appState.defaultEngine, .codexCLI)
        XCTAssertNil(appState.environment?.summarizer)

        try "#!/bin/sh\nexit 0\n".write(to: codexURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: codexURL.path)

        await appState.retestEngine(.codexCLI)

        let activeSummarizer = try XCTUnwrap(appState.environment?.summarizer as? CLISummarizer)
        XCTAssertEqual(activeSummarizer.tool, .codex)
        XCTAssertEqual(activeSummarizer.executablePath, codexURL.path)
        XCTAssertEqual(appState.engineStatuses[.codexCLI]?.state, .green)
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

    func testGenerateStoryUsesSavedGlobalDiaryPromptOverrideInLiveSummarizerPath() async throws {
        let writer = try DatabaseWriter.inMemory()
        let dayKey = "2026-04-12"
        let eventID = UUID()
        try writer.insert(
            EventRecord(
                id: eventID,
                sourceType: .clipboard,
                sourceApp: "Notes",
                capturedAt: Date(timeIntervalSince1970: 1_775_700_000),
                dayKey: dayKey,
                text: "Captured a real prompt integration test",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "prompt-integration"
            )
        )

        let response = """
        {"sections":[{"id":"daily-journal","paragraphs":[{"text":"# Summary\\n- Captured a real prompt integration test","sourceEventIDs":["\(eventID.uuidString)"]}]}]}
        """
        let summarizer = RecordingPromptSummarizer(response: response)
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
        config.globalDiaryPromptOverride = "Custom live global diary prompt override"
        let appState = AppState(
            environment: environment,
            summarizerConfig: config,
            userDefaults: engineDefaults,
            keychain: engineKeychain,
            keychainService: "MainWindowViewModelTests"
        )
        environment.summarizer = summarizer
        let events = try writer.fetchEvents(dayKey: dayKey)

        let story = await appState.generateStory(dayKey: dayKey, events: events, environment: environment)

        XCTAssertEqual(summarizer.capturedDayKey, dayKey)
        XCTAssertEqual(summarizer.capturedMarkdown, "Custom live global diary prompt override")
        XCTAssertEqual(story.provenance?.generationMode, .model)
        XCTAssertEqual(story.provenance?.engineKind, DiaryEngine.codexCLI.rawValue)
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

    func testCompleteOnboardingPersistsGraySelectedEngineWithoutBlocking() throws {
        var config = SummarizerConfig.default
        config.defaultEngine = .claudeCLI
        config.claudeCLIPath = "/definitely/missing/claude"

        let environment = try makeEngineEnvironment()
        let appState = AppState(
            environment: environment,
            summarizerConfig: config,
            userDefaults: engineDefaults,
            keychain: engineKeychain,
            keychainService: "MainWindowViewModelTests"
        )
        let vaultURL = URL(fileURLWithPath: "/tmp/\(UUID().uuidString)", isDirectory: true)

        appState.completeOnboarding(vaultURL: vaultURL, preferredEngine: .claudeCLI)

        XCTAssertEqual(appState.defaultEngine, .claudeCLI)
        XCTAssertNil(appState.environment?.summarizer)
        XCTAssertEqual(
            SummarizerConfig.load(
                from: engineDefaults,
                keychain: engineKeychain,
                keychainService: "MainWindowViewModelTests"
            ).defaultEngine,
            .claudeCLI
        )
    }

    func testCompleteOnboardingWithNonePreservesExplicitDisableAcrossLaterReconciliation() throws {
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
            lastVerifiedAt: Date(timeIntervalSince1970: 1_775_620_000),
            configurationSignature: "gemini|\(executableURL.path)"
        )
        let vaultURL = URL(fileURLWithPath: "/tmp/\(UUID().uuidString)", isDirectory: true)

        appState.completeOnboarding(vaultURL: vaultURL, preferredEngine: .none)
        appState.refreshEngineStatuses()

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

    func testInitPreservesPersistedUnverifiedDefaultEngineChoice() throws {
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

        XCTAssertEqual(appState.defaultEngine, .codexCLI)
        XCTAssertEqual(appState.summarizerStatus.mode, DiaryEngine.codexCLI.displayName)
        XCTAssertTrue(appState.summarizerStatus.isConfigured)
        XCTAssertEqual(appState.engineStatuses[.codexCLI]?.state, .yellow)
        XCTAssertEqual(appState.engineStatuses[.codexCLI]?.detail, "Executable found. Retest required.")
        XCTAssertEqual(
            SummarizerConfig.load(
                from: engineDefaults,
                keychain: engineKeychain,
                keychainService: "MainWindowViewModelTests"
            ).defaultEngine,
            .codexCLI
        )
    }

    func testInitPreservesPersistedGrayDefaultEngineChoice() throws {
        var persistedConfig = SummarizerConfig.default
        persistedConfig.defaultEngine = .claudeCLI
        persistedConfig.claudeCLIPath = "/definitely/missing/claude"
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

        XCTAssertEqual(appState.defaultEngine, .claudeCLI)
        XCTAssertEqual(appState.summarizerStatus.mode, DiaryEngine.claudeCLI.displayName)
        XCTAssertFalse(appState.summarizerStatus.isConfigured)
        XCTAssertEqual(appState.engineStatuses[.claudeCLI]?.state, .gray)
        XCTAssertEqual(appState.engineStatuses[.claudeCLI]?.detail, "Executable not found.")
        XCTAssertEqual(
            SummarizerConfig.load(
                from: engineDefaults,
                keychain: engineKeychain,
                keychainService: "MainWindowViewModelTests"
            ).defaultEngine,
            .claudeCLI
        )
    }

    func testRestartAfterActiveEngineDegradesPreservesPersistedYellowEngineChoice() throws {
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

        XCTAssertEqual(relaunched.defaultEngine, .codexCLI)
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
