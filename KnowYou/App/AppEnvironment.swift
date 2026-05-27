import Foundation

@MainActor
final class AppEnvironment {
    let databaseURL: URL
    var vaultURL: URL
    let databaseWriter: DatabaseWriter
    let todoStore: TodoStore
    let privacyFilter: PrivacyFilter
    let clipboardWatcher: ClipboardWatcher
    let notificationCollector: NotificationCollector
    let notificationReader: any NotificationDatabaseReading
    let composer: DailyMarkdownComposer
    var summarizer: SummaryGenerating?
    let dailyAutomationPlanner: DailyAutomationPlanner
    let updateService: any UpdateServing
    let directAppUpdater: any DirectAppUpdating
    let externalURLOpener: @MainActor @Sendable (URL) -> Void
    var refreshLogsDirectoryURL: URL {
        databaseURL.deletingLastPathComponent().appending(path: "RefreshLogs", directoryHint: .isDirectory)
    }
    var knowledgeSourcesDirectoryURL: URL {
        databaseURL.deletingLastPathComponent().appending(path: "KnowledgeSources", directoryHint: .isDirectory)
    }
    var externalSourcesDirectoryURL: URL {
        databaseURL.deletingLastPathComponent().appending(path: "ExternalSources", directoryHint: .isDirectory)
    }

    convenience init(
        databasePath: String,
        vaultURL: URL,
        summarizer: SummaryGenerating? = nil,
        updateService: any UpdateServing = AppEnvironment.makeDefaultUpdateService(),
        directAppUpdater: (any DirectAppUpdating)? = nil,
        externalURLOpener: @escaping @MainActor @Sendable (URL) -> Void = defaultExternalURLOpener,
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
            updateService: updateService,
            directAppUpdater: directAppUpdater,
            externalURLOpener: externalURLOpener,
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
        updateService: any UpdateServing = AppEnvironment.makeDefaultUpdateService(),
        directAppUpdater: (any DirectAppUpdating)? = nil,
        externalURLOpener: @escaping @MainActor @Sendable (URL) -> Void = defaultExternalURLOpener,
        onClipboardCapture: ((ClipboardCaptureSnapshot) -> Void)? = nil
    ) {
        let privacyFilter = PrivacyFilter()
        self.databaseURL = databaseURL
        self.vaultURL = vaultURL
        self.databaseWriter = databaseWriter
        self.todoStore = TodoStore(databaseWriter: databaseWriter)
        self.privacyFilter = privacyFilter
        self.notificationReader = notificationReader
        self.composer = DailyMarkdownComposer()
        self.summarizer = summarizer
        self.dailyAutomationPlanner = dailyAutomationPlanner
        self.updateService = updateService
        self.externalURLOpener = externalURLOpener
        self.directAppUpdater = directAppUpdater ?? ExternalLinkDirectAppUpdater(opener: externalURLOpener)
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

    func writeDailyStory(_ story: DailyStory) throws -> URL {
        try FileManager.default.createDirectory(at: vaultURL, withIntermediateDirectories: true)
        let fileURL = vaultURL.appending(path: "\(story.dayKey).story.json")
        let data = try JSONEncoder.pretty.encode(story)
        try data.write(to: fileURL, options: .atomic)
        return fileURL
    }

    func loadDailyStory(dayKey: String) throws -> DailyStory? {
        let fileURL = vaultURL.appending(path: "\(dayKey).story.json")
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(DailyStory.self, from: data)
    }

    func loadDailyNoteMarkdown(from fileURL: URL) throws -> String {
        try String(contentsOf: fileURL, encoding: .utf8)
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

    func writeRefreshLog(filename: String, data: Data) throws -> URL {
        try FileManager.default.createDirectory(at: refreshLogsDirectoryURL, withIntermediateDirectories: true)
        let fileURL = refreshLogsDirectoryURL.appending(path: filename)
        try data.write(to: fileURL, options: .atomic)
        return fileURL
    }

    func loadDailyStoryDayKeys() throws -> [String] {
        guard FileManager.default.fileExists(atPath: vaultURL.path) else {
            return []
        }

        let fileURLs = try FileManager.default.contentsOfDirectory(
            at: vaultURL,
            includingPropertiesForKeys: nil
        )

        return fileURLs
            .map(\.lastPathComponent)
            .filter { $0.hasSuffix(".story.json") }
            .map { $0.replacingOccurrences(of: ".story.json", with: "") }
            .sorted(by: >)
    }

    private static func makeDefaultUpdateService(
        bundle: Bundle = .main,
        processEnvironment: [String: String] = ProcessInfo.processInfo.environment
    ) -> any UpdateServing {
        let metadataURLString =
            processEnvironment["KYUpdateMetadataURL"]
            ?? (bundle.object(forInfoDictionaryKey: "KYUpdateMetadataURL") as? String)

        guard let metadataURLString else {
            return NoopUpdateService()
        }

        let trimmedMetadataURLString = metadataURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedMetadataURLString.isEmpty == false,
              let metadataURL = URL(string: trimmedMetadataURLString) else {
            return NoopUpdateService()
        }

        let currentVersion = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        let channel =
            processEnvironment["KYUpdateChannel"]
            ?? (bundle.object(forInfoDictionaryKey: "KYUpdateChannel") as? String)

        return UpdateService(
            session: .shared,
            resolver: UpdateChannelResolver(buildChannelOverride: channel),
            metadataURL: metadataURL,
            currentVersion: currentVersion
        )
    }
}

private extension JSONEncoder {
    static let pretty: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
}
