import Foundation
import UserNotifications

struct ScheduledReviewNotification: Equatable {
    let identifier: String
    let fireDate: Date
    let content: EndOfDayReminderContent
    let userInfo: [String: String]
}

enum EndOfDayReminderNotificationPayload {
    static let dayKey = "dayKey"
    static let action = "action"
}

protocol NotificationScheduling: Sendable {
    func authorizationStatus() async -> ReminderAuthorizationStatus
    func requestAuthorization() async -> ReminderAuthorizationStatus
    func schedule(_ notification: ScheduledReviewNotification) async throws
    func cancel(identifiers: [String]) async
}

struct EndOfDayReminderService {
    let scheduler: any NotificationScheduling
    let calendar: Calendar

    init(
        scheduler: any NotificationScheduling = UserNotificationScheduler(),
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) {
        self.scheduler = scheduler
        self.calendar = calendar
    }

    func authorizationStatus() async -> ReminderAuthorizationStatus {
        await scheduler.authorizationStatus()
    }

    func requestAuthorization() async -> ReminderAuthorizationStatus {
        await scheduler.requestAuthorization()
    }

    func scheduleReminder(for dayKey: String, action: EndOfDayReminderAction, at date: Date) async throws {
        try await scheduler.schedule(
            ScheduledReviewNotification(
                identifier: requestIdentifier(for: dayKey),
                fireDate: date,
                content: notificationContent(for: action),
                userInfo: [
                    EndOfDayReminderNotificationPayload.dayKey: dayKey,
                    EndOfDayReminderNotificationPayload.action: action.rawValue,
                ]
            )
        )
    }

    func scheduleReminder(for dayKey: String, at date: Date) async throws {
        try await scheduleReminder(for: dayKey, action: .review, at: date)
    }

    func scheduleTestReminder(at date: Date, dayKey: String? = nil) async throws {
        var userInfo: [String: String] = [EndOfDayReminderNotificationPayload.action: EndOfDayReminderAction.review.rawValue]
        if let dayKey {
            userInfo[EndOfDayReminderNotificationPayload.dayKey] = dayKey
        }
        try await scheduler.schedule(
            ScheduledReviewNotification(
                identifier: testRequestIdentifier,
                fireDate: date,
                content: EndOfDayReminderContent(
                    title: "KnowYou",
                    body: "看看今天发生了什么吧"
                ),
                userInfo: userInfo
            )
        )
    }

    func cancelReminder(for dayKey: String) async {
        await scheduler.cancel(identifiers: [requestIdentifier(for: dayKey)])
    }

    func cancelTestReminder() async {
        await scheduler.cancel(identifiers: [testRequestIdentifier])
    }

    func requestIdentifier(for dayKey: String) -> String {
        "know-you.end-of-day-review.\(dayKey)"
    }

    var testRequestIdentifier: String {
        "know-you.end-of-day-review.test"
    }

    func notificationContent(for action: EndOfDayReminderAction) -> EndOfDayReminderContent {
        let body: String
        switch action {
        case .review:
            body = "Come review today's diary."
        case .generate:
            body = "Come generate today's diary."
        }

        return EndOfDayReminderContent(
            title: "KnowYou",
            body: body
        )
    }
}

struct UserNotificationScheduler: NotificationScheduling {
    private let calendar = Calendar(identifier: .gregorian)

    func authorizationStatus() async -> ReminderAuthorizationStatus {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                continuation.resume(returning: Self.mapAuthorizationStatus(settings.authorizationStatus))
            }
        }
    }

    func requestAuthorization() async -> ReminderAuthorizationStatus {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            return granted ? .authorized : .denied
        } catch {
            return .denied
        }
    }

    func schedule(_ notification: ScheduledReviewNotification) async throws {
        let components = calendarComponents(for: notification.fireDate)
        let content = UNMutableNotificationContent()
        content.title = notification.content.title
        content.body = notification.content.body
        content.sound = .default
        content.userInfo = notification.userInfo
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: notification.identifier, content: content, trigger: trigger)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            UNUserNotificationCenter.current().add(request) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    func cancel(identifiers: [String]) async {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    private func calendarComponents(for date: Date) -> DateComponents {
        calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
    }

    private static func mapAuthorizationStatus(_ status: UNAuthorizationStatus) -> ReminderAuthorizationStatus {
        switch status {
        case .authorized, .provisional:
            return .authorized
        case .denied:
            return .denied
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .notDetermined
        }
    }
}
