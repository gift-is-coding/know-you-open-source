import Foundation

enum EndOfDayReminderRunResult: Equatable {
    case skippedDisabled
    case skippedUnauthorized
    case skippedAlreadyDelivered(String)
    case sent(dayKey: String, action: EndOfDayReminderAction)
}

struct EndOfDayReminderRunner {
    let userDefaults: UserDefaults
    let currentDate: @Sendable () -> Date
    let service: EndOfDayReminderService
    let loadStory: (String) throws -> DailyStory?
    private let calendar: Calendar

    init(
        userDefaults: UserDefaults = .standard,
        currentDate: @escaping @Sendable () -> Date = Date.init,
        service: EndOfDayReminderService = EndOfDayReminderService(),
        calendar: Calendar = Calendar(identifier: .gregorian),
        loadStory: @escaping (String) throws -> DailyStory? = Self.loadPersistedStory
    ) {
        self.userDefaults = userDefaults
        self.currentDate = currentDate
        self.service = service
        self.calendar = calendar
        self.loadStory = loadStory
    }

    func run() async throws -> EndOfDayReminderRunResult {
        var config = EndOfDayReminderConfig.load(from: userDefaults)
        guard config.isEnabled else {
            return .skippedDisabled
        }

        let authorizationStatus = await service.authorizationStatus()
        if config.authorizationStatus != authorizationStatus {
            config.authorizationStatus = authorizationStatus
            config.save(to: userDefaults)
        }
        guard authorizationStatus == .authorized else {
            return .skippedUnauthorized
        }

        let now = currentDate()
        let dayKey = ISO8601DayKey.format(now)
        var states = loadDayReviewStates()
        var state = states[dayKey] ?? DayReviewState(dayKey: dayKey)
        if let deliveredAt = state.lastReminderDeliveredAt,
           calendar.isDate(deliveredAt, inSameDayAs: now) {
            return .skippedAlreadyDelivered(dayKey)
        }

        let action: EndOfDayReminderAction = (try loadStory(dayKey) != nil) ? .review : .generate
        let fireDate = now.addingTimeInterval(1)
        try await service.scheduleReminder(for: dayKey, action: action, at: fireDate)
        state.lastReminderScheduledAt = fireDate
        state.lastReminderDeliveredAt = now
        states[dayKey] = state
        persistDayReviewStates(states)
        return .sent(dayKey: dayKey, action: action)
    }

    private func loadDayReviewStates() -> [String: DayReviewState] {
        guard
            let data = userDefaults.data(forKey: AppState.UserDefaultsKeys.dayReviewStates),
            let decoded = try? JSONDecoder().decode([String: DayReviewState].self, from: data)
        else {
            return [:]
        }
        return decoded
    }

    private func persistDayReviewStates(_ states: [String: DayReviewState]) {
        let data = try? JSONEncoder().encode(states)
        userDefaults.set(data, forKey: AppState.UserDefaultsKeys.dayReviewStates)
        userDefaults.synchronize()
    }

    private static func loadPersistedStory(dayKey: String) throws -> DailyStory? {
        let applicationSupportURL = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let vaultURL = applicationSupportURL
            .appending(path: "KnowYou", directoryHint: .isDirectory)
            .appending(path: "Vault", directoryHint: .isDirectory)
        let fileURL = vaultURL.appending(path: "\(dayKey).story.json")
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(DailyStory.self, from: data)
    }
}
