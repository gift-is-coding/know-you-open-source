import Foundation

@MainActor
final class AppEnvironment {
    let databaseURL: URL
    let vaultURL: URL
    let databaseWriter: DatabaseWriter
    let privacyFilter: PrivacyFilter
    let clipboardWatcher: ClipboardWatcher
    let notificationCollector: NotificationCollector
    let composer: DailyMarkdownComposer
    let summarizer: SummaryGenerating?

    init(databasePath: String, vaultURL: URL, summarizer: SummaryGenerating? = nil) throws {
        let databaseURL = URL(fileURLWithPath: databasePath)
        let databaseWriter = try DatabaseWriter(path: databasePath)
        let privacyFilter = PrivacyFilter()

        self.databaseURL = databaseURL
        self.vaultURL = vaultURL
        self.databaseWriter = databaseWriter
        self.privacyFilter = privacyFilter
        self.composer = DailyMarkdownComposer()
        self.summarizer = summarizer
        self.clipboardWatcher = ClipboardWatcher(
            privacyFilter: privacyFilter,
            databaseWriter: databaseWriter
        )
        self.notificationCollector = NotificationCollector(
            privacyFilter: privacyFilter,
            databaseWriter: databaseWriter
        )
    }

    func writeDailyNote(dayKey: String, markdown: String) throws -> URL {
        try FileManager.default.createDirectory(at: vaultURL, withIntermediateDirectories: true)

        let fileURL = vaultURL.appending(path: "\(dayKey).md")
        try markdown.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    func loadDailyNotes() throws -> [String: URL] {
        guard FileManager.default.fileExists(atPath: vaultURL.path) else {
            return [:]
        }

        let fileURLs = try FileManager.default.contentsOfDirectory(
            at: vaultURL,
            includingPropertiesForKeys: nil
        )

        return Dictionary(
            uniqueKeysWithValues: fileURLs
                .filter { $0.pathExtension == "md" }
                .map { ($0.deletingPathExtension().lastPathComponent, $0) }
        )
    }
}
