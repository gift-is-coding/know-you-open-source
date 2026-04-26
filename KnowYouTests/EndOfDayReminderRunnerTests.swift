import XCTest
@testable import KnowYou

private actor RunnerNotificationScheduler: NotificationScheduling {
    enum Call: Equatable {
        case schedule(ScheduledReviewNotification)
        case cancel([String])
    }

    private var status: ReminderAuthorizationStatus = .notDetermined
    private var calls: [Call] = []

    func setStatus(_ status: ReminderAuthorizationStatus) {
        self.status = status
    }

    func authorizationStatus() async -> ReminderAuthorizationStatus {
        status
    }

    func requestAuthorization() async -> ReminderAuthorizationStatus {
        status
    }

    func schedule(_ notification: ScheduledReviewNotification) async throws {
        calls.append(.schedule(notification))
    }

    func cancel(identifiers: [String]) async {
        calls.append(.cancel(identifiers))
    }

    func snapshot() async -> [Call] {
        calls
    }
}

final class EndOfDayReminderRunnerTests: XCTestCase {
    func testRunSchedulesReviewReminderWhenStoryAlreadyExists() async throws {
        let defaults = UserDefaults(suiteName: "EndOfDayReminderRunnerTests-\(UUID().uuidString)")!
        var config = EndOfDayReminderConfig.default
        config.isEnabled = true
        config.authorizationStatus = .authorized
        config.save(to: defaults)

        let scheduler = RunnerNotificationScheduler()
        await scheduler.setStatus(.authorized)
        let now = makeDate(hour: 20, minute: 30)
        let runner = EndOfDayReminderRunner(
            userDefaults: defaults,
            currentDate: { now },
            service: EndOfDayReminderService(scheduler: scheduler),
            loadStory: { dayKey in
                DailyStory(
                    dayKey: dayKey,
                    generatedAt: now.addingTimeInterval(-60),
                    sections: [],
                    provenance: nil
                )
            }
        )

        let result = try await runner.run()

        XCTAssertEqual(result, .sent(dayKey: "2026-04-21", action: .review))
        let calls = await scheduler.snapshot()
        XCTAssertEqual(
            calls,
            [
                .schedule(
                    ScheduledReviewNotification(
                        identifier: "know-you.end-of-day-review.2026-04-21",
                        fireDate: now.addingTimeInterval(1),
                        content: EndOfDayReminderContent(title: "KnowYou", body: "Come review today's diary."),
                        userInfo: [
                            EndOfDayReminderNotificationPayload.dayKey: "2026-04-21",
                            EndOfDayReminderNotificationPayload.action: EndOfDayReminderAction.review.rawValue,
                        ]
                    )
                )
            ]
        )
        let states = try XCTUnwrap(loadDayReviewStates(from: defaults))
        XCTAssertEqual(states["2026-04-21"]?.lastReminderDeliveredAt, now)
    }

    func testRunSchedulesGenerateReminderWhenStoryDoesNotExist() async throws {
        let defaults = UserDefaults(suiteName: "EndOfDayReminderRunnerTests-\(UUID().uuidString)")!
        var config = EndOfDayReminderConfig.default
        config.isEnabled = true
        config.authorizationStatus = .authorized
        config.save(to: defaults)

        let scheduler = RunnerNotificationScheduler()
        await scheduler.setStatus(.authorized)
        let now = makeDate(hour: 20, minute: 30)
        let runner = EndOfDayReminderRunner(
            userDefaults: defaults,
            currentDate: { now },
            service: EndOfDayReminderService(scheduler: scheduler),
            loadStory: { _ in nil }
        )

        let result = try await runner.run()

        XCTAssertEqual(result, .sent(dayKey: "2026-04-21", action: .generate))
        let calls = await scheduler.snapshot()
        XCTAssertEqual(
            calls,
            [
                .schedule(
                    ScheduledReviewNotification(
                        identifier: "know-you.end-of-day-review.2026-04-21",
                        fireDate: now.addingTimeInterval(1),
                        content: EndOfDayReminderContent(title: "KnowYou", body: "Come generate today's diary."),
                        userInfo: [
                            EndOfDayReminderNotificationPayload.dayKey: "2026-04-21",
                            EndOfDayReminderNotificationPayload.action: EndOfDayReminderAction.generate.rawValue,
                        ]
                    )
                )
            ]
        )
    }

    func testRunSkipsWhenReminderAlreadyDeliveredToday() async throws {
        let defaults = UserDefaults(suiteName: "EndOfDayReminderRunnerTests-\(UUID().uuidString)")!
        var config = EndOfDayReminderConfig.default
        config.isEnabled = true
        config.authorizationStatus = .authorized
        config.save(to: defaults)
        let states = [
            "2026-04-21": DayReviewState(
                dayKey: "2026-04-21",
                lastReminderScheduledAt: nil,
                lastReminderDeliveredAt: makeDate(hour: 20, minute: 25),
                lastRefreshTriggeredAt: nil
            )
        ]
        defaults.set(try JSONEncoder().encode(states), forKey: AppState.UserDefaultsKeys.dayReviewStates)

        let scheduler = RunnerNotificationScheduler()
        await scheduler.setStatus(.authorized)
        let now = makeDate(hour: 20, minute: 30)
        let runner = EndOfDayReminderRunner(
            userDefaults: defaults,
            currentDate: { now },
            service: EndOfDayReminderService(scheduler: scheduler),
            loadStory: { _ in nil }
        )

        let result = try await runner.run()

        XCTAssertEqual(result, .skippedAlreadyDelivered("2026-04-21"))
        let calls = await scheduler.snapshot()
        XCTAssertEqual(calls, [])
    }

    private func loadDayReviewStates(from defaults: UserDefaults) -> [String: DayReviewState]? {
        guard let data = defaults.data(forKey: AppState.UserDefaultsKeys.dayReviewStates) else {
            return nil
        }
        return try? JSONDecoder().decode([String: DayReviewState].self, from: data)
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
