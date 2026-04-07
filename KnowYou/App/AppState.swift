import Foundation
import Observation

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
    private(set) var environment: AppEnvironment?
    nonisolated(unsafe) private var automationTimer: Timer?

    init() {
        do {
            let databaseURL = try Self.makeDatabaseURL()
            let vaultURL = try Self.makeVaultURL()
            let environment = try AppEnvironment(
                databasePath: databaseURL.path,
                vaultURL: vaultURL,
                summarizer: Self.makeSummarizer()
            )
            environment.clipboardWatcher.start()
            self.environment = environment
            refreshNotesIndex()
            self.statusMessage = "Capture services ready"
            startAutomation()
        } catch {
            self.statusMessage = "Capture unavailable: \(error.localizedDescription)"
        }
    }

    func selectDate(_ date: String) {
        selectedDate = date
        selectedMarkdownURL = noteIndex[date]
    }

    func ingestNotifications(_ snapshots: [NotificationSnapshot]) {
        environment?.notificationCollector.ingest(snapshots)
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

            let summary = try await environment.summarizer?.summarize(dayKey: dayKey, markdown: baseMarkdown)
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
            }
            statusMessage = summary == nil ? "Summary pending for \(dayKey)" : "Summary ready for \(dayKey)"
        } catch {
            if let runID {
                try? environment.databaseWriter.finishRun(id: runID, status: "failed")
            }
            statusMessage = "Daily note failed: \(error.localizedDescription)"
        }
    }

    func runAutomation(now: Date = Date()) async {
        guard let environment else {
            statusMessage = "Capture unavailable"
            return
        }

        lastAutomationRunAt = now
        let notificationSince = Calendar(identifier: .gregorian).date(byAdding: .day, value: -2, to: now) ?? now
        let importedNotifications = (try? environment.notificationCollector.importDeliveredNotifications(since: notificationSince)) ?? 0
        lastImportedNotificationCount = importedNotifications
        refreshNotesIndex()

        let today = ISO8601DayKey.format(now)
        let latestCompletedDay = try? environment.databaseWriter.fetchLatestSuccessfulRunDay(runType: "daily-note")
        let pendingDays = environment.dailyAutomationPlanner.pendingDays(
            latestCompletedDay: latestCompletedDay,
            existingNoteDays: Set(noteIndex.keys),
            today: today
        )
        pendingBackfillDays = pendingDays

        for dayKey in pendingDays {
            await generateDailyNote(for: dayKey, recordsRun: true)
        }

        if pendingDays.isEmpty {
            statusMessage = importedNotifications == 0
                ? "Capture services ready"
                : "Imported \(importedNotifications) notifications"
            pendingBackfillDays = []
        }
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
        statusMessage = config.type == .none
            ? "Summarizer disabled"
            : "Summarizer set to \(config.type.displayName)"
    }

    private static func makeSummarizer() -> SummaryGenerating? {
        let saved = SummarizerConfig.load()
        if let s = saved.makeSummarizer() {
            return s
        }
        // Fallback: legacy OPENAI_API_KEY env var
        let apiKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let apiKey, !apiKey.isEmpty else { return nil }
        return CloudSummarizer(apiKey: apiKey)
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

    deinit {
        automationTimer?.invalidate()
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
}
