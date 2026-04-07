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
    private(set) var environment: AppEnvironment?

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
            self.statusMessage = "Capture services ready"
            refreshNotesIndex()
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
        guard let environment else {
            statusMessage = "Capture unavailable"
            return
        }

        do {
            let events = try environment.databaseWriter.fetchEvents(dayKey: dayKey)
            let baseMarkdown = environment.composer.compose(dayKey: dayKey, events: events, summary: nil)

            let summary = try await environment.summarizer?.summarize(dayKey: dayKey, markdown: baseMarkdown)
            let finalMarkdown = environment.composer.compose(dayKey: dayKey, events: events, summary: summary)
            let fileURL = try environment.writeDailyNote(dayKey: dayKey, markdown: finalMarkdown)

            noteIndex[dayKey] = fileURL
            availableDates = noteIndex.keys.sorted(by: >)
            if selectedDate == dayKey || selectedDate == nil {
                selectedDate = dayKey
                selectedMarkdownURL = fileURL
            }
            statusMessage = summary == nil ? "Summary pending for \(dayKey)" : "Summary ready for \(dayKey)"
        } catch {
            statusMessage = "Daily note failed: \(error.localizedDescription)"
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

    private static func makeVaultURL() throws -> URL {
        let applicationSupportURL = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let appDirectoryURL = applicationSupportURL.appending(path: "KnowYou", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: appDirectoryURL, withIntermediateDirectories: true)
        return appDirectoryURL.appending(path: "Vault", directoryHint: .isDirectory)
    }

    private static func makeSummarizer() -> SummaryGenerating? {
        let apiKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let apiKey, !apiKey.isEmpty else {
            return nil
        }

        return CloudSummarizer(apiKey: apiKey)
    }
}
