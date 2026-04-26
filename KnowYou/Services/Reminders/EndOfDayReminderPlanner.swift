import Foundation

struct EndOfDayReminderPlanner {
    private let calendar: Calendar

    init(calendar: Calendar = Calendar(identifier: .gregorian)) {
        self.calendar = calendar
    }

    func plan(context: EndOfDayReminderPlanContext) -> EndOfDayReminderPlanDecision {
        guard context.config.isEnabled else {
            return .cancelPending
        }
        guard context.config.authorizationStatus == .authorized else {
            return .cancelPending
        }
        guard let startOfDay = startOfDay(for: context.dayKey) else {
            return .cancelPending
        }
        if context.lastReminderDeliveredAt != nil {
            return .cancelPending
        }

        let fixedReminderTime = calendar.date(
            bySettingHour: context.config.reminderHour,
            minute: context.config.reminderMinute,
            second: 0,
            of: startOfDay
        ) ?? startOfDay

        if let pendingAt = context.lastReminderScheduledAt,
           pendingAt > context.now {
            let expectedPendingAt: Date
            if let refreshTriggeredAt = context.lastRefreshTriggeredAt {
                let delayedTime = refreshTriggeredAt.addingTimeInterval(TimeInterval(context.config.retryDelayMinutes * 60))
                expectedPendingAt = max(delayedTime, context.now.addingTimeInterval(1))
            } else {
                expectedPendingAt = max(fixedReminderTime, context.now.addingTimeInterval(1))
            }
            if abs(expectedPendingAt.timeIntervalSince(pendingAt)) < 1 {
                return .noOp
            }
        }

        if context.hasStory {
            if let refreshTriggeredAt = context.lastRefreshTriggeredAt {
                let delayedTime = refreshTriggeredAt.addingTimeInterval(TimeInterval(context.config.retryDelayMinutes * 60))
                let scheduledAt = max(delayedTime, context.now.addingTimeInterval(1))
                return .scheduleNotification(at: scheduledAt)
            }

            if fixedReminderTime > context.now {
                return .scheduleNotification(at: fixedReminderTime)
            }

            return .scheduleNotification(at: context.now.addingTimeInterval(1))
        }

        if context.now < fixedReminderTime {
            return .noOp
        }

        if context.lastRefreshTriggeredAt != nil {
            if context.lastReminderScheduledAt != nil {
                return .noOp
            }
            return .cancelPending
        }

        return .triggerRefresh
    }

    private func startOfDay(for dayKey: String) -> Date? {
        let parts = dayKey.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var calendar = calendar
        calendar.timeZone = .autoupdatingCurrent
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}
