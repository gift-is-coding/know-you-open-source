import Foundation
import Observation

struct ClipboardMonitorStatus {
    var isActive = false
    var lastCapturedAt: Date?
    var lastSourceApp: String?
    var lastPreview: String?
    var lastError: String?
}

struct NotificationImportStatus {
    var isDatabaseAvailable = false
    var databasePath: String?
    var availabilityMessage: String?
    var lastImportedAt: Date?
    var lastImportedCount = 0
    var lastError: String?
}

struct DayRefreshStatus {
    var lastRequestedDay: String?
    var lastRefreshedAt: Date?
    var detail: String?
    var lastError: String?
}

struct SummarizerRuntimeStatus {
    var mode: String = "None"
    var isConfigured = false
    var lastCompletedAt: Date?
    var lastError: String?
}

@MainActor
@Observable
final class AppState {
    var availableDates: [String] = []
    var selectedDate: String?
    var selectedMarkdownURL: URL?
    var noteIndex: [String: URL] = [:]
    var statusMessage: String?
    var lastAutomationRunAt: Date?
    var lastImportedNotificationCount = 0
    var pendingBackfillDays: [String] = []
    var clipboardStatus = ClipboardMonitorStatus()
    var notificationStatus = NotificationImportStatus()
    var dayRefreshStatus = DayRefreshStatus()
    var summarizerStatus = SummarizerRuntimeStatus()
    var selectedContentVersion = 0
    private(set) var environment: AppEnvironment?
    @ObservationIgnored private var automationTimer: Timer?

    init(environment: AppEnvironment? = nil, bootstrapServices: Bool = true) {
        if let environment {
            self.environment = environment
            clipboardStatus.isActive = true
            updateNotificationAccessStatus(using: environment.notificationReader)
            summarizerStatus = Self.makeSummarizerStatus(from: environment.summarizer)
            refreshNotesIndex()
            return
        }

        guard bootstrapServices else {
            return
        }

        do {
            let databaseURL = try AppState.makeDatabaseURL()
            let vaultURL = try AppState.makeVaultURL()
            let environment = try AppEnvironment(
                databasePath: databaseURL.path,
                vaultURL: vaultURL,
                summarizer: AppState.makeSummarizer(),
                onClipboardCapture: { [weak self] snapshot in
                    Task { @MainActor in
                        self?.recordClipboardCapture(snapshot)
                    }
                }
            )
            environment.clipboardWatcher.start()
            self.environment = environment
            clipboardStatus.isActive = true
            updateNotificationAccessStatus(using: environment.notificationReader)
            summarizerStatus = Self.makeSummarizerStatus(from: environment.summarizer)
            refreshNotesIndex()
            statusMessage = "Capture services ready"
            startAutomation()
        } catch {
            statusMessage = "Capture unavailable: \(error.localizedDescription)"
        }
    }

    func selectDate(_ date: String) {
        selectedDate = date
        selectedMarkdownURL = noteIndex[date]
    }

    func ingestNotifications(_ snapshots: [NotificationSnapshot]) {
        environment?.notificationCollector.ingest(snapshots)
    }

    func refreshSelectedDay(now: Date = Date()) async {
        guard let environment else {
            statusMessage = "Capture unavailable"
            return
        }

        let targetDay = selectedDate ?? ISO8601DayKey.format(now)
        if selectedDate == nil {
            selectDate(targetDay)
        }

        if targetDay == ISO8601DayKey.format(now) {
            await refreshToday(now: now, environment: environment)
        } else {
            await refreshHistoricalDay(targetDay)
        }
    }

    func generateDailyNote(for dayKey: String) async {
        await generateDailyNote(for: dayKey, recordsRun: true)
    }

    private func generateDailyNote(for dayKey: String, recordsRun: Bool) async {
        guard let environment else {
            statusMessage = "Capture unavailable"
            return
        }

        let runID = recordsRun ? try? environment.databaseWriter.startRun(runType: "daily-note", dayKey: dayKey) : nil
        do {
            let events = try environment.databaseWriter.fetchEvents(dayKey: dayKey)
            let baseMarkdown = environment.composer.compose(dayKey: dayKey, events: events, summary: nil)
            let summary: String?
            do {
                summary = try await environment.summarizer?.summarize(dayKey: dayKey, markdown: baseMarkdown)
                if environment.summarizer != nil {
                    summarizerStatus.lastCompletedAt = Date()
                    summarizerStatus.lastError = nil
                }
            } catch {
                summary = nil
                summarizerStatus.lastError = error.localizedDescription
            }
            let finalMarkdown = environment.composer.compose(dayKey: dayKey, events: events, summary: summary)
            let fileURL = try environment.writeDailyNote(dayKey: dayKey, markdown: finalMarkdown)
            if let runID {
                try environment.databaseWriter.finishRun(id: runID, status: "succeeded")
            }

            noteIndex[dayKey] = fileURL
            availableDates = noteIndex.keys.sorted(by: >)
            if selectedDate == dayKey || selectedDate == nil {
                selectedDate = dayKey
                selectedMarkdownURL = fileURL
                selectedContentVersion += 1
            }
            dayRefreshStatus.lastRequestedDay = dayKey
            dayRefreshStatus.lastRefreshedAt = Date()
            dayRefreshStatus.lastError = nil
            dayRefreshStatus.detail = events.isEmpty
                ? "Refreshed \(dayKey) with no captured events"
                : "Refreshed \(dayKey) with \(events.count) event\(events.count == 1 ? "" : "s")"
            if environment.summarizer == nil {
                statusMessage = "Refreshed \(dayKey) without summary"
            } else {
                statusMessage = summary == nil
                    ? "Refreshed \(dayKey); summary unavailable"
                    : "Refreshed \(dayKey) with summary"
            }
        } catch {
            if let runID {
                try? environment.databaseWriter.finishRun(id: runID, status: "failed")
            }
            dayRefreshStatus.lastRequestedDay = dayKey
            dayRefreshStatus.lastRefreshedAt = Date()
            dayRefreshStatus.lastError = error.localizedDescription
            statusMessage = "Daily note failed: \(error.localizedDescription)"
        }
    }

    func runAutomation(now: Date = Date()) async {
        guard let environment else {
            statusMessage = "Capture unavailable"
            return
        }

        lastAutomationRunAt = now
        refreshNotesIndex()
        let today = ISO8601DayKey.format(now)
        let latestCompletedDay = try? environment.databaseWriter.fetchLatestSuccessfulRunDay(runType: "daily-note")
        let pendingDays = environment.dailyAutomationPlanner.pendingDays(
            latestCompletedDay: latestCompletedDay,
            existingNoteDays: Set(noteIndex.keys),
            today: today
        )
        let notificationSince = Self.importStartDate(for: pendingDays, now: now)
        updateNotificationAccessStatus(using: environment.notificationReader)

        do {
            let importResult = try environment.notificationCollector.importDeliveredNotifications(since: notificationSince)
            lastImportedNotificationCount = importResult.importedCount
            notificationStatus.lastImportedAt = importResult.importedAt
            notificationStatus.lastImportedCount = importResult.importedCount
            if notificationStatus.isDatabaseAvailable {
                notificationStatus.lastError = nil
            }
        } catch {
            lastImportedNotificationCount = 0
            notificationStatus.lastImportedAt = Date()
            notificationStatus.lastImportedCount = 0
            notificationStatus.lastError = error.localizedDescription
        }

        refreshNotesIndex()
        pendingBackfillDays = pendingDays.filter { $0 != today }

        for dayKey in pendingDays {
            await generateDailyNote(for: dayKey, recordsRun: true)
        }

        if pendingDays.isEmpty {
            if let lastError = notificationStatus.lastError {
                statusMessage = "Refresh completed with notification issue: \(lastError)"
            } else {
                statusMessage = lastImportedNotificationCount == 0
                    ? "Capture services ready"
                    : "Imported \(lastImportedNotificationCount) notifications"
            }
            pendingBackfillDays = []
        }
    }

    func applyVaultURL(_ url: URL) {
        UserDefaults.standard.set(url.path, forKey: UserDefaultsKeys.vaultPath)
        guard let environment else { return }
        environment.vaultURL = url
        refreshNotesIndex()
        statusMessage = "Vault set to \(url.lastPathComponent)"
    }

    func applySummarizerConfig(_ config: SummarizerConfig) {
        config.save()
        environment?.summarizer = config.makeSummarizer()
        summarizerStatus = Self.makeSummarizerStatus(from: environment?.summarizer, configuredType: config.type.displayName)
        statusMessage = config.type == .none
            ? "Summarizer disabled"
            : "Summarizer set to \(config.type.displayName)"
    }

    func recheckNotificationAccess() {
        if let reader = environment?.notificationReader {
            updateNotificationAccessStatus(using: reader)
        } else {
            notificationStatus.isDatabaseAvailable = false
            notificationStatus.availabilityMessage = "Notification import unavailable because the app environment is not ready."
        }
        statusMessage = notificationStatus.isDatabaseAvailable
            ? "Notification import is available"
            : (notificationStatus.availabilityMessage ?? "Notification import unavailable. Grant Full Disk Access and try again.")
    }

    func refreshServiceStatuses() {
        if let reader = environment?.notificationReader {
            updateNotificationAccessStatus(using: reader)
        } else {
            notificationStatus.isDatabaseAvailable = false
            notificationStatus.availabilityMessage = "Notification import unavailable because the app environment is not ready."
        }
        summarizerStatus.mode = SummarizerConfig.load().type.displayName
        summarizerStatus.isConfigured = environment?.summarizer != nil
        if !notificationStatus.isDatabaseAvailable {
            notificationStatus.lastError = notificationStatus.availabilityMessage ?? "Notification Center database not accessible"
        } else if notificationStatus.lastError == "Notification Center database not accessible" {
            notificationStatus.lastError = nil
        }
    }

    var automationStatusText: String {
        let lastRunText: String
        if let lastAutomationRunAt {
            lastRunText = DateFormatter.localizedString(
                from: lastAutomationRunAt,
                dateStyle: .none,
                timeStyle: .short
            )
        } else {
            lastRunText = "Never"
        }

        let backfillText = pendingBackfillDays.isEmpty
            ? "No pending backfill"
            : "Pending: \(pendingBackfillDays.joined(separator: ", "))"

        return "Last run: \(lastRunText) · Notifications: \(lastImportedNotificationCount) · \(backfillText)"
    }

    var statusDetails: [String] {
        [
            clipboardStatusSummary,
            notificationStatusSummary,
            dayRefreshSummary,
            summarizerSummary,
        ].filter { !$0.isEmpty }
    }

    enum UserDefaultsKeys {
        static let vaultPath = "vaultPath"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
    }

    /// Returns the default vault URL without creating it on disk.
    static func defaultVaultURL() throws -> URL {
        let applicationSupportURL = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return applicationSupportURL
            .appending(path: "KnowYou", directoryHint: .isDirectory)
            .appending(path: "Vault", directoryHint: .isDirectory)
    }

    private static func makeVaultURL() throws -> URL {
        if let saved = UserDefaults.standard.string(forKey: UserDefaultsKeys.vaultPath), !saved.isEmpty {
            return URL(fileURLWithPath: saved, isDirectory: true)
        }
        return try defaultVaultURL()
    }

}

private extension AppState {
    func refreshToday(now: Date, environment: AppEnvironment) async {
        await runAutomation(now: now)
        selectedDate = ISO8601DayKey.format(now)
        selectedMarkdownURL = noteIndex[selectedDate ?? ""]
        selectedContentVersion += 1
        if dayRefreshStatus.lastError != nil {
            return
        }
        let imported = notificationStatus.lastImportedCount
        if let error = notificationStatus.lastError, !notificationStatus.isDatabaseAvailable {
            statusMessage = "Refreshed today without notifications: \(error)"
        } else if imported == 0 {
            statusMessage = "Refreshed today with no new notifications"
        } else {
            statusMessage = "Imported \(imported) notifications and refreshed today"
        }
    }

    func refreshHistoricalDay(_ dayKey: String) async {
        await generateDailyNote(for: dayKey, recordsRun: true)
        if dayRefreshStatus.lastError == nil {
            statusMessage = "Refreshed \(dayKey)"
        }
    }

    func recordClipboardCapture(_ snapshot: ClipboardCaptureSnapshot) {
        clipboardStatus.isActive = true
        clipboardStatus.lastCapturedAt = snapshot.capturedAt
        clipboardStatus.lastSourceApp = snapshot.sourceApp
        let previewSource = snapshot.persistedText ?? snapshot.auditText ?? ""
        clipboardStatus.lastPreview = String(previewSource.prefix(80))
        clipboardStatus.lastError = nil
        if selectedDate == ISO8601DayKey.format(snapshot.capturedAt) {
            statusMessage = "Clipboard captured; refresh today to update the note"
        }
    }

    private var clipboardStatusSummary: String {
        guard clipboardStatus.isActive else {
            return "Clipboard watcher inactive"
        }
        if let lastCapturedAt = clipboardStatus.lastCapturedAt {
            let time = DateFormatter.localizedString(from: lastCapturedAt, dateStyle: .none, timeStyle: .short)
            let source = clipboardStatus.lastSourceApp ?? "Unknown"
            return "Clipboard active · last capture \(time) from \(source)"
        }
        return "Clipboard active · waiting for the next capture"
    }

    private var notificationStatusSummary: String {
        let base = notificationStatus.isDatabaseAvailable
            ? "Notifications available"
            : "Notifications unavailable"
        let pathSuffix = notificationStatus.databasePath.map { " · \($0)" } ?? ""
        if let lastError = notificationStatus.lastError, !lastError.isEmpty, notificationStatus.isDatabaseAvailable {
            return "\(base)\(pathSuffix) · last error: \(lastError)"
        }
        if !notificationStatus.isDatabaseAvailable, let availabilityMessage = notificationStatus.availabilityMessage {
            return "\(base)\(pathSuffix) · \(availabilityMessage)"
        }
        if let lastImportedAt = notificationStatus.lastImportedAt {
            let time = DateFormatter.localizedString(from: lastImportedAt, dateStyle: .none, timeStyle: .short)
            return "\(base)\(pathSuffix) · last import \(time), \(notificationStatus.lastImportedCount) item(s)"
        }
        return "\(base)\(pathSuffix)"
    }

    private var dayRefreshSummary: String {
        if let lastError = dayRefreshStatus.lastError, let dayKey = dayRefreshStatus.lastRequestedDay {
            return "Refresh failed for \(dayKey): \(lastError)"
        }
        if let detail = dayRefreshStatus.detail {
            return detail
        }
        return ""
    }

    private var summarizerSummary: String {
        let base = "Summarizer: \(summarizerStatus.mode)"
        if let lastError = summarizerStatus.lastError {
            return "\(base) · last error: \(lastError)"
        }
        if let lastCompletedAt = summarizerStatus.lastCompletedAt {
            let time = DateFormatter.localizedString(from: lastCompletedAt, dateStyle: .none, timeStyle: .short)
            return "\(base) · last success \(time)"
        }
        return summarizerStatus.isConfigured ? "\(base) · ready" : "\(base) · disabled"
    }

    private static func makeSummarizer() -> SummaryGenerating? {
        let saved = SummarizerConfig.load()
        if let s = saved.makeSummarizer() {
            return s
        }
        let apiKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let apiKey, !apiKey.isEmpty else { return nil }
        return CloudSummarizer(apiKey: apiKey)
    }

    private static func makeSummarizerStatus(from summarizer: SummaryGenerating?, configuredType: String? = nil) -> SummarizerRuntimeStatus {
        SummarizerRuntimeStatus(
            mode: configuredType ?? {
                switch summarizer {
                case is CloudSummarizer: return "OpenAI API"
                case is CLISummarizer: return "CLI"
                default: return "None"
                }
            }(),
            isConfigured: summarizer != nil,
            lastCompletedAt: nil,
            lastError: nil
        )
    }

    private static func importStartDate(for pendingDays: [String], now: Date) -> Date {
        if let oldestPendingDay = pendingDays.first, let startDate = startOfDay(for: oldestPendingDay) {
            return startDate
        }
        return Calendar(identifier: .gregorian).date(byAdding: .day, value: -2, to: now) ?? now
    }

    private static func startOfDay(for dayKey: String) -> Date? {
        let parts = dayKey.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        let calendar = Calendar(identifier: .gregorian)
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    private static func makeDatabaseURL() throws -> URL {
        let applicationSupportURL = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let appDirectoryURL = applicationSupportURL.appending(path: "KnowYou", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: appDirectoryURL, withIntermediateDirectories: true)
        return appDirectoryURL.appending(path: "events.sqlite")
    }

    private func refreshNotesIndex() {
        guard let notes = try? environment?.loadDailyNotes() else {
            return
        }

        noteIndex = notes
        availableDates = notes.keys.sorted(by: >)
        if let selectedDate {
            selectedMarkdownURL = noteIndex[selectedDate]
        } else if let firstDate = availableDates.first {
            selectedDate = firstDate
            selectedMarkdownURL = noteIndex[firstDate]
        }
    }

    private func updateNotificationAccessStatus(using reader: NotificationDatabaseReader) {
        let accessStatus = reader.accessStatus()
        notificationStatus.isDatabaseAvailable = accessStatus.isAvailable
        notificationStatus.databasePath = accessStatus.databaseURL?.path
        notificationStatus.availabilityMessage = accessStatus.message
    }

    private func startAutomation() {
        automationTimer?.invalidate()
        automationTimer = Timer.scheduledTimer(withTimeInterval: 900, repeats: true) { [weak self] _ in
            guard let self else {
                return
            }

            Task { @MainActor in
                await self.runAutomation()
            }
        }

        Task { @MainActor in
            await runAutomation()
        }
    }
}
