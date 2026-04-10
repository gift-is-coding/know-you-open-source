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

struct EngineRuntimeStatus: Equatable {
    var state: EngineIndicatorState = .gray
    var detail: String = "Not configured."
    var lastVerifiedAt: Date?
    var configurationSignature: String = ""
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
    var engineStatuses: [DiaryEngine: EngineRuntimeStatus]
    var defaultEngine: DiaryEngine
    var isRetestingEngines = false
    var retestingEngines: Set<DiaryEngine> = []
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
    @ObservationIgnored private let userDefaults: UserDefaults
    @ObservationIgnored private let keychain: KeychainStoring
    @ObservationIgnored private let keychainService: String
    @ObservationIgnored private let processEnvironment: [String: String]
    @ObservationIgnored private let probeEngine: @Sendable (DiaryEngine, SummarizerConfig, [String: String]) async -> EngineProbeResult
    @ObservationIgnored private var summarizerConfig: SummarizerConfig

    var summarizerStatus: SummarizerRuntimeStatus {
        get {
            let status = engineStatuses[defaultEngine] ?? Self.makeBaselineStatus(
                for: defaultEngine,
                config: summarizerConfig,
                environment: processEnvironment
            )
            let isActiveEngineConfigured = defaultEngine != .none && status.state != .gray
            return SummarizerRuntimeStatus(
                mode: defaultEngine.displayName,
                isConfigured: isActiveEngineConfigured || environment?.summarizer != nil,
                lastCompletedAt: status.lastVerifiedAt,
                lastError: status.state == .green || (defaultEngine == .none && environment?.summarizer == nil)
                    ? nil
                    : status.detail
            )
        }
        set {
            engineStatuses[defaultEngine] = EngineRuntimeStatus(
                state: Self.state(for: newValue),
                detail: newValue.lastError
                    ?? (newValue.isConfigured ? "Ready." : "Not configured."),
                lastVerifiedAt: newValue.lastCompletedAt,
                configurationSignature: Self.configurationSignature(
                    for: defaultEngine,
                    config: summarizerConfig,
                    environment: processEnvironment
                )
            )
        }
    }

    init(
        environment: AppEnvironment? = nil,
        bootstrapServices: Bool = true,
        summarizerConfig: SummarizerConfig? = nil,
        probeEngine: @escaping @Sendable (DiaryEngine, SummarizerConfig, [String: String]) async -> EngineProbeResult = { engine, config, environment in
            await EngineProbe().probe(engine: engine, config: config, environment: environment)
        },
        processEnvironment: [String: String] = ProcessInfo.processInfo.environment,
        userDefaults: UserDefaults = .standard,
        keychain: KeychainStoring = KeychainHelper.shared,
        keychainService: String = KeychainHelper.service
    ) {
        let explicitSummarizerConfig = summarizerConfig
        self.userDefaults = userDefaults
        self.keychain = keychain
        self.keychainService = keychainService
        self.processEnvironment = processEnvironment
        self.probeEngine = probeEngine
        self.summarizerConfig = summarizerConfig ?? SummarizerConfig.load(
            from: userDefaults,
            keychain: keychain,
            keychainService: keychainService
        )
        let loadedDefaultEngine = self.summarizerConfig.defaultEngine
        if explicitSummarizerConfig == nil, let injectedSummarizer = environment?.summarizer {
            self.summarizerConfig = Self.reconciledConfig(
                from: self.summarizerConfig,
                with: injectedSummarizer
            )
        }
        let initialEngineStatuses = Self.makeInitialEngineStatuses(
            config: self.summarizerConfig,
            environment: processEnvironment
        )
        self.engineStatuses = initialEngineStatuses
        self.defaultEngine = Self.initialDefaultEngine(
            explicitConfigProvided: explicitSummarizerConfig != nil,
            config: &self.summarizerConfig,
            environment: environment?.summarizer,
            engineStatuses: initialEngineStatuses
        )
        if explicitSummarizerConfig == nil,
           environment?.summarizer == nil,
           self.summarizerConfig.defaultEngine != loadedDefaultEngine {
            self.summarizerConfig.save(
                to: userDefaults,
                keychain: keychain,
                keychainService: keychainService
            )
        }

        if let environment {
            self.environment = environment
            if explicitSummarizerConfig != nil {
                environment.summarizer = self.summarizerConfig.makeSummarizer(
                    for: defaultEngine,
                    environment: processEnvironment
                )
            }
            clipboardStatus.isActive = true
            updateNotificationAccessStatus(using: environment.notificationReader)
            refreshEngineStatuses()
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
                summarizer: self.summarizerConfig.makeSummarizer(
                    for: defaultEngine,
                    environment: processEnvironment
                ),
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
            refreshEngineStatuses()
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
        let requestedEngine = config.defaultEngine
        applyEngineConfig(config)

        if requestedEngine == .none {
            selectDefaultEngine(.none)
            return
        }

        guard requestedEngine != defaultEngine else {
            return
        }

        guard engineStatuses[requestedEngine]?.state == .green else {
            return
        }

        selectDefaultEngine(requestedEngine)
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
        refreshEngineStatuses()
        if !notificationStatus.isDatabaseAvailable {
            notificationStatus.lastError = notificationStatus.availabilityMessage ?? "Notification Center database not accessible"
        } else if notificationStatus.lastError == "Notification Center database not accessible" {
            notificationStatus.lastError = nil
        }
    }

    func refreshEngineStatuses() {
        var refreshed: [DiaryEngine: EngineRuntimeStatus] = [:]
        for engine in DiaryEngine.allCases {
            let existing = engineStatuses[engine]
            let baseline = Self.makeBaselineStatus(
                for: engine,
                config: summarizerConfig,
                environment: processEnvironment
            )

            let existingSignature = existing?.configurationSignature.isEmpty == false
                ? existing?.configurationSignature
                : baseline.configurationSignature

            if existingSignature == baseline.configurationSignature,
               let existing,
               existing.state != .gray || baseline.state == .gray {
                refreshed[engine] = EngineRuntimeStatus(
                    state: existing.state,
                    detail: existing.detail,
                    lastVerifiedAt: existing.lastVerifiedAt,
                    configurationSignature: baseline.configurationSignature
                )
            } else {
                refreshed[engine] = EngineRuntimeStatus(
                    state: baseline.state,
                    detail: baseline.detail,
                    lastVerifiedAt: existing?.lastVerifiedAt,
                    configurationSignature: baseline.configurationSignature
                )
            }
        }
        engineStatuses = refreshed
    }

    func retestAllEngines() async {
        let engines = DiaryEngine.allCases.filter { $0 != .none }
        let configSnapshot = summarizerConfig
        let signatures = Dictionary(
            uniqueKeysWithValues: engines.map { engine in
                (
                    engine,
                    Self.configurationSignature(
                        for: engine,
                        config: configSnapshot,
                        environment: processEnvironment
                    )
                )
            }
        )

        retestingEngines.formUnion(engines)
        isRetestingEngines = true

        await withTaskGroup(of: (DiaryEngine, EngineProbeResult, String).self) { group in
            for engine in engines {
                let signature = signatures[engine] ?? ""
                group.addTask { [probeEngine, processEnvironment] in
                    let result = await probeEngine(engine, configSnapshot, processEnvironment)
                    return (engine, result, signature)
                }
            }

            for await (engine, result, signature) in group {
                if Self.configurationSignature(
                    for: engine,
                    config: summarizerConfig,
                    environment: processEnvironment
                ) == signature {
                    engineStatuses[engine] = EngineRuntimeStatus(
                        state: result.state,
                        detail: result.detail,
                        lastVerifiedAt: result.verifiedAt ?? engineStatuses[engine]?.lastVerifiedAt,
                        configurationSignature: signature
                    )
                }

                retestingEngines.remove(engine)
                isRetestingEngines = !retestingEngines.isEmpty
            }
        }
    }

    func retestEngine(_ engine: DiaryEngine) async {
        retestingEngines.insert(engine)
        isRetestingEngines = true
        let configSnapshot = summarizerConfig
        let configurationSignature = Self.configurationSignature(
            for: engine,
            config: configSnapshot,
            environment: processEnvironment
        )
        let result = await probeEngine(engine, configSnapshot, processEnvironment)
        guard Self.configurationSignature(
            for: engine,
            config: summarizerConfig,
            environment: processEnvironment
        ) == configurationSignature else {
            retestingEngines.remove(engine)
            isRetestingEngines = !retestingEngines.isEmpty
            return
        }
        engineStatuses[engine] = EngineRuntimeStatus(
            state: result.state,
            detail: result.detail,
            lastVerifiedAt: result.verifiedAt ?? engineStatuses[engine]?.lastVerifiedAt,
            configurationSignature: configurationSignature
        )
        retestingEngines.remove(engine)
        isRetestingEngines = !retestingEngines.isEmpty
    }

    func selectDefaultEngine(_ engine: DiaryEngine) {
        guard engine == .none || engineStatuses[engine]?.state == .green else {
            statusMessage = "\(engine.displayName) is not verified yet"
            return
        }

        defaultEngine = engine
        summarizerConfig.defaultEngine = engine
        persistSummarizerConfig()
        statusMessage = engine == .none
            ? "Summarizer disabled"
            : "Default engine set to \(engine.displayName)"
    }

    func applyEngineConfig(_ config: SummarizerConfig) {
        let requestedEngine = config.defaultEngine
        var persistedConfig = config
        persistedConfig.defaultEngine = defaultEngine
        summarizerConfig = persistedConfig
        persistSummarizerConfig()
        refreshEngineStatuses()

        statusMessage = defaultEngine == .none
            ? "Summarizer disabled"
            : requestedEngine == defaultEngine
                ? "Summarizer settings updated for \(defaultEngine.displayName)"
                : "Saved \(requestedEngine.displayName) settings; \(defaultEngine.displayName) remains active until verified"
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
                recordActiveEngineRuntime(state: .green, detail: "Story generation succeeded.", verifiedAt: Date())
                return parsed
            }
            recordActiveEngineRuntime(
                state: .yellow,
                detail: "Story output was not valid structured JSON",
                verifiedAt: Date()
            )
        } catch {
            recordActiveEngineRuntime(
                state: .yellow,
                detail: error.localizedDescription,
                verifiedAt: Date()
            )
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

    static func makeSummarizer(
        config: SummarizerConfig = SummarizerConfig.load(),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> SummaryGenerating? {
        config.makeSummarizer(for: config.defaultEngine, environment: environment)
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

    private func persistSummarizerConfig() {
        summarizerConfig.save(
            to: userDefaults,
            keychain: keychain,
            keychainService: keychainService
        )
        environment?.summarizer = summarizerConfig.makeSummarizer(
            for: defaultEngine,
            environment: processEnvironment
        )
    }

    private func recordActiveEngineRuntime(
        state: EngineIndicatorState,
        detail: String,
        verifiedAt: Date?
    ) {
        engineStatuses[defaultEngine] = EngineRuntimeStatus(
            state: state,
            detail: detail,
            lastVerifiedAt: verifiedAt ?? engineStatuses[defaultEngine]?.lastVerifiedAt,
            configurationSignature: Self.configurationSignature(
                for: defaultEngine,
                config: summarizerConfig,
                environment: processEnvironment
            )
        )
    }

    private static func makeInitialEngineStatuses(
        config: SummarizerConfig,
        environment: [String: String]
    ) -> [DiaryEngine: EngineRuntimeStatus] {
        Dictionary(
            uniqueKeysWithValues: DiaryEngine.allCases.map { engine in
                (engine, makeBaselineStatus(for: engine, config: config, environment: environment))
            }
        )
    }

    private static func makeBaselineStatus(
        for engine: DiaryEngine,
        config: SummarizerConfig,
        environment: [String: String]
    ) -> EngineRuntimeStatus {
        let signature = configurationSignature(for: engine, config: config, environment: environment)
        switch engine {
        case .none:
            return EngineRuntimeStatus(
                state: .gray,
                detail: "No engine selected.",
                lastVerifiedAt: nil,
                configurationSignature: signature
            )
        case .openAI:
            if !config.apiConfigurationIsComplete {
                return EngineRuntimeStatus(
                    state: .gray,
                    detail: "API configuration is incomplete.",
                    lastVerifiedAt: nil,
                    configurationSignature: signature
                )
            }
            return EngineRuntimeStatus(
                state: .yellow,
                detail: "API configuration changed. Retest required.",
                lastVerifiedAt: nil,
                configurationSignature: signature
            )
        case .claudeCLI, .codexCLI, .geminiCLI, .openclawCLI:
            guard config.makeSummarizer(for: engine, environment: environment) != nil else {
                return EngineRuntimeStatus(
                    state: .gray,
                    detail: "Executable not found.",
                    lastVerifiedAt: nil,
                    configurationSignature: signature
                )
            }
            return EngineRuntimeStatus(
                state: .yellow,
                detail: "Executable found. Retest required.",
                lastVerifiedAt: nil,
                configurationSignature: signature
            )
        }
    }

    private static func configurationSignature(
        for engine: DiaryEngine,
        config: SummarizerConfig,
        environment: [String: String]
    ) -> String {
        switch engine {
        case .none:
            return "none"
        case .openAI:
            return [
                config.apiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines),
                config.apiModel.trimmingCharacters(in: .whitespacesAndNewlines),
                config.apiToken.trimmingCharacters(in: .whitespacesAndNewlines)
            ].joined(separator: "|")
        case .claudeCLI:
            return "claude|\(SummarizerConfig.resolvedExecutablePath(configuredPath: config.claudeCLIPath, commandName: "claude", environment: environment) ?? "")"
        case .codexCLI:
            return "codex|\(SummarizerConfig.resolvedExecutablePath(configuredPath: config.codexCLIPath, commandName: "codex", environment: environment) ?? "")"
        case .geminiCLI:
            return "gemini|\(SummarizerConfig.resolvedExecutablePath(configuredPath: config.geminiCLIPath, commandName: "gemini", environment: environment) ?? "")"
        case .openclawCLI:
            return "openclaw|\(SummarizerConfig.resolvedExecutablePath(configuredPath: config.openclawCLIPath, commandName: "openclaw", environment: environment) ?? "")"
        }
    }

    private static func state(for status: SummarizerRuntimeStatus) -> EngineIndicatorState {
        if !status.isConfigured {
            return .gray
        }
        return status.lastError == nil ? .green : .yellow
    }

    private static func inferEngine(from summarizer: SummaryGenerating?) -> DiaryEngine? {
        switch summarizer {
        case is CloudSummarizer:
            return .openAI
        case let summarizer as CLISummarizer:
            switch summarizer.tool {
            case .claude:
                return .claudeCLI
            case .codex:
                return .codexCLI
            case .gemini:
                return .geminiCLI
            case .openclaw:
                return .openclawCLI
            }
        default:
            return nil
        }
    }

    private static func reconciledConfig(
        from config: SummarizerConfig,
        with summarizer: SummaryGenerating
    ) -> SummarizerConfig {
        var reconciled = config

        switch summarizer {
        case let summarizer as CloudSummarizer:
            reconciled.defaultEngine = .openAI
            reconciled.apiBaseURL = summarizer.apiURL.absoluteString
            reconciled.apiModel = summarizer.model
            reconciled.apiToken = summarizer.apiKey
        case let summarizer as CLISummarizer:
            switch summarizer.tool {
            case .claude:
                reconciled.defaultEngine = .claudeCLI
                reconciled.claudeCLIPath = summarizer.executablePath
            case .codex:
                reconciled.defaultEngine = .codexCLI
                reconciled.codexCLIPath = summarizer.executablePath
            case .gemini:
                reconciled.defaultEngine = .geminiCLI
                reconciled.geminiCLIPath = summarizer.executablePath
            case .openclaw:
                reconciled.defaultEngine = .openclawCLI
                reconciled.openclawCLIPath = summarizer.executablePath
            }
        default:
            break
        }

        return reconciled
    }

    private static func initialDefaultEngine(
        explicitConfigProvided: Bool,
        config: inout SummarizerConfig,
        environment: SummaryGenerating?,
        engineStatuses: [DiaryEngine: EngineRuntimeStatus]
    ) -> DiaryEngine {
        if let inferred = inferEngine(from: environment) {
            config.defaultEngine = inferred
            return inferred
        }

        let persistedEngine = config.defaultEngine
        guard !explicitConfigProvided, persistedEngine != .none else {
            return persistedEngine
        }

        guard engineStatuses[persistedEngine]?.state == .green else {
            config.defaultEngine = .none
            return .none
        }

        return persistedEngine
    }
}
