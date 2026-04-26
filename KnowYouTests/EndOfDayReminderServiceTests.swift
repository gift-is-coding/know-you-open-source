import XCTest
import UserNotifications
@testable import KnowYou

private actor RecordingNotificationScheduler: NotificationScheduling {
    enum Call: Equatable {
        case schedule(ScheduledReviewNotification)
        case cancel([String])
    }

    var status: ReminderAuthorizationStatus = .notDetermined
    var calls: [Call] = []

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

final class EndOfDayReminderServiceTests: XCTestCase {
    func testForegroundDeliveryUsesBannerListAndSound() {
        let options = EndOfDayReminderNotificationPresentation.foregroundOptions

        XCTAssertTrue(options.contains(.banner))
        XCTAssertTrue(options.contains(.list))
        XCTAssertTrue(options.contains(.sound))
    }

    func testReviewReminderUsesStablePerDayRequestIdentifierAndReviewCopy() async throws {
        let scheduler = RecordingNotificationScheduler()
        let service = EndOfDayReminderService(scheduler: scheduler)
        let fireDate = Date(timeIntervalSince1970: 1_777_000_000)

        try await service.scheduleReminder(for: "2026-04-21", action: .review, at: fireDate)

        let calls = await scheduler.snapshot()
        XCTAssertEqual(
            calls,
            [
                .schedule(
                    ScheduledReviewNotification(
                        identifier: "know-you.end-of-day-review.2026-04-21",
                        fireDate: fireDate,
                        content: EndOfDayReminderContent(
                            title: "KnowYou",
                            body: "Come review today's diary."
                        ),
                        userInfo: [
                            EndOfDayReminderNotificationPayload.dayKey: "2026-04-21",
                            EndOfDayReminderNotificationPayload.action: EndOfDayReminderAction.review.rawValue,
                        ]
                    )
                )
            ]
        )
    }

    func testGenerateReminderUsesGenerateCopyAndActionPayload() async throws {
        let scheduler = RecordingNotificationScheduler()
        let service = EndOfDayReminderService(scheduler: scheduler)
        let fireDate = Date(timeIntervalSince1970: 1_777_000_050)

        try await service.scheduleReminder(for: "2026-04-21", action: .generate, at: fireDate)

        let calls = await scheduler.snapshot()
        XCTAssertEqual(
            calls,
            [
                .schedule(
                    ScheduledReviewNotification(
                        identifier: "know-you.end-of-day-review.2026-04-21",
                        fireDate: fireDate,
                        content: EndOfDayReminderContent(
                            title: "KnowYou",
                            body: "Come generate today's diary."
                        ),
                        userInfo: [
                            EndOfDayReminderNotificationPayload.dayKey: "2026-04-21",
                            EndOfDayReminderNotificationPayload.action: EndOfDayReminderAction.generate.rawValue,
                        ]
                    )
                )
            ]
        )
    }

    func testCancelRemovesPendingAndDeliveredRequestForDay() async {
        let scheduler = RecordingNotificationScheduler()
        let service = EndOfDayReminderService(scheduler: scheduler)

        await service.cancelReminder(for: "2026-04-21")

        let calls = await scheduler.snapshot()
        XCTAssertEqual(calls, [.cancel(["know-you.end-of-day-review.2026-04-21"])])
    }

    func testAuthorizationStatusPassesThroughScheduler() async {
        let scheduler = RecordingNotificationScheduler()
        await scheduler.setStatus(.authorized)
        let service = EndOfDayReminderService(scheduler: scheduler)

        let status = await service.authorizationStatus()

        XCTAssertEqual(status, .authorized)
    }

    func testScheduleTestReminderUsesDedicatedIdentifierAndKnowYouCopy() async throws {
        let scheduler = RecordingNotificationScheduler()
        let service = EndOfDayReminderService(scheduler: scheduler)
        let fireDate = Date(timeIntervalSince1970: 1_777_000_123)

        try await service.scheduleTestReminder(at: fireDate)

        let calls = await scheduler.snapshot()
        XCTAssertEqual(
            calls,
            [
                .schedule(
                    ScheduledReviewNotification(
                        identifier: "know-you.end-of-day-review.test",
                        fireDate: fireDate,
                        content: EndOfDayReminderContent(
                            title: "KnowYou",
                            body: "看看今天发生了什么吧"
                        ),
                        userInfo: [EndOfDayReminderNotificationPayload.action: EndOfDayReminderAction.review.rawValue]
                    )
                )
            ]
        )
    }

    func testScheduleTestReminderCanCarryDayKeyForNavigation() async throws {
        let scheduler = RecordingNotificationScheduler()
        let service = EndOfDayReminderService(scheduler: scheduler)
        let fireDate = Date(timeIntervalSince1970: 1_777_000_321)

        try await service.scheduleTestReminder(at: fireDate, dayKey: "2026-04-26")

        let calls = await scheduler.snapshot()
        XCTAssertEqual(
            calls,
            [
                .schedule(
                    ScheduledReviewNotification(
                        identifier: "know-you.end-of-day-review.test",
                        fireDate: fireDate,
                        content: EndOfDayReminderContent(
                            title: "KnowYou",
                            body: "看看今天发生了什么吧"
                        ),
                        userInfo: [
                            EndOfDayReminderNotificationPayload.dayKey: "2026-04-26",
                            EndOfDayReminderNotificationPayload.action: EndOfDayReminderAction.review.rawValue,
                        ]
                    )
                )
            ]
        )
    }
}
