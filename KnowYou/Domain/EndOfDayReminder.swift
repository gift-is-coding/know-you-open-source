import Foundation
import UserNotifications

enum ReminderAuthorizationStatus: String, Codable, Equatable {
    case notDetermined
    case authorized
    case denied

    var settingsSummary: String {
        switch self {
        case .notDetermined:
            return "Not allowed yet"
        case .authorized:
            return "Allowed"
        case .denied:
            return "System blocked"
        }
    }
}

struct EndOfDayReminderConfig: Codable, Equatable {
    var isEnabled = true
    var authorizationStatus: ReminderAuthorizationStatus = .notDetermined
    var reminderHour = 20
    var reminderMinute = 30
    var retryDelayMinutes = 10

    static let `default` = EndOfDayReminderConfig()
    private static let storageKey = "endOfDayReminderConfig"

    func save(to defaults: UserDefaults = .standard) {
        let data = try? JSONEncoder().encode(self)
        defaults.set(data, forKey: Self.storageKey)
        defaults.synchronize()
    }

    static func load(from defaults: UserDefaults = .standard) -> EndOfDayReminderConfig {
        guard
            let data = defaults.data(forKey: storageKey),
            let decoded = try? JSONDecoder().decode(EndOfDayReminderConfig.self, from: data)
        else {
            return .default
        }
        return decoded
    }
}

struct DayReviewState: Codable, Equatable {
    var dayKey: String
    var lastReminderScheduledAt: Date?
    var lastReminderDeliveredAt: Date?
    var lastRefreshTriggeredAt: Date?

    var hasDeliveredReminder: Bool {
        lastReminderDeliveredAt != nil
    }
}

struct EndOfDayReminderContent: Equatable {
    let title: String
    let body: String
}

enum EndOfDayReminderAction: String, Codable, Equatable {
    case review
    case generate
}

struct EndOfDayReminderPlanContext: Equatable {
    let dayKey: String
    let now: Date
    let config: EndOfDayReminderConfig
    let hasStory: Bool
    let lastReminderScheduledAt: Date?
    let lastReminderDeliveredAt: Date?
    let lastRefreshTriggeredAt: Date?
}

enum EndOfDayReminderPlanDecision: Equatable {
    case noOp
    case cancelPending
    case scheduleNotification(at: Date)
    case triggerRefresh
}

enum EndOfDayReminderNotificationPresentation {
    static var foregroundOptions: UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
