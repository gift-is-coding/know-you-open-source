import XCTest
@testable import KnowYou

private struct ThrowingSummarizer: SummaryGenerating {
    func summarize(dayKey: String, markdown: String, context: SummaryInvocationContext) async throws -> String {
        throw URLError(.cannotConnectToHost)
    }
}

private struct StaticSummarizer: SummaryGenerating {
    let response: String

    func summarize(dayKey: String, markdown: String, context: SummaryInvocationContext) async throws -> String {
        response
    }
}

private struct HandlerSummarizer: SummaryGenerating {
    let handler: @Sendable (String, String, SummaryInvocationContext) async throws -> String

    func summarize(dayKey: String, markdown: String, context: SummaryInvocationContext) async throws -> String {
        try await handler(dayKey, markdown, context)
    }
}

private actor EngineAttemptRecorder {
    private var attempts: [DiaryEngine] = []

    func record(_ engine: DiaryEngine) {
        attempts.append(engine)
    }

    func values() -> [DiaryEngine] {
        attempts
    }
}

private actor ParallelAttemptRecorder {
    private var started: [DiaryEngine] = []
    private var cancelled: [DiaryEngine] = []
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func recordStart(_ engine: DiaryEngine) {
        started.append(engine)
        if started.contains(.geminiCLI), started.contains(.claudeCLI) {
            let continuations = waiters
            waiters.removeAll()
            continuations.forEach { $0.resume() }
        }
    }

    func waitForGeminiAndClaudeToStart() async {
        if started.contains(.geminiCLI), started.contains(.claudeCLI) {
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func recordCancelled(_ engine: DiaryEngine) {
        cancelled.append(engine)
    }

    func snapshot() -> (started: [DiaryEngine], cancelled: [DiaryEngine]) {
        (started, cancelled)
    }
}

private final class RecordingPromptSummarizer: SummaryGenerating, @unchecked Sendable {
    let response: String
    private(set) var capturedDayKey: String?
    private(set) var capturedMarkdown: String?

    init(response: String) {
        self.response = response
    }

    func summarize(dayKey: String, markdown: String, context: SummaryInvocationContext) async throws -> String {
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

    func summarize(dayKey: String, markdown: String, context: SummaryInvocationContext) async throws -> String {
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

private func waitUntilAsync(
    timeoutNanoseconds: UInt64 = 1_000_000_000,
    pollNanoseconds: UInt64 = 10_000_000,
    condition: @escaping @Sendable () async -> Bool
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

private func makeValidStoryResponse(sourceEventID: UUID = UUID(), summaryLine: String = "Recovered day") -> String {
    """
    {"sections":[{"id":"daily-journal","paragraphs":[{"text":"# Summary\\n- \(summaryLine)","sourceEventIDs":["\(sourceEventID.uuidString)"]}]}]}
    """
}

private func makeIsolatedCLIProcessEnvironment() throws -> ([String: String], URL) {
    let homeURL = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
    return (
        [
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "HOME": homeURL.path,
        ],
        homeURL
    )
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

    func testAutomationStatusTextReflectsManualOnlyHistoryPolicy() {
        let appState = AppState(bootstrapServices: false)
        appState.lastImportedNotificationCount = 3
        appState.pendingBackfillDays = ["2026-04-06", "2026-04-07"]

        XCTAssertTrue(appState.automationStatusText.contains("Notifications: 3"))
        XCTAssertTrue(appState.automationStatusText.contains("History refresh is manual-only"))
    }

    func testGenerateDailyNoteFailsWithoutPersistingFilesWhenSummarizerFails() async throws {
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
        XCTAssertFalse(FileManager.default.fileExists(atPath: savedURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: storyURL.path))
        XCTAssertTrue(appState.statusMessage?.contains("Daily note failed:") == true)
        XCTAssertEqual(appState.summarizerStatus.lastError, URLError(.cannotConnectToHost).localizedDescription)
        XCTAssertNil(appState.selectedStory)
        XCTAssertEqual(try writer.fetchRuns(runType: "daily-note").last?.status, "failed")
    }

    func testGenerateDailyNotePreservesExistingModelStoryWhenNoNewEventsExist() async throws {
        let writer = try DatabaseWriter.inMemory()
        let dayKey = "2026-04-07"
        let capturedAt = Date(timeIntervalSince1970: 1_775_000_000)
        let eventID = UUID()
        try writer.insert(
            EventRecord(
                id: eventID,
                sourceType: .clipboard,
                sourceApp: "Notes",
                capturedAt: capturedAt,
                dayKey: dayKey,
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
        let existingStory = makeModelStory(dayKey: dayKey, eventID: eventID)
        let existingMarkdown = "# Existing model story\nStill good."
        _ = try environment.writeDailyNote(dayKey: dayKey, markdown: existingMarkdown)
        _ = try environment.writeDailyStory(existingStory)

        await appState.generateDailyNote(for: dayKey)

        let savedURL = vaultURL.appending(path: "\(dayKey).md")
        let storyURL = vaultURL.appending(path: "\(dayKey).story.json")
        XCTAssertEqual(try String(contentsOf: savedURL, encoding: .utf8), existingMarkdown)
        XCTAssertEqual(try environment.loadDailyStory(dayKey: dayKey), existingStory)
        XCTAssertEqual(appState.statusMessage, "Refreshed \(dayKey)")
        XCTAssertNil(appState.dayRefreshStatus.lastError)
        XCTAssertEqual(appState.dayRefreshStatus.detail, "No new events to append for \(dayKey)")
        XCTAssertEqual(appState.refreshJob(for: dayKey)?.detail, "Completed · No new events")
        XCTAssertEqual(try writer.fetchRuns(runType: "daily-note").last?.status, "succeeded")
        XCTAssertEqual(try JSONDecoder().decode(DailyStory.self, from: Data(contentsOf: storyURL)), existingStory)
    }

    func testRunAutomationImportsNotificationsFromStartOfToday() async throws {
        let writer = try DatabaseWriter.inMemory()
        let completedRun = try writer.startRun(runType: "daily-note", dayKey: "2026-04-01")
        try writer.finishRun(id: completedRun, status: "succeeded")

        let reader = RecordingNotificationReader()
        let vaultURL = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let environment = AppEnvironment(
            databaseURL: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).sqlite"),
            vaultURL: vaultURL,
            databaseWriter: writer,
            summarizer: StaticSummarizer(response: makeValidStoryResponse(summaryLine: "Today kept despite notification failure")),
            notificationReader: reader,
            dailyAutomationPlanner: DailyAutomationPlanner(
                backfillPlanner: BackfillPlanner(calendar: Calendar(identifier: .gregorian))
            )
        )
        let appState = AppState(environment: environment)

        await appState.runAutomation(now: DateComponents(calendar: Calendar(identifier: .gregorian), year: 2026, month: 4, day: 7).date!)

        XCTAssertEqual(
            ISO8601DayKey.format(reader.requestedSince ?? .distantPast),
            "2026-04-07"
        )
    }

    func testRunAutomationFullRecoversTodayWhenOnlyMarkdownAlreadyExists() async throws {
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
            summarizer: StaticSummarizer(response: makeValidStoryResponse(summaryLine: "Selected day refreshed")),
            notificationReader: RecordingNotificationReader(),
            dailyAutomationPlanner: DailyAutomationPlanner(
                backfillPlanner: BackfillPlanner(calendar: Calendar(identifier: .gregorian))
            )
        )
        let appState = AppState(environment: environment)

        await appState.runAutomation(now: capturedAt)

        let rebuiltMarkdown = try String(contentsOf: existingNoteURL)
        XCTAssertNotEqual(rebuiltMarkdown, "stale note")
        XCTAssertEqual(appState.selectedDate, today)
        XCTAssertEqual(
            appState.selectedMarkdownURL?.standardizedFileURL.path,
            existingNoteURL.standardizedFileURL.path
        )
        XCTAssertEqual(try environment.loadDailyStory(dayKey: today)?.provenance?.generationMode, .model)
        XCTAssertEqual(try writer.fetchRuns(runType: "daily-note").last?.status, "succeeded")
    }

    func testRunAutomationFullRecoversTodayWhenNoModelStoryExists() async throws {
        let writer = try DatabaseWriter.inMemory()
        let calendar = Calendar(identifier: .gregorian)
        let dayKey = "2026-04-07"
        let capturedAt = DateComponents(calendar: calendar, year: 2026, month: 4, day: 7, hour: 9).date!
        try writer.insert(
            EventRecord(
                id: UUID(),
                sourceType: .clipboard,
                sourceApp: "Notes",
                capturedAt: capturedAt,
                dayKey: dayKey,
                text: "Fresh start for the day",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "automation-first-full-recovery"
            )
        )

        let vaultURL = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let environment = AppEnvironment(
            databaseURL: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).sqlite"),
            vaultURL: vaultURL,
            databaseWriter: writer,
            summarizer: StaticSummarizer(response: makeValidStoryResponse(summaryLine: "Automation created the first story")),
            notificationReader: RecordingNotificationReader(),
            dailyAutomationPlanner: DailyAutomationPlanner(
                backfillPlanner: BackfillPlanner(calendar: calendar)
            )
        )
        let appState = AppState(environment: environment)

        await appState.runAutomation(now: DateComponents(calendar: calendar, year: 2026, month: 4, day: 7, hour: 12).date!)

        XCTAssertTrue(FileManager.default.fileExists(atPath: vaultURL.appending(path: "\(dayKey).md").path))
        XCTAssertEqual(try environment.loadDailyStory(dayKey: dayKey)?.provenance?.generationMode, .model)
        XCTAssertEqual(try writer.fetchRuns(runType: "daily-note").last?.status, "succeeded")
    }

    func testRunAutomationWithoutVerifiedEnginePromptsConfigurationForFreshToday() async throws {
        let writer = try DatabaseWriter.inMemory()
        let calendar = Calendar(identifier: .gregorian)
        let dayKey = "2026-04-07"
        try writer.insert(
            EventRecord(
                id: UUID(),
                sourceType: .clipboard,
                sourceApp: "Notes",
                capturedAt: DateComponents(calendar: calendar, year: 2026, month: 4, day: 7, hour: 9).date!,
                dayKey: dayKey,
                text: "Need an engine before automation can write",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "automation-no-engine"
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
                backfillPlanner: BackfillPlanner(calendar: calendar)
            )
        )
        let appState = AppState(environment: environment)

        await appState.runAutomation(now: DateComponents(calendar: calendar, year: 2026, month: 4, day: 7, hour: 12).date!)

        XCTAssertEqual(appState.statusMessage, "Configure and verify an engine to generate today's journal")
        XCTAssertFalse(FileManager.default.fileExists(atPath: vaultURL.appending(path: "\(dayKey).md").path))
        XCTAssertNil(try writer.fetchRuns(runType: "daily-note").last)
    }

    func testRunAutomationAppendsTodayWhenModelStoryHasNewEvents() async throws {
        let writer = try DatabaseWriter.inMemory()
        let calendar = Calendar(identifier: .gregorian)
        let dayKey = "2026-04-07"
        let oldID = UUID()
        let newID = UUID()
        let oldEvent = EventRecord(
            id: oldID,
            sourceType: .clipboard,
            sourceApp: "Notes",
            capturedAt: DateComponents(calendar: calendar, year: 2026, month: 4, day: 7, hour: 9).date!,
            dayKey: dayKey,
            text: "Wrapped the first pass",
            auditText: nil,
            privacyAction: .keep,
            contentHash: "old-event"
        )
        let newEvent = EventRecord(
            id: newID,
            sourceType: .notification,
            sourceApp: "Mail",
            capturedAt: DateComponents(calendar: calendar, year: 2026, month: 4, day: 7, hour: 11).date!,
            dayKey: dayKey,
            text: "Customer approved the follow-up",
            auditText: nil,
            privacyAction: .keep,
            contentHash: "new-event"
        )
        try writer.insert(oldEvent)
        try writer.insert(newEvent)

        let vaultURL = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let environment = AppEnvironment(
            databaseURL: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).sqlite"),
            vaultURL: vaultURL,
            databaseWriter: writer,
            summarizer: nil,
            notificationReader: RecordingNotificationReader(),
            dailyAutomationPlanner: DailyAutomationPlanner(
                backfillPlanner: BackfillPlanner(calendar: calendar)
            )
        )
        let initialStory = DailyStory(
            dayKey: dayKey,
            generatedAt: Date(timeIntervalSince1970: 1_775_000_000),
            sections: [
                DailyStorySection(
                    id: "daily-journal",
                    title: "",
                    paragraphs: [
                        DailyStoryParagraph(
                            id: "daily-journal-0",
                            text: """
                            # You did a good job today

                            Keep the pace.

                            # Summary

                            - Wrapped the first pass

                            # Details

                            ## Existing Thread

                            Closed the first workflow.

                            # To-do

                            - [ ] Send recap
                            """,
                            sourceEventIDs: [oldID]
                        )
                    ]
                )
            ],
            provenance: StoryProvenance(
                generationMode: .model,
                engineKind: "codexCLI",
                engineLabel: "Codex (CLI)",
                model: nil,
                pipelineVersion: "diary-story-v1",
                curatedEventCount: 1
            )
        )
        try writeStoryDay(
            dayKey: dayKey,
            markdown: environment.composer.compose(dayKey: dayKey, events: [oldEvent], story: initialStory),
            story: initialStory,
            environment: environment
        )

        var config = SummarizerConfig.default
        config.defaultEngine = .codexCLI
        let appState = AppState(
            environment: environment,
            summarizerConfig: config,
            makeSummarizer: { engine, _, _ in
                guard engine == .codexCLI else { return nil }
                return StaticSummarizer(
                    response: """
                    {
                      "encouragementToReplace": { "text": "Keep the pace.", "sourceEventIDs": ["\(oldID.uuidString)", "\(newID.uuidString)"] },
                      "summaryBulletsToReplace": [
                        { "text": "- Wrapped the first pass", "sourceEventIDs": ["\(oldID.uuidString)"] },
                        { "text": "- Customer approved the follow-up", "sourceEventIDs": ["\(newID.uuidString)"] }
                      ],
                      "detailBlocksToAppend": [{ "text": "## Follow-up\\n\\nHandled the approval loop.", "sourceEventIDs": ["\(newID.uuidString)"] }],
                      "todoItemsToReplace": [
                        { "text": "- [ ] Send recap", "sourceEventIDs": ["\(oldID.uuidString)"] },
                        { "text": "- [ ] Queue the final handoff", "sourceEventIDs": ["\(newID.uuidString)"] }
                      ]
                    }
                    """
                )
            }
        )
        appState.engineStatuses[.codexCLI] = EngineRuntimeStatus(
            state: .green,
            detail: "Ready.",
            lastVerifiedAt: Date(),
            configurationSignature: "codex"
        )

        await appState.runAutomation(now: DateComponents(calendar: calendar, year: 2026, month: 4, day: 7, hour: 12).date!)

        let markdown = try String(contentsOf: vaultURL.appending(path: "\(dayKey).md"))
        XCTAssertTrue(markdown.contains("Keep the pace."))
        XCTAssertTrue(markdown.contains("- Customer approved the follow-up"))
        XCTAssertTrue(markdown.contains("## Follow-up"))
        XCTAssertTrue(markdown.contains("- [ ] Queue the final handoff"))
        XCTAssertEqual(try writer.fetchRuns(runType: "daily-note").last?.dayKey, dayKey)
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
            summarizer: StaticSummarizer(response: makeValidStoryResponse(summaryLine: "Selected day refreshed")),
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
            summarizer: StaticSummarizer(response: makeValidStoryResponse(summaryLine: "Selected day refreshed")),
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
            summarizer: StaticSummarizer(response: makeValidStoryResponse(summaryLine: "Today kept despite notification failure")),
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

    func testStartAutomationStillRunsTodayOnlyAutomationWhileSchedulingCatchUp() async throws {
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
        XCTAssertEqual(appState.lastAutomationRunAt, now)
        XCTAssertEqual(appState.notificationStatus.lastImportedCount, 1)
        XCTAssertNil(try writer.fetchRuns(runType: "daily-note").last)
        XCTAssertFalse(FileManager.default.fileExists(atPath: vaultURL.appending(path: "\(dayKey).md").path))
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
            summarizer: StaticSummarizer(response: makeValidStoryResponse(summaryLine: "Selected day refreshed")),
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
            summarizer: StaticSummarizer(response: makeValidStoryResponse(summaryLine: "Selected day refreshed")),
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
            summarizer: StaticSummarizer(response: makeValidStoryResponse(summaryLine: "Selected day refreshed")),
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
            summarizer: StaticSummarizer(response: makeValidStoryResponse(summaryLine: "Today refreshed")),
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
            summarizer: StaticSummarizer(response: makeValidStoryResponse(summaryLine: "Today kept despite notification failure")),
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
            summarizer: StaticSummarizer(response: makeValidStoryResponse(summaryLine: "Today kept despite notification failure")),
            notificationReader: reader,
            dailyAutomationPlanner: DailyAutomationPlanner(
                backfillPlanner: BackfillPlanner(calendar: Calendar(identifier: .gregorian))
            )
        )
        let appState = AppState(environment: environment)

        await appState.runAutomation(now: DateComponents(calendar: Calendar(identifier: .gregorian), year: 2026, month: 4, day: 7).date!)

        XCTAssertEqual(appState.notificationStatus.lastError, CocoaError(.fileReadUnknown).localizedDescription)
    }

    func testRunAutomationDoesNotBackfillHistoricalDays() async throws {
        let calendar = Calendar(identifier: .gregorian)
        let writer = try DatabaseWriter.inMemory()
        let runID = try writer.startRun(runType: "daily-note", dayKey: "2026-04-08")
        try writer.finishRun(id: runID, status: "succeeded")

        try writer.insert(
            EventRecord(
                id: UUID(),
                sourceType: .clipboard,
                sourceApp: "Notes",
                capturedAt: DateComponents(calendar: calendar, year: 2026, month: 4, day: 9, hour: 10).date!,
                dayKey: "2026-04-09",
                text: "Historical gap event",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "historical-gap-event"
            )
        )

        let vaultURL = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let environment = AppEnvironment(
            databaseURL: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).sqlite"),
            vaultURL: vaultURL,
            databaseWriter: writer,
            summarizer: StaticSummarizer(response: makeValidStoryResponse(summaryLine: "Should stay manual-only")),
            notificationReader: RecordingNotificationReader(),
            dailyAutomationPlanner: DailyAutomationPlanner(
                backfillPlanner: BackfillPlanner(calendar: calendar)
            )
        )
        let appState = AppState(environment: environment)

        await appState.runAutomation(
            now: DateComponents(calendar: calendar, year: 2026, month: 4, day: 10, hour: 12).date!
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: vaultURL.appending(path: "2026-04-09.md").path))
        XCTAssertTrue(appState.pendingBackfillDays.isEmpty)
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
            summarizer: StaticSummarizer(response: makeValidStoryResponse(summaryLine: "Today kept despite notification failure")),
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

    func testRefreshSelectedDayWritesRefreshLogFile() async throws {
        let writer = try DatabaseWriter.inMemory()
        let calendar = Calendar(identifier: .gregorian)
        let dayKey = "2026-04-09"
        let eventID = UUID()
        try writer.insert(
            EventRecord(
                id: eventID,
                sourceType: .clipboard,
                sourceApp: "Notes",
                capturedAt: DateComponents(calendar: calendar, year: 2026, month: 4, day: 9, hour: 9).date!,
                dayKey: dayKey,
                text: "Log this refresh",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "refresh-log-file"
            )
        )

        let supportURL = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let environment = AppEnvironment(
            databaseURL: supportURL.appending(path: "events.sqlite"),
            vaultURL: supportURL.appending(path: "Vault", directoryHint: .isDirectory),
            databaseWriter: writer,
            summarizer: StaticSummarizer(response: makeValidStoryResponse(summaryLine: "Loggable refresh")),
            notificationReader: RecordingNotificationReader(),
            dailyAutomationPlanner: DailyAutomationPlanner(
                backfillPlanner: BackfillPlanner(calendar: calendar)
            )
        )
        let appState = AppState(environment: environment)
        appState.selectDate(dayKey)

        await appState.refreshSelectedDay(now: DateComponents(calendar: calendar, year: 2026, month: 4, day: 11).date!)

        let logDirectory = supportURL.appending(path: "RefreshLogs", directoryHint: .isDirectory)
        let logFiles = try FileManager.default.contentsOfDirectory(at: logDirectory, includingPropertiesForKeys: nil)
        XCTAssertEqual(logFiles.count, 1)

        let data = try Data(contentsOf: try XCTUnwrap(logFiles.first))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["dayKey"] as? String, dayKey)
        XCTAssertEqual(object["trigger"] as? String, "manual")
        XCTAssertEqual(object["mode"] as? String, "fullRecovery")
        XCTAssertEqual(object["finalStatus"] as? String, "completed")
        XCTAssertEqual((object["attempts"] as? [[String: Any]])?.count, 1)
    }

    func testRefreshSelectedDaySurfacesRefreshLogWriteFailure() async throws {
        let writer = try DatabaseWriter.inMemory()
        let calendar = Calendar(identifier: .gregorian)
        let dayKey = "2026-04-09"
        try writer.insert(
            EventRecord(
                id: UUID(),
                sourceType: .clipboard,
                sourceApp: "Notes",
                capturedAt: DateComponents(calendar: calendar, year: 2026, month: 4, day: 9, hour: 9).date!,
                dayKey: dayKey,
                text: "Log failure should stay visible but low-key",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "refresh-log-failure"
            )
        )

        let environment = AppEnvironment(
            databaseURL: URL(fileURLWithPath: "/dev/null/events.sqlite"),
            vaultURL: URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory),
            databaseWriter: writer,
            summarizer: StaticSummarizer(response: makeValidStoryResponse(summaryLine: "Refresh succeeds even if log writing does not")),
            notificationReader: RecordingNotificationReader(),
            dailyAutomationPlanner: DailyAutomationPlanner(
                backfillPlanner: BackfillPlanner(calendar: calendar)
            )
        )
        let appState = AppState(environment: environment)
        appState.selectDate(dayKey)

        await appState.refreshSelectedDay(now: DateComponents(calendar: calendar, year: 2026, month: 4, day: 11).date!)

        XCTAssertEqual(appState.refreshLogNotice(for: dayKey), "Refresh log unavailable")
        XCTAssertEqual(appState.refreshJob(for: dayKey)?.stage, .completed)
    }

    func testRefreshSelectedDayIncrementallyAppendsToModelStory() async throws {
        let writer = try DatabaseWriter.inMemory()
        let calendar = Calendar(identifier: .gregorian)
        let dayKey = "2026-04-09"
        let oldID = UUID()
        let newID = UUID()
        let oldEvent = EventRecord(
            id: oldID,
            sourceType: .clipboard,
            sourceApp: "Notes",
            capturedAt: DateComponents(calendar: calendar, year: 2026, month: 4, day: 9, hour: 9).date!,
            dayKey: dayKey,
            text: "Wrapped the first pass",
            auditText: nil,
            privacyAction: .keep,
            contentHash: "incremental-old"
        )
        let newEvent = EventRecord(
            id: newID,
            sourceType: .notification,
            sourceApp: "Mail",
            capturedAt: DateComponents(calendar: calendar, year: 2026, month: 4, day: 9, hour: 11).date!,
            dayKey: dayKey,
            text: "Customer approved the follow-up",
            auditText: nil,
            privacyAction: .keep,
            contentHash: "incremental-new"
        )
        try writer.insert(oldEvent)
        try writer.insert(newEvent)

        let vaultURL = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let environment = AppEnvironment(
            databaseURL: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).sqlite"),
            vaultURL: vaultURL,
            databaseWriter: writer,
            summarizer: nil,
            notificationReader: RecordingNotificationReader(),
            dailyAutomationPlanner: DailyAutomationPlanner(
                backfillPlanner: BackfillPlanner(calendar: calendar)
            )
        )
        let existingStory = DailyStory(
            dayKey: dayKey,
            generatedAt: Date(timeIntervalSince1970: 1_775_000_000),
            sections: [
                DailyStorySection(
                    id: "daily-journal",
                    title: "",
                    paragraphs: [
                        DailyStoryParagraph(
                            id: "daily-journal-0",
                            text: """
                            # You did a good job today

                            Keep the pace.

                            # Summary

                            - Wrapped the first pass

                            # Details

                            ## Existing Thread

                            Closed the first workflow.

                            # To-do

                            - [ ] Send recap
                            """,
                            sourceEventIDs: [oldID]
                        )
                    ]
                )
            ],
            provenance: StoryProvenance(
                generationMode: .model,
                engineKind: "codexCLI",
                engineLabel: "Codex (CLI)",
                model: nil,
                pipelineVersion: "diary-story-v1",
                curatedEventCount: 1
            )
        )
        try writeStoryDay(
            dayKey: dayKey,
            markdown: environment.composer.compose(dayKey: dayKey, events: [oldEvent], story: existingStory),
            story: existingStory,
            environment: environment
        )

        var config = SummarizerConfig.default
        config.defaultEngine = .codexCLI
        let appState = AppState(
            environment: environment,
            summarizerConfig: config,
            makeSummarizer: { engine, _, _ in
                guard engine == .codexCLI else { return nil }
                return StaticSummarizer(
                    response: """
                    {
                      "encouragementToReplace": { "text": "Keep the pace.", "sourceEventIDs": ["\(oldID.uuidString)", "\(newID.uuidString)"] },
                      "summaryBulletsToReplace": [
                        { "text": "- Wrapped the first pass", "sourceEventIDs": ["\(oldID.uuidString)"] },
                        { "text": "- Customer approved the follow-up", "sourceEventIDs": ["\(newID.uuidString)"] }
                      ],
                      "detailBlocksToAppend": [{ "text": "## Follow-up\\n\\nHandled the approval loop.", "sourceEventIDs": ["\(newID.uuidString)"] }],
                      "todoItemsToReplace": [
                        { "text": "- [ ] Send recap", "sourceEventIDs": ["\(oldID.uuidString)"] },
                        { "text": "- [ ] Queue the final handoff", "sourceEventIDs": ["\(newID.uuidString)"] }
                      ]
                    }
                    """
                )
            }
        )
        appState.engineStatuses[.codexCLI] = EngineRuntimeStatus(state: .green, detail: "Ready.", lastVerifiedAt: Date(), configurationSignature: "codex")
        appState.selectDate(dayKey)

        await appState.refreshSelectedDay(now: DateComponents(calendar: calendar, year: 2026, month: 4, day: 11).date!)

        let refreshedMarkdown = try String(contentsOf: vaultURL.appending(path: "\(dayKey).md"))
        XCTAssertTrue(refreshedMarkdown.contains("Keep the pace."))
        XCTAssertTrue(refreshedMarkdown.contains("- Wrapped the first pass"))
        XCTAssertTrue(refreshedMarkdown.contains("- Customer approved the follow-up"))
        XCTAssertTrue(refreshedMarkdown.contains("## Existing Thread"))
        XCTAssertTrue(refreshedMarkdown.contains("## Follow-up"))
        XCTAssertTrue(refreshedMarkdown.contains("- [ ] Send recap"))
        XCTAssertTrue(refreshedMarkdown.contains("- [ ] Queue the final handoff"))
        XCTAssertNil(appState.dayRefreshStatus.lastError)
    }

    func testGenerateDailyNoteUsesIncrementalModeWhenModelStoryExists() async throws {
        let writer = try DatabaseWriter.inMemory()
        let calendar = Calendar(identifier: .gregorian)
        let dayKey = "2026-04-09"
        let oldID = UUID()
        let newID = UUID()
        try writer.insert(
            EventRecord(
                id: oldID,
                sourceType: .clipboard,
                sourceApp: "Notes",
                capturedAt: DateComponents(calendar: calendar, year: 2026, month: 4, day: 9, hour: 9).date!,
                dayKey: dayKey,
                text: "Wrapped the first pass",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "generate-note-old"
            )
        )
        try writer.insert(
            EventRecord(
                id: newID,
                sourceType: .notification,
                sourceApp: "Mail",
                capturedAt: DateComponents(calendar: calendar, year: 2026, month: 4, day: 9, hour: 10).date!,
                dayKey: dayKey,
                text: "Queued the final handoff",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "generate-note-new"
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
                backfillPlanner: BackfillPlanner(calendar: calendar)
            )
        )
        let existingStory = DailyStory(
            dayKey: dayKey,
            generatedAt: Date(timeIntervalSince1970: 1_775_000_000),
            sections: [
                DailyStorySection(
                    id: "daily-journal",
                    title: "",
                    paragraphs: [
                        DailyStoryParagraph(
                            id: "daily-journal-0",
                            text: """
                            # You did a good job today

                            Keep the pace.

                            # Summary

                            - Wrapped the first pass

                            # Details

                            ## Existing Thread

                            Closed the first workflow.

                            # To-do

                            - [ ] Send recap
                            """,
                            sourceEventIDs: [oldID]
                        )
                    ]
                )
            ],
            provenance: StoryProvenance(
                generationMode: .model,
                engineKind: "codexCLI",
                engineLabel: "Codex (CLI)",
                model: nil,
                pipelineVersion: "diary-story-v1",
                curatedEventCount: 1
            )
        )
        try writeStoryDay(
            dayKey: dayKey,
            markdown: environment.composer.compose(dayKey: dayKey, events: [oldID, newID].compactMap { id in
                try? writer.fetchEvents(dayKey: dayKey).first(where: { $0.id == id })
            }, story: existingStory),
            story: existingStory,
            environment: environment
        )

        var config = SummarizerConfig.default
        config.defaultEngine = .codexCLI
        let appState = AppState(
            environment: environment,
            summarizerConfig: config,
            makeSummarizer: { engine, _, _ in
                guard engine == .codexCLI else { return nil }
                return StaticSummarizer(
                    response: """
                    {
                      "encouragementToReplace": { "text": "Keep the pace.", "sourceEventIDs": ["\(oldID.uuidString)", "\(newID.uuidString)"] },
                      "summaryBulletsToReplace": [
                        { "text": "- Wrapped the first pass", "sourceEventIDs": ["\(oldID.uuidString)"] },
                        { "text": "- Queued the final handoff", "sourceEventIDs": ["\(newID.uuidString)"] }
                      ],
                      "detailBlocksToAppend": [],
                      "todoItemsToReplace": [
                        { "text": "- [ ] Send recap", "sourceEventIDs": ["\(oldID.uuidString)"] },
                        { "text": "- [ ] Finish the handoff", "sourceEventIDs": ["\(newID.uuidString)"] }
                      ]
                    }
                    """
                )
            }
        )
        appState.engineStatuses[.codexCLI] = EngineRuntimeStatus(state: .green, detail: "Ready.", lastVerifiedAt: Date(), configurationSignature: "codex")

        await appState.generateDailyNote(for: dayKey)

        let refreshedMarkdown = try String(contentsOf: vaultURL.appending(path: "\(dayKey).md"))
        XCTAssertTrue(refreshedMarkdown.contains("- Wrapped the first pass"))
        XCTAssertTrue(refreshedMarkdown.contains("- Queued the final handoff"))
        XCTAssertTrue(refreshedMarkdown.contains("- [ ] Finish the handoff"))
        XCTAssertFalse(refreshedMarkdown.contains("Recovered day"))
        XCTAssertNil(appState.dayRefreshStatus.lastError)
    }

    func testRefreshSelectedDayIncrementalFailurePreservesExistingFiles() async throws {
        let writer = try DatabaseWriter.inMemory()
        let calendar = Calendar(identifier: .gregorian)
        let dayKey = "2026-04-09"
        let oldID = UUID()
        let newID = UUID()
        try writer.insert(
            EventRecord(
                id: oldID,
                sourceType: .clipboard,
                sourceApp: "Notes",
                capturedAt: DateComponents(calendar: calendar, year: 2026, month: 4, day: 9, hour: 9).date!,
                dayKey: dayKey,
                text: "Wrapped the first pass",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "preserve-old"
            )
        )
        try writer.insert(
            EventRecord(
                id: newID,
                sourceType: .notification,
                sourceApp: "Mail",
                capturedAt: DateComponents(calendar: calendar, year: 2026, month: 4, day: 9, hour: 11).date!,
                dayKey: dayKey,
                text: "Customer approved the follow-up",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "preserve-new"
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
                backfillPlanner: BackfillPlanner(calendar: calendar)
            )
        )
        let existingStory = DailyStory(
            dayKey: dayKey,
            generatedAt: Date(timeIntervalSince1970: 1_775_000_000),
            sections: [
                DailyStorySection(
                    id: "daily-journal",
                    title: "",
                    paragraphs: [
                        DailyStoryParagraph(
                            id: "daily-journal-0",
                            text: "# You did a good job today\n\nKeep the pace.\n\n# Summary\n\n- Wrapped the first pass\n\n# Details\n\n## Existing Thread\n\nClosed the first workflow.\n\n# To-do\n\n- [ ] Send recap",
                            sourceEventIDs: [oldID]
                        )
                    ]
                )
            ],
            provenance: StoryProvenance(
                generationMode: .model,
                engineKind: "codexCLI",
                engineLabel: "Codex (CLI)",
                model: nil,
                pipelineVersion: "diary-story-v1",
                curatedEventCount: 1
            )
        )
        let originalMarkdown = environment.composer.compose(dayKey: dayKey, events: try writer.fetchEvents(dayKey: dayKey), story: existingStory)
        try writeStoryDay(dayKey: dayKey, markdown: originalMarkdown, story: existingStory, environment: environment)

        var config = SummarizerConfig.default
        config.defaultEngine = .codexCLI
        let appState = AppState(
            environment: environment,
            summarizerConfig: config,
            makeSummarizer: { engine, _, _ in
                guard engine == .codexCLI else { return nil }
                return StaticSummarizer(response: "not json")
            }
        )
        appState.engineStatuses[.codexCLI] = EngineRuntimeStatus(state: .green, detail: "Ready.", lastVerifiedAt: Date(), configurationSignature: "codex")
        appState.selectDate(dayKey)

        await appState.refreshSelectedDay(now: DateComponents(calendar: calendar, year: 2026, month: 4, day: 11).date!)

        XCTAssertEqual(try String(contentsOf: vaultURL.appending(path: "\(dayKey).md")), originalMarkdown)
        XCTAssertEqual(try environment.loadDailyStory(dayKey: dayKey), existingStory)
        XCTAssertNotNil(appState.dayRefreshStatus.lastError)
    }

    func testRefreshSelectedDayFallsBackToParallelGreenEnginesAfterDefaultFailureAndCancelsLosers() async throws {
        let writer = try DatabaseWriter.inMemory()
        let calendar = Calendar(identifier: .gregorian)
        let dayKey = "2026-04-09"
        let eventID = UUID()
        try writer.insert(
            EventRecord(
                id: eventID,
                sourceType: .clipboard,
                sourceApp: "Notes",
                capturedAt: DateComponents(calendar: calendar, year: 2026, month: 4, day: 9, hour: 9).date!,
                dayKey: dayKey,
                text: "Recover this day",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "retry-day"
            )
        )

        let vaultURL = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let environment = AppEnvironment(
            databaseURL: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).sqlite"),
            vaultURL: vaultURL,
            databaseWriter: writer,
            summarizer: StaticSummarizer(response: "{}"),
            notificationReader: RecordingNotificationReader(),
            dailyAutomationPlanner: DailyAutomationPlanner(
                backfillPlanner: BackfillPlanner(calendar: calendar)
            )
        )
        let attemptRecorder = ParallelAttemptRecorder()

        var config = SummarizerConfig.default
        config.defaultEngine = .codexCLI
        let appState = AppState(
            environment: environment,
            summarizerConfig: config,
            makeSummarizer: { engine, _, _ in
                let attemptEngine = engine
                return HandlerSummarizer { dayKey, _, _ in
                    await attemptRecorder.recordStart(attemptEngine)
                    switch attemptEngine {
                    case .codexCLI:
                        return "not json"
                    case .geminiCLI:
                        await attemptRecorder.waitForGeminiAndClaudeToStart()
                        return """
                        {"sections":[{"id":"daily-journal","paragraphs":[{"text":"# Summary\\n- \(dayKey) recovered","sourceEventIDs":["\(eventID.uuidString)"]}]}]}
                        """
                    case .claudeCLI:
                        do {
                            try await Task.sleep(nanoseconds: 5_000_000_000)
                            return """
                            {"sections":[{"id":"daily-journal","paragraphs":[{"text":"# Summary\\n- slower fallback","sourceEventIDs":["\(eventID.uuidString)"]}]}]}
                            """
                        } catch {
                            await attemptRecorder.recordCancelled(attemptEngine)
                            throw error
                        }
                    default:
                        throw URLError(.cannotConnectToHost)
                    }
                }
            }
        )
        appState.engineStatuses[.codexCLI] = EngineRuntimeStatus(state: .green, detail: "Ready.", lastVerifiedAt: Date(), configurationSignature: "codex")
        appState.engineStatuses[.claudeCLI] = EngineRuntimeStatus(state: .green, detail: "Ready.", lastVerifiedAt: Date(), configurationSignature: "claude")
        appState.engineStatuses[.geminiCLI] = EngineRuntimeStatus(state: .green, detail: "Ready.", lastVerifiedAt: Date(), configurationSignature: "gemini")
        appState.selectDate(dayKey)

        await appState.refreshSelectedDay(now: DateComponents(calendar: calendar, year: 2026, month: 4, day: 11).date!)

        let snapshot = await attemptRecorder.snapshot()
        XCTAssertTrue(snapshot.started.contains(.geminiCLI))
        XCTAssertTrue(snapshot.started.contains(.claudeCLI))
        XCTAssertEqual(snapshot.cancelled, [.claudeCLI])
        XCTAssertTrue(try String(contentsOf: vaultURL.appending(path: "\(dayKey).md")).contains("2026-04-09 recovered"))
        XCTAssertNil(appState.dayRefreshStatus.lastError)
    }

    func testRefreshSelectedDayFailsInsteadOfFullRecoveryWhenExistingStoryCannotBeLoaded() async throws {
        let writer = try DatabaseWriter.inMemory()
        let calendar = Calendar(identifier: .gregorian)
        let dayKey = "2026-04-11"
        try writer.insert(
            EventRecord(
                id: UUID(),
                sourceType: .clipboard,
                sourceApp: "Notes",
                capturedAt: DateComponents(calendar: calendar, year: 2026, month: 4, day: 11, hour: 10).date!,
                dayKey: dayKey,
                text: "Existing day should not be regenerated if story loading fails",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "invalid-story-load"
            )
        )

        let vaultURL = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: vaultURL, withIntermediateDirectories: true)
        let markdownURL = vaultURL.appending(path: "\(dayKey).md")
        try "keep this markdown".write(to: markdownURL, atomically: true, encoding: .utf8)
        let storyURL = vaultURL.appending(path: "\(dayKey).story.json")
        try "{ invalid json".write(to: storyURL, atomically: true, encoding: .utf8)

        let environment = AppEnvironment(
            databaseURL: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).sqlite"),
            vaultURL: vaultURL,
            databaseWriter: writer,
            summarizer: StaticSummarizer(response: makeValidStoryResponse(summaryLine: "Should not be used")),
            notificationReader: RecordingNotificationReader(),
            dailyAutomationPlanner: DailyAutomationPlanner(
                backfillPlanner: BackfillPlanner(calendar: calendar)
            )
        )
        let appState = AppState(environment: environment)
        appState.selectDate(dayKey)

        await appState.refreshSelectedDay(now: DateComponents(calendar: calendar, year: 2026, month: 4, day: 11, hour: 12).date!)

        XCTAssertEqual(try String(contentsOf: markdownURL, encoding: .utf8), "keep this markdown")
        XCTAssertEqual(appState.refreshJob(for: dayKey)?.stage, .failed)
        XCTAssertTrue(appState.dayRefreshStatus.lastError?.contains("Failed to load existing story") == true)
    }

    func testRefreshSelectedDayFullRecoveryWithoutVerifiedEngineFailsAndPreservesExistingFiles() async throws {
        let writer = try DatabaseWriter.inMemory()
        let calendar = Calendar(identifier: .gregorian)
        let dayKey = "2026-04-11"
        let eventID = UUID()
        try writer.insert(
            EventRecord(
                id: eventID,
                sourceType: .clipboard,
                sourceApp: "Notes",
                capturedAt: DateComponents(calendar: calendar, year: 2026, month: 4, day: 11, hour: 9).date!,
                dayKey: dayKey,
                text: "Recover this day",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "full-recovery-no-engine"
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
                backfillPlanner: BackfillPlanner(calendar: calendar)
            )
        )
        let existingStory = DailyStory(
            dayKey: dayKey,
            generatedAt: Date(timeIntervalSince1970: 1_775_000_000),
            sections: [
                DailyStorySection(
                    id: "daily-journal",
                    title: "",
                    paragraphs: [
                        DailyStoryParagraph(
                            id: "daily-journal-0",
                            text: "# Summary\n\n- Existing fallback content",
                            sourceEventIDs: [eventID]
                        )
                    ]
                )
            ],
            provenance: StoryProvenance(
                generationMode: .fallback,
                engineKind: "codexCLI",
                engineLabel: "Codex (CLI)",
                model: nil,
                pipelineVersion: "diary-story-v1",
                curatedEventCount: 1
            )
        )
        let originalMarkdown = environment.composer.compose(dayKey: dayKey, events: try writer.fetchEvents(dayKey: dayKey), story: existingStory)
        try writeStoryDay(dayKey: dayKey, markdown: originalMarkdown, story: existingStory, environment: environment)

        var config = SummarizerConfig.default
        config.defaultEngine = .codexCLI
        let appState = AppState(
            environment: environment,
            summarizerConfig: config,
            makeSummarizer: { _, _, _ in nil }
        )
        appState.selectDate(dayKey)

        await appState.refreshSelectedDay(now: DateComponents(calendar: calendar, year: 2026, month: 4, day: 13).date!)

        XCTAssertEqual(try String(contentsOf: vaultURL.appending(path: "\(dayKey).md")), originalMarkdown)
        XCTAssertEqual(try environment.loadDailyStory(dayKey: dayKey), existingStory)
        XCTAssertEqual(appState.refreshJob(for: dayKey)?.stage, .failed)
        XCTAssertEqual(appState.dayRefreshStatus.lastError, "Configure and verify an engine to generate this journal")
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
            summarizer: StaticSummarizer(response: makeValidStoryResponse(summaryLine: "Visible stages")),
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

        let bothStarted = await waitUntilAsync(timeoutNanoseconds: 2_000_000_000) {
            let startCountNine = await gate.startCount(for: "2026-04-09")
            let startCountTen = await gate.startCount(for: "2026-04-10")
            return startCountNine > 0 && startCountTen > 0
        }
        XCTAssertTrue(bothStarted, "Expected both refresh jobs to start within the timeout")

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
            summarizer: StaticSummarizer(response: makeValidStoryResponse(summaryLine: "Terminal state complete")),
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
            summarizer: StaticSummarizer(response: makeValidStoryResponse(summaryLine: "Terminal summary complete")),
            notificationReader: RecordingNotificationReader(),
            dailyAutomationPlanner: DailyAutomationPlanner(
                backfillPlanner: BackfillPlanner(calendar: Calendar(identifier: .gregorian))
            )
        )
        var config = SummarizerConfig.default
        config.defaultEngine = .codexCLI
        let appState = AppState(environment: environment, summarizerConfig: config)
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
            "Completed · Codex (CLI) returned successfully"
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

    func testSummarizerStatusInfersFailureKindFromActiveEngineDetail() throws {
        let executableURL = try makeStubExecutable(named: "codex")
        var config = SummarizerConfig.default
        config.defaultEngine = .codexCLI
        config.codexCLIPath = executableURL.path

        let appState = AppState(
            bootstrapServices: false,
            summarizerConfig: config,
            userDefaults: engineDefaults,
            keychain: engineKeychain,
            keychainService: "MainWindowViewModelTests"
        )
        appState.engineStatuses[.codexCLI] = EngineRuntimeStatus(
            state: .yellow,
            detail: "Structured repair failed: repair output was not valid structured JSON",
            lastVerifiedAt: Date(timeIntervalSince1970: 1_775_100_000),
            configurationSignature: "codex|\(executableURL.path)"
        )

        XCTAssertEqual(appState.summarizerStatus.failureKind, .repairFailed)
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
        defer { try? FileManager.default.removeItem(at: executableDirectory) }
        let codexURL = executableDirectory.appending(path: "codex")
        let (processEnvironment, isolatedHomeURL) = try makeIsolatedCLIProcessEnvironment()
        defer { try? FileManager.default.removeItem(at: isolatedHomeURL) }
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
            processEnvironment: processEnvironment,
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

    func testGenerateStoryIgnoresLegacyPromptOverrideInPersistedConfig() async throws {
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
        var storedConfig = SummarizerConfig.default
        storedConfig.defaultEngine = .none
        storedConfig.save(
            to: engineDefaults,
            keychain: engineKeychain,
            keychainService: "MainWindowViewModelTests"
        )
        engineDefaults.set("Custom live global diary prompt override", forKey: "summarizerGlobalDiaryPromptOverride")
        let summarizer = RecordingPromptSummarizer(response: response)
        let environment = AppEnvironment(
            databaseURL: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).sqlite"),
            vaultURL: URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory),
            databaseWriter: writer,
            summarizer: summarizer,
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

        XCTAssertEqual(summarizer.capturedDayKey, dayKey)
        XCTAssertEqual(
            summarizer.capturedMarkdown,
            environment.composer.storyPrompt(dayKey: dayKey, events: events)
        )
        XCTAssertEqual(story.provenance?.generationMode, .model)
        XCTAssertEqual(story.provenance?.engineKind, DiaryEngine.none.rawValue)
        XCTAssertNil(engineDefaults.string(forKey: "summarizerGlobalDiaryPromptOverride"))
    }

    func testRefreshSelectedDayFullRecoveryIgnoresLegacyPromptOverrideAndNormalizesBeforePersisting() async throws {
        let writer = try DatabaseWriter.inMemory()
        let dayKey = "2026-04-12"
        let firstID = UUID()
        let secondID = UUID()
        try writer.insert(
            EventRecord(
                id: firstID,
                sourceType: .clipboard,
                sourceApp: "Figma",
                capturedAt: Date(timeIntervalSince1970: 1_775_700_000),
                dayKey: dayKey,
                text: "Adjusted the onboarding preview spacing",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "full-recovery-override-1"
            )
        )
        try writer.insert(
            EventRecord(
                id: secondID,
                sourceType: .clipboard,
                sourceApp: "Terminal",
                capturedAt: Date(timeIntervalSince1970: 1_775_700_300),
                dayKey: dayKey,
                text: "Ran the verification build",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "full-recovery-override-2"
            )
        )

        let vaultURL = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let summarizer = RecordingPromptSummarizer(
            response: """
            {
              "sections": [{
                "id": "daily-journal",
                "paragraphs": [{
                  "text": "# Details\\n\\n## Demo polish\\n\\nFigma tightened the preview.\\n\\n## Verification\\n\\nTerminal confirmed the build.",
                  "sourceEventIDs": ["\(firstID.uuidString)", "\(secondID.uuidString)"]
                }]
              }]
            }
            """
        )
        let environment = AppEnvironment(
            databaseURL: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).sqlite"),
            vaultURL: vaultURL,
            databaseWriter: writer,
            summarizer: summarizer,
            notificationReader: RecordingNotificationReader(),
            dailyAutomationPlanner: DailyAutomationPlanner(
                backfillPlanner: BackfillPlanner(calendar: Calendar(identifier: .gregorian))
            )
        )
        var storedConfig = SummarizerConfig.default
        storedConfig.defaultEngine = .none
        storedConfig.save(
            to: engineDefaults,
            keychain: engineKeychain,
            keychainService: "MainWindowViewModelTests"
        )
        engineDefaults.set("Custom full recovery override", forKey: "summarizerGlobalDiaryPromptOverride")
        let appState = AppState(
            environment: environment,
            userDefaults: engineDefaults,
            keychain: engineKeychain,
            keychainService: "MainWindowViewModelTests"
        )
        appState.selectDate(dayKey)

        await appState.refreshSelectedDay(now: Date(timeIntervalSince1970: 1_775_800_000))

        let events = try writer.fetchEvents(dayKey: dayKey)
        XCTAssertEqual(
            summarizer.capturedMarkdown,
            environment.composer.storyPrompt(dayKey: dayKey, events: events)
        )
        let persistedStory = try XCTUnwrap(environment.loadDailyStory(dayKey: dayKey))
        XCTAssertEqual(persistedStory.sections.first?.paragraphs.map(\.id), [
            "daily-journal-0-detail-0",
            "daily-journal-0-detail-1",
        ])
        let markdown = try String(contentsOf: vaultURL.appending(path: "\(dayKey).md"), encoding: .utf8)
        XCTAssertTrue(markdown.contains("## Demo polish"))
        XCTAssertTrue(markdown.contains("## Verification"))
        XCTAssertNil(engineDefaults.string(forKey: "summarizerGlobalDiaryPromptOverride"))
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
        let (processEnvironment, isolatedHomeURL) = try makeIsolatedCLIProcessEnvironment()
        defer { try? FileManager.default.removeItem(at: isolatedHomeURL) }

        let environment = try makeEngineEnvironment()
        let appState = AppState(
            environment: environment,
            summarizerConfig: config,
            processEnvironment: processEnvironment,
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
        let (processEnvironment, isolatedHomeURL) = try makeIsolatedCLIProcessEnvironment()
        defer { try? FileManager.default.removeItem(at: isolatedHomeURL) }

        let appState = AppState(
            bootstrapServices: false,
            processEnvironment: processEnvironment,
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
        let firstID = UUID()
        let secondID = UUID()
        let baseDate = DateComponents(calendar: Calendar(identifier: .gregorian), year: 2026, month: 4, day: 7, hour: 9).date!
        try writer.insert(
            EventRecord(
                id: firstID,
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
                id: secondID,
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
            summarizer: StaticSummarizer(
                response: """
                {
                  "sections": [{
                    "id": "daily-journal",
                    "paragraphs": [
                      { "text": "# Summary\\n\\n- Outlined launch story", "sourceEventIDs": ["\(firstID.uuidString)"] },
                      { "text": "## Calendar\\n\\nDesign review in 10 minutes", "sourceEventIDs": ["\(secondID.uuidString)"] }
                    ]
                  }]
                }
                """
            ),
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

    func testLoadDayPresentationLeavesLegacyDetailsUntouched() throws {
        let writer = try DatabaseWriter.inMemory()
        let dayKey = "2026-04-10"
        let figmaID = UUID()
        let notionID = UUID()
        let terminalID = UUID()
        let baseDate = DateComponents(calendar: Calendar(identifier: .gregorian), year: 2026, month: 4, day: 10, hour: 9).date!

        try writer.insert(
            EventRecord(
                id: figmaID,
                sourceType: .clipboard,
                sourceApp: "Figma",
                capturedAt: baseDate,
                dayKey: dayKey,
                text: "Adjusted onboarding preview spacing.",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "load-details-figma"
            )
        )
        try writer.insert(
            EventRecord(
                id: notionID,
                sourceType: .clipboard,
                sourceApp: "Notion",
                capturedAt: baseDate.addingTimeInterval(300),
                dayKey: dayKey,
                text: "Compressed the demo into a cleaner narrative.",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "load-details-notion"
            )
        )
        try writer.insert(
            EventRecord(
                id: terminalID,
                sourceType: .clipboard,
                sourceApp: "Terminal",
                capturedAt: baseDate.addingTimeInterval(600),
                dayKey: dayKey,
                text: "Ran the final verification build.",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "load-details-terminal"
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
        try writeStoryDay(
            dayKey: dayKey,
            markdown: """
            # 2026-04-10

            # Details

            ## Demo polish
            In Figma I refined the onboarding preview.

            ## Live narrative
            Notion helped keep the walkthrough honest.

            ## Recording readiness
            Terminal gave me the final verification pass.
            """,
            story: DailyStory(
                dayKey: dayKey,
                generatedAt: Date(timeIntervalSince1970: 1_775_000_500),
                sections: [
                    DailyStorySection(
                        id: "daily-journal",
                        title: "",
                        paragraphs: [
                            DailyStoryParagraph(
                                id: "daily-journal-2",
                                text: """
                                # Details

                                ## Demo polish
                                In Figma I refined the onboarding preview.

                                ## Live narrative
                                Notion helped keep the walkthrough honest.

                                ## Recording readiness
                                Terminal gave me the final verification pass.
                                """,
                                sourceEventIDs: [figmaID, notionID, terminalID]
                            )
                        ]
                    )
                ]
            ),
            environment: environment
        )

        let appState = AppState(environment: environment)
        appState.loadDayPresentation(for: dayKey)

        let paragraphs = try XCTUnwrap(appState.selectedStory?.sections.first?.paragraphs)
        XCTAssertEqual(paragraphs.map(\.id), ["daily-journal-2"])
        XCTAssertEqual(appState.selectedStoryParagraphID, "daily-journal-2")
        XCTAssertEqual(appState.selectedStorySourceEvents.map(\.id), [figmaID, notionID, terminalID])

        let persistedStory = try XCTUnwrap(environment.loadDailyStory(dayKey: dayKey))
        let persistedParagraphs = try XCTUnwrap(persistedStory.sections.first?.paragraphs)
        XCTAssertEqual(persistedParagraphs.map(\.id), ["daily-journal-2"])

        let persistedMarkdown = try String(contentsOf: vaultURL.appending(path: "\(dayKey).md"), encoding: .utf8)
        XCTAssertEqual(persistedMarkdown.components(separatedBy: "# Details").count - 1, 1)
        XCTAssertTrue(persistedMarkdown.contains("## Demo polish"))
        XCTAssertTrue(persistedMarkdown.contains("## Live narrative"))
        XCTAssertTrue(persistedMarkdown.contains("## Recording readiness"))
    }

    func testAppStateInitializationDoesNotMigrateLegacyStoriesAcrossVault() throws {
        let writer = try DatabaseWriter.inMemory()
        let newerDayKey = "2026-04-10"
        let olderDayKey = "2026-04-09"
        let newerFigmaID = UUID()
        let newerTerminalID = UUID()
        let olderNotionID = UUID()
        let olderXcodeID = UUID()
        let baseDate = DateComponents(calendar: Calendar(identifier: .gregorian), year: 2026, month: 4, day: 10, hour: 9).date!

        try writer.insert(
            EventRecord(
                id: newerFigmaID,
                sourceType: .clipboard,
                sourceApp: "Figma",
                capturedAt: baseDate,
                dayKey: newerDayKey,
                text: "Adjusted the preview spacing.",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "bulk-migrate-newer-figma"
            )
        )
        try writer.insert(
            EventRecord(
                id: newerTerminalID,
                sourceType: .clipboard,
                sourceApp: "Terminal",
                capturedAt: baseDate.addingTimeInterval(300),
                dayKey: newerDayKey,
                text: "Ran the verification build.",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "bulk-migrate-newer-terminal"
            )
        )
        try writer.insert(
            EventRecord(
                id: olderNotionID,
                sourceType: .clipboard,
                sourceApp: "Notion",
                capturedAt: baseDate.addingTimeInterval(-86_400),
                dayKey: olderDayKey,
                text: "Condensed the walkthrough script.",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "bulk-migrate-older-notion"
            )
        )
        try writer.insert(
            EventRecord(
                id: olderXcodeID,
                sourceType: .clipboard,
                sourceApp: "Xcode",
                capturedAt: baseDate.addingTimeInterval(-86_100),
                dayKey: olderDayKey,
                text: "Checked the macOS build warnings.",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "bulk-migrate-older-xcode"
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

        try writeStoryDay(
            dayKey: newerDayKey,
            markdown: """
            # 2026-04-10

            # Details

            ## Demo polish
            Figma tightened the preview.

            ## Verification
            Terminal confirmed the build.
            """,
            story: DailyStory(
                dayKey: newerDayKey,
                generatedAt: Date(timeIntervalSince1970: 1_775_000_500),
                sections: [
                    DailyStorySection(
                        id: "daily-journal",
                        title: "",
                        paragraphs: [
                            DailyStoryParagraph(
                                id: "daily-journal-2",
                                text: """
                                # Details

                                ## Demo polish
                                Figma tightened the preview.

                                ## Verification
                                Terminal confirmed the build.
                                """,
                                sourceEventIDs: [newerFigmaID, newerTerminalID]
                            )
                        ]
                    )
                ]
            ),
            environment: environment
        )
        try writeStoryDay(
            dayKey: olderDayKey,
            markdown: """
            # 2026-04-09

            # Details

            ## Narrative
            Notion reshaped the walkthrough.

            ## Build review
            Xcode exposed the warnings.
            """,
            story: DailyStory(
                dayKey: olderDayKey,
                generatedAt: Date(timeIntervalSince1970: 1_775_000_400),
                sections: [
                    DailyStorySection(
                        id: "daily-journal",
                        title: "",
                        paragraphs: [
                            DailyStoryParagraph(
                                id: "daily-journal-2",
                                text: """
                                # Details

                                ## Narrative
                                Notion reshaped the walkthrough.

                                ## Build review
                                Xcode exposed the warnings.
                                """,
                                sourceEventIDs: [olderNotionID, olderXcodeID]
                            )
                        ]
                    )
                ]
            ),
            environment: environment
        )

        let appState = AppState(environment: environment)

        let newerStory = try XCTUnwrap(environment.loadDailyStory(dayKey: newerDayKey))
        let olderStory = try XCTUnwrap(environment.loadDailyStory(dayKey: olderDayKey))
        XCTAssertEqual(newerStory.sections.first?.paragraphs.map(\.id), ["daily-journal-2"])
        XCTAssertEqual(olderStory.sections.first?.paragraphs.map(\.id), ["daily-journal-2"])

        let olderMarkdown = try String(contentsOf: vaultURL.appending(path: "\(olderDayKey).md"), encoding: .utf8)
        XCTAssertEqual(olderMarkdown.components(separatedBy: "# Details").count - 1, 1)
        XCTAssertTrue(olderMarkdown.contains("## Narrative"))
        XCTAssertTrue(olderMarkdown.contains("## Build review"))

        XCTAssertEqual(appState.availableDates, [newerDayKey, olderDayKey])
        XCTAssertEqual(appState.selectedDate, newerDayKey)
    }

    private func makeModelStory(dayKey: String, eventID: UUID) -> DailyStory {
        DailyStory(
            dayKey: dayKey,
            generatedAt: Date(timeIntervalSince1970: 1_775_000_100),
            sections: [
                DailyStorySection(
                    id: "daily-journal",
                    title: "",
                    paragraphs: [
                        DailyStoryParagraph(
                            id: "daily-journal-0",
                            text: "# 你今天做得很棒\n旧的成功内容",
                            sourceEventIDs: [eventID]
                        )
                    ]
                )
            ],
            provenance: StoryProvenance(
                generationMode: .model,
                engineKind: DiaryEngine.codexCLI.rawValue,
                engineLabel: DiaryEngine.codexCLI.displayName,
                model: nil,
                pipelineVersion: "diary-story-v1",
                curatedEventCount: 1
            )
        )
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
