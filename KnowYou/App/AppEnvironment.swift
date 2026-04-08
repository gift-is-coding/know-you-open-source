import Foundation

@MainActor
final class AppEnvironment {
    let databaseURL: URL
    var vaultURL: URL
    let databaseWriter: DatabaseWriter
    let privacyFilter: PrivacyFilter
    let clipboardWatcher: ClipboardWatcher
    let notificationCollector: NotificationCollector
    let notificationReader: NotificationDatabaseReader
    let composer: DailyMarkdownComposer
    var summarizer: SummaryGenerating?
    let dailyAutomationPlanner: DailyAutomationPlanner

    convenience init(
        databasePath: String,
        vaultURL: URL,
        summarizer: SummaryGenerating? = nil,
        onClipboardCapture: ((ClipboardCaptureSnapshot) -> Void)? = nil
    ) throws {
        let databaseURL = URL(fileURLWithPath: databasePath)
        let databaseWriter = try DatabaseWriter(path: databasePath)
        let notificationReader = NotificationDatabaseReader()
        self.init(
            databaseURL: databaseURL,
            vaultURL: vaultURL,
            databaseWriter: databaseWriter,
            summarizer: summarizer,
            notificationReader: notificationReader,
            dailyAutomationPlanner: DailyAutomationPlanner(
                backfillPlanner: BackfillPlanner(calendar: Calendar(identifier: .gregorian))
            ),
            onClipboardCapture: onClipboardCapture
        )
    }

    init(
        databaseURL: URL,
        vaultURL: URL,
        databaseWriter: DatabaseWriter,
        summarizer: SummaryGenerating?,
        notificationReader: NotificationDatabaseReading,
        dailyAutomationPlanner: DailyAutomationPlanner,
        onClipboardCapture: ((ClipboardCaptureSnapshot) -> Void)? = nil
    ) {
        let privacyFilter = PrivacyFilter()
        let concreteNotificationReader = notificationReader as? NotificationDatabaseReader ?? NotificationDatabaseReader()

        self.databaseURL = databaseURL
        self.vaultURL = vaultURL
        self.databaseWriter = databaseWriter
        self.privacyFilter = privacyFilter
        self.notificationReader = concreteNotificationReader
        self.composer = DailyMarkdownComposer()
        self.summarizer = summarizer
        self.dailyAutomationPlanner = dailyAutomationPlanner
        self.clipboardWatcher = ClipboardWatcher(
            privacyFilter: privacyFilter,
            databaseWriter: databaseWriter,
            onCapture: onClipboardCapture
        )
        self.notificationCollector = NotificationCollector(
            privacyFilter: privacyFilter,
            databaseWriter: databaseWriter,
            databaseReader: notificationReader
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
            fileURLs
                .filter { $0.pathExtension == "md" }
                .map { ($0.deletingPathExtension().lastPathComponent, $0) },
            uniquingKeysWith: { _, new in new }
        )
    }
}
