import XCTest
@testable import KnowYou

private struct ReminderStaticSummarizer: SummaryGenerating {
    let response: String

    func summarize(dayKey: String, markdown: String, context: SummaryInvocationContext) async throws -> String {
        response
    }
}

private actor AppStateReminderScheduler: NotificationScheduling {
    enum Call: Equatable {
        case schedule(String, Date)
        case cancel(String)
    }

    private var authorizationStatusValue: ReminderAuthorizationStatus
    private var requestAuthorizationValue: ReminderAuthorizationStatus
    private var calls: [Call] = []

    init(
        authorizationStatus: ReminderAuthorizationStatus,
        requestAuthorizationStatus: ReminderAuthorizationStatus? = nil
    ) {
        self.authorizationStatusValue = authorizationStatus
        self.requestAuthorizationValue = requestAuthorizationStatus ?? authorizationStatus
    }

    func authorizationStatus() async -> ReminderAuthorizationStatus {
        authorizationStatusValue
    }

    func setAuthorizationStatus(_ status: ReminderAuthorizationStatus) async {
        authorizationStatusValue = status
    }

    func requestAuthorization() async -> ReminderAuthorizationStatus {
        requestAuthorizationValue
    }

    func schedule(_ notification: ScheduledReviewNotification) async throws {
        calls.append(.schedule(notification.identifier, notification.fireDate))
    }

    func cancel(identifiers: [String]) async {
        identifiers.forEach { calls.append(.cancel($0)) }
    }

    func snapshot() async -> [Call] {
        calls
    }
}

private struct ReminderNotificationReader: NotificationDatabaseReading {
    func fetchDeliveredNotifications(since: Date) throws -> [NotificationSnapshot] { [] }
}

@MainActor
final class EndOfDayReminderAppStateTests: XCTestCase {
    func testLoadingTodaysPersistedStoryStillLoadsSelectedStory() async throws {
        let harness = try TestHarness(now: makeDate(hour: 21, minute: 0), schedulerStatus: .authorized)
        let dayKey = "2026-04-21"
        let story = makeStory(dayKey: dayKey, generatedAt: makeDate(hour: 20, minute: 10), sourceID: harness.event.id)

        _ = try harness.environment.writeDailyStory(story)
        _ = try harness.environment.writeDailyNote(dayKey: dayKey, markdown: "# 你今天做得很棒\n\nTest")
        try harness.environment.databaseWriter.insert(harness.event)

        harness.appState.selectDate(dayKey)
        await Task.yield()

        XCTAssertNotNil(harness.appState.selectedStory)
        XCTAssertEqual(harness.appState.selectedStory?.generatedAt, story.generatedAt)
    }

    func testRequestDailyReviewReminderAuthorizationEnablesReminderAndRegistersBackgroundAgent() async throws {
        let harness = try TestHarness(
            now: makeDate(hour: 14, minute: 0),
            schedulerStatus: .notDetermined,
            requestSchedulerStatus: .authorized
        )

        await harness.appState.requestDailyReviewReminderAuthorization()

        XCTAssertTrue(harness.appState.endOfDayReminderConfig.isEnabled)
        XCTAssertEqual(harness.appState.endOfDayReminderConfig.authorizationStatus, .authorized)
        XCTAssertEqual(harness.appState.statusMessage, "Daily review reminder enabled")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: harness.reminderLaunchAgentManager.defaultPlistURL().path)
        )
    }

    func testDisablingReminderRemovesBackgroundAgentAndCancelsTodayReminder() async throws {
        let harness = try TestHarness(
            now: makeDate(hour: 20, minute: 35),
            schedulerStatus: .authorized,
            summarizer: ReminderStaticSummarizer(response: makeStoryResponse(sourceID: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!))
        )
        let dayKey = "2026-04-21"
        harness.appState.setPersistedDayReviewState(
            DayReviewState(
                dayKey: dayKey,
                lastReminderScheduledAt: makeDate(hour: 20, minute: 30),
                lastReminderDeliveredAt: nil,
                lastRefreshTriggeredAt: nil
            )
        )
        await harness.appState.requestDailyReviewReminderAuthorization()
        XCTAssertTrue(FileManager.default.fileExists(atPath: harness.reminderLaunchAgentManager.defaultPlistURL().path))

        await harness.appState.setEndOfDayReminderEnabled(false)

        let calls = await harness.scheduler.snapshot()
        XCTAssertEqual(
            calls,
            [.cancel("know-you.end-of-day-review.2026-04-21")]
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: harness.reminderLaunchAgentManager.defaultPlistURL().path))
    }

    func testDeniedPermissionPreventsReminderScheduling() async throws {
        let harness = try TestHarness(
            now: makeDate(hour: 20, minute: 0),
            schedulerStatus: .denied,
            summarizer: ReminderStaticSummarizer(response: makeStoryResponse(sourceID: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!))
        )
        let dayKey = "2026-04-21"
        let event = EventRecord(
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            sourceType: .notification,
            sourceApp: "Calendar",
            capturedAt: makeDate(hour: 19, minute: 15),
            dayKey: dayKey,
            text: "Wrap up the day.",
            auditText: nil,
            privacyAction: .keep,
            contentHash: "end-of-day-review-denied"
        )
        try harness.environment.databaseWriter.insert(event)

        await harness.appState.refreshEndOfDayReminderAuthorizationStatus()
        await harness.appState.generateDailyNote(for: dayKey)
        await Task.yield()

        XCTAssertEqual(harness.appState.endOfDayReminderConfig.authorizationStatus, .denied)
        XCTAssertNil(harness.appState.dayReviewState(for: dayKey)?.lastReminderScheduledAt)
        let calls = await harness.scheduler.snapshot()
        XCTAssertEqual(calls, [])
    }

    func testSendTestReminderNowSchedulesImmediateDedicatedNotification() async throws {
        let harness = try TestHarness(
            now: makeDate(hour: 14, minute: 0),
            schedulerStatus: .authorized
        )

        await harness.appState.sendTestEndOfDayReminderNow()

        let calls = await harness.scheduler.snapshot()
        XCTAssertEqual(
            calls,
            [
                .cancel("know-you.end-of-day-review.test"),
                .schedule("know-you.end-of-day-review.test", makeDate(hour: 14, minute: 0).addingTimeInterval(1))
            ]
        )
        XCTAssertEqual(harness.appState.statusMessage, "Sent a test evening review reminder")
    }

    func testRefreshAuthorizationStatusDoesNotAutoEnableReminder() async throws {
        let harness = try TestHarness(
            now: makeDate(hour: 14, minute: 0),
            schedulerStatus: .denied,
            persistedReminderEnabled: false
        )

        XCTAssertFalse(harness.appState.endOfDayReminderConfig.isEnabled)

        await harness.scheduler.setAuthorizationStatus(.authorized)
        await harness.appState.refreshEndOfDayReminderAuthorizationStatus()

        XCTAssertEqual(harness.appState.endOfDayReminderConfig.authorizationStatus, .authorized)
        XCTAssertFalse(harness.appState.endOfDayReminderConfig.isEnabled)
    }

    func testGenerateReminderOpenStartsGeneratingTodaysDiary() async throws {
        let harness = try TestHarness(
            now: makeDate(hour: 21, minute: 0),
            schedulerStatus: .authorized,
            summarizer: ReminderStaticSummarizer(response: makeStoryResponse(sourceID: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!))
        )
        let dayKey = "2026-04-21"
        let event = EventRecord(
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            sourceType: .notification,
            sourceApp: "Calendar",
            capturedAt: makeDate(hour: 19, minute: 15),
            dayKey: dayKey,
            text: "Wrap up the day.",
            auditText: nil,
            privacyAction: .keep,
            contentHash: "end-of-day-review-generate-open"
        )
        try harness.environment.databaseWriter.insert(event)

        harness.appState.openDayFromEndOfDayReminder(dayKey, action: .generate)
        await Task.yield()
        await Task.yield()

        XCTAssertEqual(harness.appState.selectedDate, dayKey)
        XCTAssertNotNil(harness.appState.selectedStory)
        XCTAssertEqual(harness.appState.statusMessage, "Generating \(dayKey) from evening review reminder")
    }

    func testRelaunchDoesNotQueueDuplicateReminderForSameDay() async throws {
        let defaults = UserDefaults(suiteName: "EndOfDayReminderAppStateTests-\(UUID().uuidString)")!
        let dayKey = "2026-04-21"
        let now = makeDate(hour: 20, minute: 0)
        let storyVersion = makeDate(hour: 20, minute: 5)
        let scheduledAt = makeDate(hour: 20, minute: 30)

        let firstHarness = try TestHarness(
            now: now,
            schedulerStatus: .authorized,
            summarizer: ReminderStaticSummarizer(response: makeStoryResponse(sourceID: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!)),
            userDefaults: defaults
        )
        let event = EventRecord(
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            sourceType: .notification,
            sourceApp: "Calendar",
            capturedAt: makeDate(hour: 19, minute: 15),
            dayKey: dayKey,
            text: "Wrap up the day.",
            auditText: nil,
            privacyAction: .keep,
            contentHash: "end-of-day-review-relaunch"
        )
        try firstHarness.environment.databaseWriter.insert(event)
        _ = try firstHarness.environment.writeDailyStory(
            makeStory(dayKey: dayKey, generatedAt: storyVersion, sourceID: event.id)
        )
        let persistedStates = [
            dayKey: DayReviewState(
                dayKey: dayKey,
                lastReminderScheduledAt: scheduledAt,
                lastReminderDeliveredAt: nil,
                lastRefreshTriggeredAt: nil
            )
        ]
        defaults.set(try JSONEncoder().encode(persistedStates), forKey: "dayReviewStates")
        defaults.synchronize()

        let relaunchHarness = try TestHarness(
            now: now,
            schedulerStatus: .authorized,
            summarizer: nil,
            userDefaults: defaults,
            databaseURL: firstHarness.environment.databaseURL,
            vaultURL: firstHarness.environment.vaultURL
        )

        await relaunchHarness.appState.refreshEndOfDayReminderAuthorizationStatus()
        await Task.yield()

        let relaunchCalls = await relaunchHarness.scheduler.snapshot()
        XCTAssertEqual(relaunchCalls, [])
        XCTAssertEqual(relaunchHarness.appState.dayReviewState(for: dayKey)?.lastReminderScheduledAt, scheduledAt)
    }

    func testOpenDayFromEndOfDayReminderLoadsThatDiary() async throws {
        let harness = try TestHarness(now: makeDate(hour: 21, minute: 0), schedulerStatus: .authorized)
        let dayKey = "2026-04-21"
        let story = makeStory(dayKey: dayKey, generatedAt: makeDate(hour: 20, minute: 10), sourceID: harness.event.id)

        try harness.environment.databaseWriter.insert(harness.event)
        _ = try harness.environment.writeDailyStory(story)
        _ = try harness.environment.writeDailyNote(dayKey: dayKey, markdown: "# Story\n\nLoaded from reminder")

        harness.appState.openDayFromEndOfDayReminder(dayKey, action: .review)

        XCTAssertEqual(harness.appState.selectedDate, dayKey)
        XCTAssertEqual(harness.appState.selectedStory?.generatedAt, story.generatedAt)
        XCTAssertEqual(harness.appState.statusMessage, "Opened \(dayKey) from evening review reminder")
    }

    private func makeStory(dayKey: String, generatedAt: Date, sourceID: UUID) -> DailyStory {
        DailyStory(
            dayKey: dayKey,
            generatedAt: generatedAt,
            sections: [
                DailyStorySection(
                    id: "daily-journal",
                    title: "",
                    paragraphs: [
                        DailyStoryParagraph(id: "daily-journal-0", text: "Story", sourceEventIDs: [sourceID])
                    ]
                )
            ],
            provenance: StoryProvenance(
                generationMode: .model,
                engineKind: "test",
                engineLabel: "Test",
                model: nil,
                pipelineVersion: "test",
                curatedEventCount: 1
            )
        )
    }

    private func makeStoryResponse(sourceID: UUID) -> String {
        "{\"sections\":[{\"id\":\"daily-journal\",\"paragraphs\":[{\"text\":\"# Summary\\n- One calm day.\",\"sourceEventIDs\":[\"\(sourceID.uuidString)\"]}]}]}"
    }

    private func makeDate(hour: Int, minute: Int) -> Date {
        DateComponents(
            calendar: Calendar(identifier: .gregorian),
            timeZone: .autoupdatingCurrent,
            year: 2026,
            month: 4,
            day: 21,
            hour: hour,
            minute: minute
        ).date!
    }
}

@MainActor
private struct TestHarness {
    let environment: AppEnvironment
    let appState: AppState
    let scheduler: AppStateReminderScheduler
    let event: EventRecord
    let reminderLaunchAgentManager: LaunchAgentManager

    init(
        now: Date,
        schedulerStatus: ReminderAuthorizationStatus,
        requestSchedulerStatus: ReminderAuthorizationStatus? = nil,
        summarizer: SummaryGenerating? = nil,
        userDefaults: UserDefaults? = nil,
        databaseURL: URL? = nil,
        vaultURL: URL? = nil,
        persistedReminderEnabled: Bool = true
    ) throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let resolvedDatabaseURL = databaseURL ?? rootURL.appendingPathComponent("events.sqlite")
        let resolvedVaultURL = vaultURL ?? rootURL.appendingPathComponent("Vault", isDirectory: true)
        let databaseWriter = try DatabaseWriter(path: resolvedDatabaseURL.path)
        let environment = AppEnvironment(
            databaseURL: resolvedDatabaseURL,
            vaultURL: resolvedVaultURL,
            databaseWriter: databaseWriter,
            summarizer: summarizer,
            notificationReader: ReminderNotificationReader(),
            dailyAutomationPlanner: DailyAutomationPlanner(
                backfillPlanner: BackfillPlanner(calendar: Calendar(identifier: .gregorian))
            )
        )
        let scheduler = AppStateReminderScheduler(
            authorizationStatus: schedulerStatus,
            requestAuthorizationStatus: requestSchedulerStatus
        )
        let reminderLaunchAgentRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let reminderLaunchAgentManager = LaunchAgentManager(
            fileManager: .default,
            label: "dev.knowyou.end-of-day-reminder",
            homeDirectoryURL: reminderLaunchAgentRoot,
            commandRunner: { _ in },
            userIDProvider: { 501 }
        )
        let defaults = userDefaults ?? UserDefaults(suiteName: "EndOfDayReminderAppStateTests-\(UUID().uuidString)")!
        defaults.set(true, forKey: AppState.UserDefaultsKeys.hasCompletedOnboarding)
        defaults.set(OnboardingProgressState.complete.rawValue, forKey: AppState.UserDefaultsKeys.onboardingProgressState)
        defaults.set(OnboardingBootstrapState.complete.rawValue, forKey: AppState.UserDefaultsKeys.onboardingBootstrapState)
        defaults.removeObject(forKey: AppState.UserDefaultsKeys.onboardingBootstrapDayKeys)
        var reminderConfig = EndOfDayReminderConfig.default
        reminderConfig.isEnabled = persistedReminderEnabled
        reminderConfig.authorizationStatus = schedulerStatus
        reminderConfig.save(to: defaults)

        self.environment = environment
        self.scheduler = scheduler
        self.reminderLaunchAgentManager = reminderLaunchAgentManager
        self.event = EventRecord(
            id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            sourceType: .notification,
            sourceApp: "Mail",
            capturedAt: now.addingTimeInterval(-1800),
            dayKey: "2026-04-21",
            text: "A note",
            auditText: nil,
            privacyAction: .keep,
            contentHash: "loaded-story-event"
        )
        self.appState = AppState(
            environment: environment,
            bootstrapServices: false,
            currentDate: { now },
            userDefaults: defaults,
            launchAgentManager: LaunchAgentManager(
                fileManager: .default,
                homeDirectoryURL: reminderLaunchAgentRoot,
                commandRunner: { _ in },
                userIDProvider: { 501 }
            ),
            endOfDayReminderLaunchAgentManager: reminderLaunchAgentManager,
            endOfDayReminderService: EndOfDayReminderService(scheduler: scheduler)
        )
    }
}
