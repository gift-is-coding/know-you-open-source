import Foundation
import Observation

enum ReaderFocusZone: Hashable {
    case dateList
    case storyParagraphs
}

enum ReaderMoveDirection {
    case up
    case down
    case left
    case right
}

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
    var selectedStory: DailyStory?
    var selectedStoryParagraphID: String?
    var selectedStorySourceEvents: [EventRecord] = []
    var selectedDayEvents: [EventRecord] = []
    var selectedMarkdownText: String?
    var selectedSourceNotesMarkdown: String?
    var readerFocus: ReaderFocusZone = .dateList
    private(set) var environment: AppEnvironment?
    @ObservationIgnored private var automationTimer: Timer?
    @ObservationIgnored private var paragraphSelectionByDay: [String: String] = [:]

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
            try? environment.databaseWriter.markOrphanRunsAsFailed()
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
        readerFocus = .dateList
        selectedDate = date
        selectedMarkdownURL = noteIndex[date]
        loadDayPresentation(for: date)
    }

    func selectStoryParagraph(_ paragraphID: String) {
        selectedStoryParagraphID = paragraphID
        if let selectedDate {
            paragraphSelectionByDay[selectedDate] = paragraphID
        }
        syncSelectedStorySources()
    }

    func selectAdjacentStoryParagraph(step: Int) {
        let paragraphs = selectedStoryParagraphs
        guard !paragraphs.isEmpty else { return }
        guard let selectedStoryParagraphID,
              let currentIndex = paragraphs.firstIndex(where: { $0.id == selectedStoryParagraphID })
        else {
            selectStoryParagraph(paragraphs[0].id)
            return
        }
        let nextIndex = min(max(currentIndex + step, 0), paragraphs.count - 1)
        selectStoryParagraph(paragraphs[nextIndex].id)
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
            clipboardServiceDetail,
            notificationServiceDetail,
        ].filter { !$0.isEmpty }
    }

    var selectedStoryParagraphs: [DailyStoryParagraph] {
        selectedStory?.sections.flatMap(\.paragraphs) ?? []
    }

    var selectedStoryParagraph: DailyStoryParagraph? {
        guard let selectedStoryParagraphID else { return nil }
        return selectedStoryParagraphs.first(where: { $0.id == selectedStoryParagraphID })
    }

    enum UserDefaultsKeys {
        static let vaultPath = "vaultPath"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
    }

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

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private func generateDailyNote(for dayKey: String, recordsRun: Bool) async {
        guard let environment else {
            statusMessage = "Capture unavailable"
            return
        }

        let runID = recordsRun ? try? environment.databaseWriter.startRun(runType: "daily-note", dayKey: dayKey) : nil
        do {
            let events = try environment.databaseWriter.fetchEvents(dayKey: dayKey)
            let story = await generateStory(dayKey: dayKey, events: events, environment: environment)
            let finalMarkdown = environment.composer.compose(dayKey: dayKey, events: events, story: story)
            let fileURL = try environment.writeDailyNote(dayKey: dayKey, markdown: finalMarkdown)
                _ = try environment.writeDailyStory(story)
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

            updateSelectedPresentation(dayKey: dayKey, story: story, events: events)
            dayRefreshStatus.lastRequestedDay = dayKey
            dayRefreshStatus.lastRefreshedAt = Date()
            dayRefreshStatus.lastError = nil
            dayRefreshStatus.detail = events.isEmpty
                ? "Refreshed \(dayKey) with no captured events"
                : "Refreshed \(dayKey) into \(story.sections.flatMap(\.paragraphs).count) story segment(s)"

            if environment.summarizer == nil {
                statusMessage = "Refreshed \(dayKey) with local story fallback"
            } else if summarizerStatus.lastError != nil {
                statusMessage = "Refreshed \(dayKey); story fell back to local summary"
            } else {
                statusMessage = "Refreshed \(dayKey) with story view"
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
}

extension AppState {
    func focusDateList() {
        readerFocus = .dateList
    }

    func focusStoryParagraphs() {
        guard selectedDate != nil else { return }
        readerFocus = .storyParagraphs
        restoreParagraphSelectionForCurrentDay()
    }

    func handleReaderMove(_ direction: ReaderMoveDirection) {
        switch readerFocus {
        case .dateList:
            switch direction {
            case .up:
                selectAdjacentDate(step: -1)
            case .down:
                selectAdjacentDate(step: 1)
            case .right:
                focusStoryParagraphs()
            case .left:
                break
            }
        case .storyParagraphs:
            switch direction {
            case .up:
                selectAdjacentStoryParagraph(step: -1)
            case .down:
                selectAdjacentStoryParagraph(step: 1)
            case .left:
                focusDateList()
            case .right:
                break
            }
        }
    }

    func handleReaderExit() {
        focusDateList()
    }

    func refreshToday(now: Date, environment: AppEnvironment) async {
        await runAutomation(now: now)
        let today = ISO8601DayKey.format(now)
        selectedDate = today
        selectedMarkdownURL = noteIndex[today]
        loadDayPresentation(for: today)
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

    func generateStory(dayKey: String, events: [EventRecord], environment: AppEnvironment) async -> DailyStory {
        let fallbackStory = environment.composer.fallbackStory(dayKey: dayKey, events: events)
        guard let summarizer = environment.summarizer else {
            return fallbackStory
        }

        do {
            let raw = try await summarizer.summarize(
                dayKey: dayKey,
                markdown: environment.composer.storyPrompt(dayKey: dayKey, events: events)
            )
            if let parsed = environment.composer.parseStory(dayKey: dayKey, raw: raw),
               parsed.sections.flatMap(\.paragraphs).isEmpty == false {
                summarizerStatus.lastCompletedAt = Date()
                summarizerStatus.lastError = nil
                return parsed
            }
            summarizerStatus.lastError = "Story output was not valid structured JSON"
        } catch {
            summarizerStatus.lastError = error.localizedDescription
        }

        return fallbackStory
    }

    func loadDayPresentation(for dayKey: String) {
        guard let environment else {
            selectedStory = nil
            selectedStoryParagraphID = nil
            selectedStorySourceEvents = []
            selectedDayEvents = []
            selectedMarkdownText = nil
            selectedSourceNotesMarkdown = nil
            return
        }

        let events = (try? environment.databaseWriter.fetchEvents(dayKey: dayKey)) ?? []
        let story = (try? environment.loadDailyStory(dayKey: dayKey)) ?? environment.composer.fallbackStory(dayKey: dayKey, events: events)
        updateSelectedPresentation(dayKey: dayKey, story: story, events: events)
    }

    func updateSelectedPresentation(dayKey: String, story: DailyStory, events: [EventRecord]) {
        selectedDate = dayKey
        selectedStory = story
        selectedDayEvents = events
        selectedMarkdownURL = preferredMarkdownURL(for: dayKey)
        let markdown = loadSelectedMarkdownText()
        selectedMarkdownText = markdown
        selectedSourceNotesMarkdown =
            markdown.flatMap(extractSourceNotesMarkdown(from:))
            ?? generatedSourceNotesMarkdown(from: events)
        let paragraphs = story.sections.flatMap(\.paragraphs)
        if let rememberedID = paragraphSelectionByDay[dayKey],
           paragraphs.contains(where: { $0.id == rememberedID }) {
            selectedStoryParagraphID = rememberedID
        } else if let currentID = selectedStoryParagraphID,
                  paragraphs.contains(where: { $0.id == currentID }) {
            selectedStoryParagraphID = currentID
        } else {
            selectedStoryParagraphID = paragraphs.first?.id
        }
        if let selectedStoryParagraphID {
            paragraphSelectionByDay[dayKey] = selectedStoryParagraphID
        }
        syncSelectedStorySources()
    }

    func syncSelectedStorySources() {
        guard let paragraph = selectedStoryParagraph else {
            selectedStorySourceEvents = []
            return
        }
        let sourceSet = Set(paragraph.sourceEventIDs)
        selectedStorySourceEvents = selectedDayEvents.filter { sourceSet.contains($0.id) }
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

    var clipboardStatusSummary: String {
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

    var notificationStatusSummary: String {
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

    var dayRefreshSummary: String {
        if let lastError = dayRefreshStatus.lastError, let dayKey = dayRefreshStatus.lastRequestedDay {
            return "Refresh failed for \(dayKey): \(lastError)"
        }
        if let detail = dayRefreshStatus.detail {
            return detail
        }
        return ""
    }

    var summarizerSummary: String {
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

    var clipboardServiceDetail: String {
        "Clipboard capture uses the native macOS pasteboard, not Maccy."
    }

    var notificationServiceDetail: String {
        let base = "Notification import reads the local Notification Center database."
        if notificationStatus.isDatabaseAvailable {
            return "\(base) Some banners are never persisted by macOS, so an empty import can be machine-dependent."
        }
        return "\(base) If the database is missing or unreadable, notifications will not appear until macOS exposes a readable store."
    }

    static func makeSummarizer() -> SummaryGenerating? {
        let saved = SummarizerConfig.load()
        if let s = saved.makeSummarizer() {
            return s
        }
        let apiKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let apiKey, !apiKey.isEmpty else { return nil }
        return CloudSummarizer(apiKey: apiKey)
    }

    static func makeSummarizerStatus(from summarizer: SummaryGenerating?, configuredType: String? = nil) -> SummarizerRuntimeStatus {
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

    static func importStartDate(for pendingDays: [String], now: Date) -> Date {
        if let oldestPendingDay = pendingDays.first, let startDate = startOfDay(for: oldestPendingDay) {
            return startDate
        }
        return Calendar(identifier: .gregorian).date(byAdding: .day, value: -2, to: now) ?? now
    }

    static func startOfDay(for dayKey: String) -> Date? {
        let parts = dayKey.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        let calendar = Calendar(identifier: .gregorian)
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    static func makeDatabaseURL() throws -> URL {
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

    func refreshNotesIndex() {
        guard let notes = try? environment?.loadDailyNotes() else {
            return
        }

        noteIndex = notes
        availableDates = notes.keys.sorted(by: >)
        if let selectedDate {
            selectedMarkdownURL = noteIndex[selectedDate]
            loadDayPresentation(for: selectedDate)
        } else if let firstDate = availableDates.first {
            selectedDate = firstDate
            selectedMarkdownURL = noteIndex[firstDate]
            loadDayPresentation(for: firstDate)
        }
    }

    func updateNotificationAccessStatus(using reader: NotificationDatabaseReader) {
        let accessStatus = reader.accessStatus()
        notificationStatus.isDatabaseAvailable = accessStatus.isAvailable
        notificationStatus.databasePath = accessStatus.databaseURL?.path
        notificationStatus.availabilityMessage = accessStatus.message
    }

    func startAutomation() {
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

    private func selectAdjacentDate(step: Int) {
        guard !availableDates.isEmpty else { return }
        guard let selectedDate,
              let currentIndex = availableDates.firstIndex(of: selectedDate)
        else {
            selectDate(availableDates[0])
            return
        }
        let nextIndex = min(max(currentIndex + step, 0), availableDates.count - 1)
        guard nextIndex != currentIndex else { return }
        selectDate(availableDates[nextIndex])
    }

    private func restoreParagraphSelectionForCurrentDay() {
        guard let selectedDate else { return }
        let paragraphs = selectedStoryParagraphs
        guard !paragraphs.isEmpty else { return }

        if let rememberedID = paragraphSelectionByDay[selectedDate],
           paragraphs.contains(where: { $0.id == rememberedID }) {
            selectedStoryParagraphID = rememberedID
        } else {
            selectedStoryParagraphID = paragraphs[0].id
            paragraphSelectionByDay[selectedDate] = paragraphs[0].id
        }
        syncSelectedStorySources()
    }

    private func preferredMarkdownURL(for dayKey: String) -> URL? {
        if let selectedMarkdownURL,
           selectedMarkdownURL.deletingPathExtension().lastPathComponent == dayKey {
            return selectedMarkdownURL
        }
        if let indexedURL = noteIndex[dayKey] {
            return indexedURL
        }
        guard let environment else {
            return nil
        }
        let fileURL = environment.vaultURL.appending(path: "\(dayKey).md")
        return FileManager.default.fileExists(atPath: fileURL.path) ? fileURL : nil
    }

    private func loadSelectedMarkdownText() -> String? {
        guard let environment, let selectedMarkdownURL else {
            return nil
        }
        return try? environment.loadDailyNoteMarkdown(from: selectedMarkdownURL)
    }

    private func extractSourceNotesMarkdown(from markdown: String) -> String? {
        environment?.composer.extractSourceNotesSection(from: markdown)
            ?? DailyMarkdownComposer().extractSourceNotesSection(from: markdown)
    }

    private func generatedSourceNotesMarkdown(from events: [EventRecord]) -> String {
        environment?.composer.sourceNotesMarkdown(for: events) ?? DailyMarkdownComposer().sourceNotesMarkdown(for: events)
    }
}
