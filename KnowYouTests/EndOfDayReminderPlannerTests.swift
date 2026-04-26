import XCTest
@testable import KnowYou

final class EndOfDayReminderPlannerTests: XCTestCase {
    private let planner = EndOfDayReminderPlanner()

    func testSchedulesStoryAtFixedLocalReminderTime() {
        let context = EndOfDayReminderPlanContext(
            dayKey: "2026-04-21",
            now: makeDate(hour: 19, minute: 45),
            config: .defaultWithAuthorization,
            hasStory: true,
            lastReminderScheduledAt: nil,
            lastReminderDeliveredAt: nil,
            lastRefreshTriggeredAt: nil
        )

        XCTAssertEqual(
            planner.plan(context: context),
            .scheduleNotification(at: makeDate(hour: 20, minute: 30))
        )
    }

    func testSchedulesImmediatelyWhenStoryAppearsAfterReminderTime() {
        let context = EndOfDayReminderPlanContext(
            dayKey: "2026-04-21",
            now: makeDate(hour: 21, minute: 5),
            config: .defaultWithAuthorization,
            hasStory: true,
            lastReminderScheduledAt: nil,
            lastReminderDeliveredAt: nil,
            lastRefreshTriggeredAt: nil
        )

        XCTAssertEqual(
            planner.plan(context: context),
            .scheduleNotification(at: makeDate(hour: 21, minute: 5, second: 1))
        )
    }

    func testTriggersRefreshWhenStoryMissingAtReminderTime() {
        let context = EndOfDayReminderPlanContext(
            dayKey: "2026-04-21",
            now: makeDate(hour: 20, minute: 35),
            config: .defaultWithAuthorization,
            hasStory: false,
            lastReminderScheduledAt: nil,
            lastReminderDeliveredAt: nil,
            lastRefreshTriggeredAt: nil
        )

        XCTAssertEqual(planner.plan(context: context), .triggerRefresh)
    }

    func testSchedulesTenMinutesAfterRefreshWhenStoryBecomesReady() {
        let context = EndOfDayReminderPlanContext(
            dayKey: "2026-04-21",
            now: makeDate(hour: 20, minute: 36),
            config: .defaultWithAuthorization,
            hasStory: true,
            lastReminderScheduledAt: nil,
            lastReminderDeliveredAt: nil,
            lastRefreshTriggeredAt: makeDate(hour: 20, minute: 35)
        )

        XCTAssertEqual(
            planner.plan(context: context),
            .scheduleNotification(at: makeDate(hour: 20, minute: 45))
        )
    }

    func testSchedulesImmediatelyWhenRefreshDelayAlreadyPassed() {
        let context = EndOfDayReminderPlanContext(
            dayKey: "2026-04-21",
            now: makeDate(hour: 20, minute: 50),
            config: .defaultWithAuthorization,
            hasStory: true,
            lastReminderScheduledAt: nil,
            lastReminderDeliveredAt: nil,
            lastRefreshTriggeredAt: makeDate(hour: 20, minute: 35)
        )

        XCTAssertEqual(
            planner.plan(context: context),
            .scheduleNotification(at: makeDate(hour: 20, minute: 50, second: 1))
        )
    }

    func testKeepsExistingPendingReminder() {
        let context = EndOfDayReminderPlanContext(
            dayKey: "2026-04-21",
            now: makeDate(hour: 20, minute: 10),
            config: .defaultWithAuthorization,
            hasStory: true,
            lastReminderScheduledAt: makeDate(hour: 20, minute: 30),
            lastReminderDeliveredAt: nil,
            lastRefreshTriggeredAt: nil
        )

        XCTAssertEqual(planner.plan(context: context), .noOp)
    }

    func testCancelsAfterReminderHasBeenDelivered() {
        let context = EndOfDayReminderPlanContext(
            dayKey: "2026-04-21",
            now: makeDate(hour: 21, minute: 0),
            config: .defaultWithAuthorization,
            hasStory: true,
            lastReminderScheduledAt: makeDate(hour: 20, minute: 30),
            lastReminderDeliveredAt: makeDate(hour: 20, minute: 30),
            lastRefreshTriggeredAt: nil
        )

        XCTAssertEqual(planner.plan(context: context), .cancelPending)
    }

    private func makeDate(hour: Int, minute: Int, second: Int = 0) -> Date {
        DateComponents(
            calendar: Calendar(identifier: .gregorian),
            timeZone: .autoupdatingCurrent,
            year: 2026,
            month: 4,
            day: 21,
            hour: hour,
            minute: minute,
            second: second
        ).date!
    }
}

private extension EndOfDayReminderConfig {
    static var defaultWithAuthorization: EndOfDayReminderConfig {
        var config = EndOfDayReminderConfig.default
        config.authorizationStatus = .authorized
        return config
    }
}
