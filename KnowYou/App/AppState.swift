import Foundation
import Observation
import AppKit
import UserNotifications
import ServiceManagement

protocol LoginItemManaging: AnyObject {
    var isRegistered: Bool { get }
    func register() throws
    func unregister() throws
}

final class MainAppLoginItemManager: LoginItemManaging {
    var isRegistered: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func register() throws {
        try SMAppService.mainApp.register()
    }

    func unregister() throws {
        try SMAppService.mainApp.unregister()
    }
}

extension Notification.Name {
    static let endOfDayReminderOpened = Notification.Name("KnowYou.endOfDayReminderOpened")
}

enum ReaderFocusZone: Hashable {
    case dateList
    case storyParagraphs
}

enum MainContentSelection: Equatable {
    case diary(dayKey: String?)
    case otherSourceManager(focusAddConnector: Bool)
    case knowledgeConnector(instanceID: String)
    case knowledgeDocument(connectorInstanceID: String, documentID: String)
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

enum DayRefreshStage: Equatable, Hashable {
    case syncingNotifications
    case loadingEvents
    case preparingStory
    case generatingStory
    case writingFiles
    case completed
    case failed

    var detail: String {
        switch self {
        case .syncingNotifications:
            return "Syncing notifications..."
        case .loadingEvents:
            return "Loading captured events..."
        case .preparingStory:
            return "Preparing journal..."
        case .generatingStory:
            return "Generating story..."
        case .writingFiles:
            return "Writing files..."
        case .completed:
            return "Refresh complete"
        case .failed:
            return "Refresh failed"
        }
    }

    var isProgressStep: Bool {
        switch self {
        case .syncingNotifications, .loadingEvents, .preparingStory, .generatingStory, .writingFiles:
            return true
        case .completed, .failed:
            return false
        }
    }
}

struct DayRefreshJob: Equatable {
    var dayKey: String
    var stage: DayRefreshStage
    var detail: String?
    var error: String?
    var completedStages: [DayRefreshStage] = []
    var summary: String? = nil
    var inFlight: Bool {
        switch stage {
        case .completed, .failed:
            return false
        default:
            return true
        }
    }
}

struct DayRefreshGenerationResult: Equatable {
    var stage: DayRefreshStage
    var summary: String
}

struct OnboardingBootstrapNotice: Equatable, Identifiable {
    let id = UUID()
    var message: String
}

enum DayRefreshMode: Equatable {
    case fullRecovery
    case incrementalUpdate
}

enum ChunkedFullRefreshContext {
    case onboardingBootstrap
    case selectedDayOverwrite
    case incrementalUpdate

    var logLabel: String {
        switch self {
        case .onboardingBootstrap:
            return "onboarding bootstrap"
        case .selectedDayOverwrite:
            return "full refresh"
        case .incrementalUpdate:
            return "incremental update"
        }
    }

    var resultSummary: String {
        switch self {
        case .onboardingBootstrap:
            return "chunked onboarding bootstrap"
        case .selectedDayOverwrite:
            return "chunked full refresh"
        case .incrementalUpdate:
            return "chunked incremental append"
        }
    }

    var missingStoryError: String {
        switch self {
        case .onboardingBootstrap:
            return "Chunked onboarding bootstrap could not load the current story"
        case .selectedDayOverwrite:
            return "Chunked full refresh could not load the current story"
        case .incrementalUpdate:
            return "Chunked incremental update could not load the current story"
        }
    }

    func completionStatusMessage(for dayKey: String, now: Date) -> String {
        switch self {
        case .onboardingBootstrap:
            return dayKey == ISO8601DayKey.format(now)
                ? "Refreshed today with chunked onboarding bootstrap"
                : "Refreshed \(dayKey) with chunked onboarding bootstrap"
        case .selectedDayOverwrite:
            return dayKey == ISO8601DayKey.format(now)
                ? "Refreshed today with chunked full refresh"
                : "Refreshed \(dayKey) with chunked full refresh"
        case .incrementalUpdate:
            return dayKey == ISO8601DayKey.format(now)
                ? "Updated today with chunked incremental refresh"
                : "Updated \(dayKey) with chunked incremental refresh"
        }
    }

    func chunkFailureError(for chunkLabel: String, persistedChunkCount: Int? = nil) -> String {
        switch self {
        case .onboardingBootstrap:
            if let persistedChunkCount {
                return "Onboarding bootstrap failed during \(chunkLabel) after persisting \(persistedChunkCount) chunk(s)"
            }
            return "Onboarding bootstrap failed during \(chunkLabel)"
        case .selectedDayOverwrite:
            if let persistedChunkCount {
                return "Full refresh failed during \(chunkLabel) after persisting \(persistedChunkCount) chunk(s)"
            }
            return "Full refresh failed during \(chunkLabel)"
        case .incrementalUpdate:
            if let persistedChunkCount {
                return "Incremental update failed during \(chunkLabel) after persisting \(persistedChunkCount) chunk(s)"
            }
            return "Incremental update failed during \(chunkLabel)"
        }
    }
}

enum RefreshModeResolutionError: LocalizedError {
    case failedToLoadExistingStory(dayKey: String, underlying: Error)

    var errorDescription: String? {
        switch self {
        case .failedToLoadExistingStory(let dayKey, let underlying):
            return "Failed to load existing story for \(dayKey): \(underlying.localizedDescription)"
        }
    }
}

enum RefreshTrigger: String, Codable, Sendable {
    case manual
    case automation
}

struct RefreshLogStageRecord: Codable, Equatable {
    var name: String
    var durationSeconds: Double
    var detail: String?
}

struct RefreshLogAttemptRecord: Codable, Equatable {
    var engine: String
    var timeoutSeconds: Int
    var startedAt: Date
    var finishedAt: Date
    var durationSeconds: Double
    var outcome: String
    var failureKind: String?
    var error: String?
}

struct RefreshLogRecord: Codable, Equatable {
    var dayKey: String
    var trigger: RefreshTrigger
    var mode: String
    var startedAt: Date
    var finishedAt: Date?
    var totalDurationSeconds: Double?
    var notificationImportedCount: Int = 0
    var notificationError: String?
    var totalEventCount: Int = 0
    var newEventCount: Int?
    var stages: [RefreshLogStageRecord] = []
    var attempts: [RefreshLogAttemptRecord] = []
    var wroteMarkdown = false
    var wroteStoryJSON = false
    var markdownPath: String?
    var storyJSONPath: String?
    var finalStatus: String = "running"
    var finalSummary: String?
    var logPath: String?
}

final class RefreshLogBuffer {
    var record: RefreshLogRecord

    init(record: RefreshLogRecord) {
        self.record = record
    }
}

private struct RefreshSummarizerAttempt {
    let engine: DiaryEngine?
    let summarizer: SummaryGenerating

    var label: String {
        engine?.displayName ?? "configured summarizer"
    }
}

private enum RefreshAttemptRunResult {
    case succeeded(
        attempt: RefreshSummarizerAttempt,
        raw: String,
        startedAt: Date,
        finishedAt: Date
    )
    case failed(
        attempt: RefreshSummarizerAttempt,
        error: Error,
        startedAt: Date,
        finishedAt: Date
    )
    case cancelled(
        attempt: RefreshSummarizerAttempt,
        startedAt: Date,
        finishedAt: Date
    )
}

struct SummarizerRuntimeStatus {
    enum FailureKind: String, Equatable {
        case timedOut
        case nonZeroExit
        case emptyOutput
        case invalidStructuredOutput
        case repairFailed
    }

    var mode: String = "None"
    var isConfigured = false
    var lastCompletedAt: Date?
    var lastError: String?
    var failureKind: FailureKind?
}

struct EngineRuntimeStatus: Equatable {
    var state: EngineIndicatorState = .gray
    var detail: String = "Not configured."
    var lastVerifiedAt: Date?
    var configurationSignature: String = ""
}

enum OnboardingBootstrapState: String, Codable, Equatable {
    case idle
    case pending
    case inProgress
    case complete
}

struct OnboardingReferenceAdvancePolicy: Equatable {
    let requiredSelections: Int
    let delaySeconds: TimeInterval
    private(set) var firstSelectionAt: Date?
    private(set) var validSelectionCount: Int

    init(requiredSelections: Int = 2, delaySeconds: TimeInterval = 6, firstSelectionAt: Date? = nil, validSelectionCount: Int = 0) {
        self.requiredSelections = requiredSelections
        self.delaySeconds = delaySeconds
        self.firstSelectionAt = firstSelectionAt
        self.validSelectionCount = validSelectionCount
    }

    mutating func registerValidParagraphSelection(at date: Date) -> Bool {
        if firstSelectionAt == nil {
            firstSelectionAt = date
        }
        validSelectionCount += 1
        return validSelectionCount >= requiredSelections
    }

    func shouldAdvanceReferenceStep(at date: Date) -> Bool {
        guard let firstSelectionAt, validSelectionCount > 0 else {
            return false
        }
        return date.timeIntervalSince(firstSelectionAt) >= delaySeconds
    }

    mutating func reset() {
        firstSelectionAt = nil
        validSelectionCount = 0
    }
}

enum JournalListOrdering {
    static func orderedDates(
        noteDays: Set<String>,
        placeholderDays: [String] = [],
        includeDemoDay: Bool
    ) -> [String] {
        let allRealDays = noteDays
            .union(placeholderDays)
            .filter { $0 != OnboardingDemoStory.demoDayKey }
            .sorted(by: >)

        if includeDemoDay {
            return allRealDays + [OnboardingDemoStory.demoDayKey]
        }

        return allRealDays
    }
}

enum OnboardingProgressState: String, Codable, Equatable {
    case demoReadPending
    case demoClickPending
    case demoReferencePending
    case privacyPending
    case permissionsPending
    case enginePromptPending
    case engineSetupPending
    case firstGenerationInProgress
    case complete

    var currentStep: OnboardingStep? {
        switch self {
        case .demoReadPending:
            return .demoRead
        case .demoClickPending:
            return .demoClick
        case .demoReferencePending:
            return .demoReference
        case .privacyPending:
            return .privacy
        case .permissionsPending:
            return .permissions
        case .enginePromptPending:
            return .enginePrompt
        case .engineSetupPending:
            return .engineSetup
        case .firstGenerationInProgress:
            return .generating
        case .complete:
            return nil
        }
    }

    var isComplete: Bool {
        self == .complete
    }

    static func pending(for step: OnboardingStep) -> OnboardingProgressState {
        switch step {
        case .demoRead:
            return .demoReadPending
        case .demoClick:
            return .demoClickPending
        case .demoReference:
            return .demoReferencePending
        case .privacy:
            return .privacyPending
        case .permissions:
            return .permissionsPending
        case .enginePrompt:
            return .enginePromptPending
        case .engineSetup:
            return .engineSetupPending
        case .generating:
            return .firstGenerationInProgress
        }
    }
}

struct OnboardingProgress: Equatable {
    var state: OnboardingProgressState

    init(state: OnboardingProgressState = .demoReadPending) {
        self.state = state
    }

    init(step: OnboardingStep) {
        self.state = OnboardingProgressState.pending(for: step)
    }

    var currentStep: OnboardingStep? {
        state.currentStep
    }

    var isComplete: Bool {
        state.isComplete
    }

    func restored(
        isFullDiskAccessReady: Bool,
        isEngineReady: Bool,
        allowsFullDiskAccessBypass: Bool = false
    ) -> OnboardingProgress {
        guard let currentStep else {
            return self
        }
        let canProceedPastPermissions = isFullDiskAccessReady || allowsFullDiskAccessBypass

        switch currentStep {
        case .demoRead, .demoClick, .demoReference, .privacy:
            return self
        case .permissions:
            if !canProceedPastPermissions {
                return OnboardingProgress(state: .permissionsPending)
            }
            return OnboardingProgress(state: .enginePromptPending)
        case .enginePrompt:
            if !canProceedPastPermissions {
                return OnboardingProgress(state: .permissionsPending)
            }
            return OnboardingProgress(state: .enginePromptPending)
        case .engineSetup:
            if !canProceedPastPermissions {
                return OnboardingProgress(state: .permissionsPending)
            }
            if !isEngineReady {
                return OnboardingProgress(state: .engineSetupPending)
            }
            return OnboardingProgress(state: .firstGenerationInProgress)
        case .generating:
            if !canProceedPastPermissions {
                return OnboardingProgress(state: .permissionsPending)
            }
            if !isEngineReady {
                return OnboardingProgress(state: .enginePromptPending)
            }
            return OnboardingProgress(state: .firstGenerationInProgress)
        }
    }
}

private struct ReaderPresentationSnapshot {
    let availableDates: [String]
    let selectedDate: String?
    let mainContentSelection: MainContentSelection
    let selectedMarkdownURL: URL?
    let noteIndex: [String: URL]
    let selectedStory: DailyStory?
    let selectedStoryParagraphID: String?
    let selectedStorySourceEvents: [EventRecord]
    let selectedDayEvents: [EventRecord]
    let selectedMarkdownText: String?
    let selectedSourceNotesMarkdown: String?
    let readerFocus: ReaderFocusZone
}

@MainActor
@Observable
final class AppState {
    typealias RefreshStageChangeHandler = @MainActor @Sendable (DayRefreshJob) -> Void
    typealias SummarizerFactory = @Sendable (DiaryEngine, SummarizerConfig, [String: String]) -> SummaryGenerating?

    private static let autoSelectionPriority: [DiaryEngine] = [
        .claudeCLI,
        .codexAuth,
        .codexCLI,
        .geminiCLI,
        .openclawCLI,
        .llmAPI,
    ]
    private static let knowledgeDocumentMarkdownPreviewByteLimit = 256_000
    private static let knowledgeDocumentMarkdownPreviewTruncationMarker = "\n\n[Preview truncated]"

    var availableDates: [String] = []
    var selectedDate: String?
    var selectedMarkdownURL: URL?
    var noteIndex: [String: URL] = [:]
    var statusMessage: String?
    var endOfDayReminderTestStatusMessage: String?
    var syncMemoryStatusMessage: String?
    var knowledgeImportStatusMessage: String?
    var isShowingSyncMemoryPanel = false
    var lastAutomationRunAt: Date?
    var lastImportedNotificationCount = 0
    var lastNotificationImportAt: Date?
    var pendingBackfillDays: [String] = []
    var clipboardStatus = ClipboardMonitorStatus()
    var notificationStatus = NotificationImportStatus()
    var dayRefreshStatus = DayRefreshStatus()
    var syncMemoryConfig: SyncMemoryConfig
    var knowledgeImportConfig: KnowledgeImportConfig
    var endOfDayReminderConfig: EndOfDayReminderConfig
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
    var refreshLogNoticesByDay: [String: String] = [:]
    var readerFocus: ReaderFocusZone = .dateList
    var mainContentSelection: MainContentSelection = .diary(dayKey: nil)
    var selectedKnowledgeDocuments: [ImportedKnowledgeDocument] = []
    var selectedKnowledgeDocument: ImportedKnowledgeDocument?
    var selectedKnowledgeDocumentMarkdown: String?
    var knowledgeDocumentsByConnector: [String: [ImportedKnowledgeDocument]] = [:]
    var onboardingProgress: OnboardingProgress
    var onboardingBootstrapState: OnboardingBootstrapState
    var onboardingBootstrapDayKeys: [String]
    var onboardingBootstrapNotice: OnboardingBootstrapNotice?
    var updateOffer: UpdateOffer?
    var isShowingUpdateSheet = false
    var lastUpdateCheckAt: Date?
    var launchAtLoginEnabled = false
    var launchAtLoginStatusMessage: String?
    private var refreshJobsByDay: [String: DayRefreshJob] = [:]
    private(set) var environment: AppEnvironment?
    @ObservationIgnored private var automationTimer: Timer?
    @ObservationIgnored private var notificationCatchUpTimer: Timer?
    @ObservationIgnored private var onboardingBootstrapTask: Task<Void, Never>?
    @ObservationIgnored private var onboardingBootstrapNoticeDismissTask: Task<Void, Never>?
    @ObservationIgnored private var paragraphSelectionByDay: [String: String] = [:]
    @ObservationIgnored private var refreshTasksByDay: [String: Task<Bool, Never>] = [:]
    @ObservationIgnored private var liveReaderSnapshot: ReaderPresentationSnapshot?
    @ObservationIgnored private var isPresentingOnboardingDemo = false
    @ObservationIgnored private let notificationSyncInterval: TimeInterval = 30
    @ObservationIgnored private let automationInterval: TimeInterval = 10_800
    @ObservationIgnored private let notificationOverlapBuffer: TimeInterval = 30
    @ObservationIgnored private let maxConcurrentRefreshes = 2
    @ObservationIgnored private let refreshEventBatchSize = 50
    @ObservationIgnored private let userDefaults: UserDefaults
    @ObservationIgnored private let keychain: KeychainStoring
    @ObservationIgnored private let keychainService: String
    @ObservationIgnored private let processEnvironment: [String: String]
    @ObservationIgnored private let currentDate: @Sendable () -> Date
    @ObservationIgnored private let probeEngine: @Sendable (DiaryEngine, SummarizerConfig, [String: String]) async -> EngineProbeResult
    @ObservationIgnored private let makeSummarizer: SummarizerFactory
    @ObservationIgnored private let onRefreshStageChange: RefreshStageChangeHandler?
    @ObservationIgnored private let notifyOnboardingBootstrapCompletion: @MainActor @Sendable ([String]) -> Void
    @ObservationIgnored private let launchAgentManager: LaunchAgentManager
    @ObservationIgnored private let knowledgeImportLaunchAgentManager: LaunchAgentManager
    @ObservationIgnored private let loginItemManager: any LoginItemManaging
    @ObservationIgnored private let endOfDayReminderLaunchAgentManager: LaunchAgentManager
    @ObservationIgnored private let endOfDayReminderPlanner: EndOfDayReminderPlanner
    @ObservationIgnored private let endOfDayReminderService: EndOfDayReminderService
    @ObservationIgnored private var summarizerConfig: SummarizerConfig
    @ObservationIgnored private var autoSelectionSuppressedByExplicitNone: Bool
    @ObservationIgnored private var dayReviewStates: [String: DayReviewState]

    private static var defaultUserDefaultsOverrideForTesting: UserDefaults?

    static func setDefaultUserDefaultsForTesting(_ defaults: UserDefaults?) {
        defaultUserDefaultsOverrideForTesting = defaults
    }

    private static func defaultUserDefaults() -> UserDefaults {
        defaultUserDefaultsOverrideForTesting ?? .standard
    }

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
                    : status.detail,
                failureKind: Self.failureKind(for: status.detail)
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
        makeSummarizer: @escaping SummarizerFactory = { engine, config, environment in
            config.makeSummarizer(for: engine, environment: environment)
        },
        onRefreshStageChange: RefreshStageChangeHandler? = nil,
        notifyOnboardingBootstrapCompletion: @escaping @MainActor @Sendable ([String]) -> Void = { dayKeys in
            Task {
                await AppState.deliverOnboardingBootstrapCompletionNotification(for: dayKeys)
            }
        },
        processEnvironment: [String: String] = ProcessInfo.processInfo.environment,
        currentDate: @escaping @Sendable () -> Date = Date.init,
        userDefaults: UserDefaults? = nil,
        keychain: KeychainStoring = KeychainHelper.shared,
        keychainService: String = KeychainHelper.service,
        launchAgentManager: LaunchAgentManager = LaunchAgentManager(),
        knowledgeImportLaunchAgentManager: LaunchAgentManager = LaunchAgentManager(
            label: "dev.knowyou.knowledge-import"
        ),
        loginItemManager: any LoginItemManaging = MainAppLoginItemManager(),
        endOfDayReminderLaunchAgentManager: LaunchAgentManager = LaunchAgentManager(
            label: "dev.knowyou.end-of-day-reminder"
        ),
        endOfDayReminderPlanner: EndOfDayReminderPlanner = EndOfDayReminderPlanner(),
        endOfDayReminderService: EndOfDayReminderService = EndOfDayReminderService()
    ) {
        let explicitSummarizerConfig = summarizerConfig
        let resolvedUserDefaults = userDefaults ?? Self.defaultUserDefaults()
        self.userDefaults = resolvedUserDefaults
        self.keychain = keychain
        self.keychainService = keychainService
        self.processEnvironment = processEnvironment
        self.currentDate = currentDate
        self.probeEngine = probeEngine
        self.makeSummarizer = makeSummarizer
        self.onRefreshStageChange = onRefreshStageChange
        self.notifyOnboardingBootstrapCompletion = notifyOnboardingBootstrapCompletion
        self.launchAgentManager = launchAgentManager
        self.knowledgeImportLaunchAgentManager = knowledgeImportLaunchAgentManager
        self.loginItemManager = loginItemManager
        self.endOfDayReminderLaunchAgentManager = endOfDayReminderLaunchAgentManager
        self.endOfDayReminderPlanner = endOfDayReminderPlanner
        self.endOfDayReminderService = endOfDayReminderService
        self.summarizerConfig = summarizerConfig ?? SummarizerConfig.load(
            from: resolvedUserDefaults,
            keychain: keychain,
            keychainService: keychainService
        )
        self.syncMemoryConfig = Self.bootstrapSyncMemoryConfigIfNeeded(
            startingFrom: SyncMemoryConfig.load(from: resolvedUserDefaults),
            userDefaults: resolvedUserDefaults
        )
        self.knowledgeImportConfig = KnowledgeImportConfig.load(from: resolvedUserDefaults)
        self.endOfDayReminderConfig = EndOfDayReminderConfig.load(from: resolvedUserDefaults)
        self.dayReviewStates = Self.loadDayReviewStates(from: resolvedUserDefaults)
        let persistedSuppression = resolvedUserDefaults.object(
            forKey: UserDefaultsKeys.explicitlyDisabledSummarizerAutoSelection
        ) as? Bool
        self.autoSelectionSuppressedByExplicitNone = persistedSuppression ?? false
        self.lastNotificationImportAt = resolvedUserDefaults.object(forKey: UserDefaultsKeys.lastNotificationImportAt) as? Date
        self.lastUpdateCheckAt = resolvedUserDefaults.object(forKey: UserDefaultsKeys.lastUpdateCheckAt) as? Date
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
        onboardingProgress = Self.loadOnboardingProgress(from: resolvedUserDefaults)
        onboardingBootstrapState = Self.loadOnboardingBootstrapState(from: resolvedUserDefaults)
        onboardingBootstrapDayKeys = Self.loadOnboardingBootstrapDayKeys(from: resolvedUserDefaults)
        onboardingBootstrapNotice = nil
        if explicitSummarizerConfig == nil,
           environment?.summarizer == nil,
            self.summarizerConfig.defaultEngine != loadedDefaultEngine {
            self.summarizerConfig.save(
                to: resolvedUserDefaults,
                keychain: keychain,
                keychainService: keychainService
            )
        }

        if let environment {
            self.environment = environment
            restorePersistedNotificationImportAt(using: environment, now: currentDate())
            if explicitSummarizerConfig != nil {
                environment.summarizer = environment.summarizer
                    ?? self.makeSummarizer(defaultEngine, self.summarizerConfig, processEnvironment)
            }
            clipboardStatus.isActive = true
            updateNotificationAccessStatus(using: environment.notificationReader)
            refreshEngineStatuses()
            refreshNotesIndex()
            queueInitialLinkedSourceScanIfNeeded()
            if bootstrapServices {
                queueEndOfDayReminderBootstrap()
                restoreOnboardingProgress(
                    isFullDiskAccessReady: notificationStatus.isDatabaseAvailable,
                    isEngineReady: summarizerStatus.isConfigured
                )
                if onboardingProgress.isComplete {
                    startAutomation(runImmediately: onboardingBootstrapState == .complete || onboardingBootstrapState == .idle)
                    resumeOnboardingBootstrapIfNeeded()
                }
                Task { @MainActor in
                    await self.checkForUpdatesIfNeeded(force: true, now: currentDate())
                }
            }
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
                summarizer: self.makeSummarizer(defaultEngine, self.summarizerConfig, processEnvironment),
                onClipboardCapture: { [weak self] snapshot in
                    Task { @MainActor in
                        self?.recordClipboardCapture(snapshot)
                    }
                }
            )
            environment.clipboardWatcher.start()
            try? environment.databaseWriter.markOrphanRunsAsFailed()
            self.environment = environment
            restorePersistedNotificationImportAt(using: environment, now: currentDate())
            clipboardStatus.isActive = true
            updateNotificationAccessStatus(using: environment.notificationReader)
            refreshEngineStatuses()
            refreshNotesIndex()
            queueInitialLinkedSourceScanIfNeeded()
            statusMessage = "Capture services ready"
            queueEndOfDayReminderBootstrap()
            restoreOnboardingProgress(
                isFullDiskAccessReady: notificationStatus.isDatabaseAvailable,
                isEngineReady: summarizerStatus.isConfigured
            )
            if onboardingProgress.isComplete {
                startAutomation(runImmediately: onboardingBootstrapState == .complete || onboardingBootstrapState == .idle)
                resumeOnboardingBootstrapIfNeeded()
            }
        } catch {
            statusMessage = "Capture unavailable: \(error.localizedDescription)"
        }
    }

    var shouldShowUpdatePill: Bool {
        updateOffer != nil
    }

    var endOfDayReminderStatusSummary: String {
        endOfDayReminderConfig.authorizationStatus.settingsSummary
    }

    func selectDate(_ date: String) {
        if date == OnboardingDemoStory.demoDayKey {
            readerFocus = .dateList
            setSelectedDiaryDate(date)
            loadDemoDayPresentation()
            return
        }
        readerFocus = .dateList
        setSelectedDiaryDate(date)
        selectedMarkdownURL = noteIndex[date]
        loadDayPresentation(for: date)
    }

    func selectOtherSourceManager(focusAddConnector: Bool) {
        mainContentSelection = .otherSourceManager(focusAddConnector: focusAddConnector)
        readerFocus = .dateList
    }

    func selectKnowledgeConnector(instanceID: String) {
        mainContentSelection = .knowledgeConnector(instanceID: instanceID)
        readerFocus = .dateList
        refreshKnowledgeDocumentTree()
        selectedKnowledgeDocuments = fetchKnowledgeDocuments(connectorInstanceID: instanceID)
        selectedKnowledgeDocument = nil
        selectedKnowledgeDocumentMarkdown = nil
    }

    func selectKnowledgeDocument(connectorInstanceID: String, documentID: String) {
        mainContentSelection = .knowledgeDocument(
            connectorInstanceID: connectorInstanceID,
            documentID: documentID
        )
        selectedKnowledgeDocuments = fetchKnowledgeDocuments(connectorInstanceID: connectorInstanceID)
        selectedKnowledgeDocument = selectedKnowledgeDocuments.first { $0.id == documentID }
        selectedKnowledgeDocumentMarkdown = loadKnowledgeDocumentMarkdown(selectedKnowledgeDocument)
        refreshKnowledgeDocumentTree()
    }

    func didDeleteKnowledgeConnector(instanceID: String) {
        switch mainContentSelection {
        case .knowledgeConnector(let selectedID) where selectedID == instanceID,
             .knowledgeDocument(connectorInstanceID: let selectedID, documentID: _) where selectedID == instanceID:
            selectOtherSourceManager(focusAddConnector: false)
        default:
            break
        }
    }

    func openDayFromEndOfDayReminder(_ dayKey: String, action: EndOfDayReminderAction = .review) {
        guard shouldShowOnboarding == false else { return }
        refreshNotesIndex()
        selectDate(dayKey)
        readerFocus = .dateList
        switch action {
        case .review:
            statusMessage = "Opened \(dayKey) from evening review reminder"
        case .generate:
            statusMessage = "Generating \(dayKey) from evening review reminder"
            Task { @MainActor [weak self] in
                await self?.generateDailyNote(for: dayKey)
            }
        }
    }

    func selectStoryParagraph(_ paragraphID: String) {
        selectedStoryParagraphID = paragraphID
        if let selectedDate {
            paragraphSelectionByDay[selectedDate] = paragraphID
        }
        syncSelectedStorySources()
    }

    func clearOnboardingDemoStorySelection() {
        guard isPresentingOnboardingDemo else { return }
        selectedStoryParagraphID = nil
        selectedStorySourceEvents = []
    }

    private func refreshKnowledgeDocumentTree() {
        guard let environment else {
            knowledgeDocumentsByConnector = [:]
            return
        }
        let documents = (try? environment.databaseWriter.fetchImportedKnowledgeDocuments()) ?? []
        knowledgeDocumentsByConnector = Dictionary(grouping: documents, by: \.connectorInstanceID)
    }

    private func fetchKnowledgeDocuments(connectorInstanceID: String) -> [ImportedKnowledgeDocument] {
        guard let environment else { return [] }
        return (try? environment.databaseWriter.fetchImportedKnowledgeDocuments(
            connectorInstanceID: connectorInstanceID
        )) ?? []
    }

    private func loadKnowledgeDocumentMarkdown(_ document: ImportedKnowledgeDocument?) -> String? {
        guard let document else { return nil }
        guard let fileHandle = FileHandle(forReadingAtPath: document.localContentPath) else {
            return nil
        }
        defer { try? fileHandle.close() }

        let data = fileHandle.readData(ofLength: Self.knowledgeDocumentMarkdownPreviewByteLimit + 1)
        let isTruncated = data.count > Self.knowledgeDocumentMarkdownPreviewByteLimit
        let previewBytes = isTruncated
            ? Data(data.prefix(Self.knowledgeDocumentMarkdownPreviewByteLimit))
            : data
        var markdown = String(decoding: previewBytes, as: UTF8.self)
        if isTruncated {
            markdown += Self.knowledgeDocumentMarkdownPreviewTruncationMarker
        }
        return markdown
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
        await refreshDay(targetDay, now: now, environment: environment)
    }

    func refreshSelectedDayFullRecovery(now: Date = Date()) async {
        guard let environment else {
            statusMessage = "Capture unavailable"
            return
        }

        let targetDay = selectedDate ?? ISO8601DayKey.format(now)
        if selectedDate == nil {
            selectDate(targetDay)
        }
        guard targetDay != OnboardingDemoStory.demoDayKey else {
            statusMessage = "Demo Day is read-only"
            return
        }

        await refreshDay(
            targetDay,
            now: now,
            environment: environment,
            forcedMode: .fullRecovery,
            chunkedFullRefreshContext: .selectedDayOverwrite
        )
    }

    func generateDailyNote(for dayKey: String) async {
        guard let environment else {
            statusMessage = "Capture unavailable"
            return
        }
        await refreshDay(dayKey, now: currentDate(), environment: environment)
    }

    func refreshJob(for dayKey: String) -> DayRefreshJob? {
        refreshJobsByDay[dayKey]
    }

    func applyVaultURL(_ url: URL) {
        userDefaults.set(url.path, forKey: UserDefaultsKeys.vaultPath)
        guard let environment else { return }
        environment.vaultURL = url
        refreshNotesIndex()
        statusMessage = "Vault set to \(url.lastPathComponent)"
    }

    func openSyncMemoryPanel() {
        isShowingSyncMemoryPanel = true
    }

    func closeSyncMemoryPanel() {
        isShowingSyncMemoryPanel = false
    }

    func openUpdateSheet() {
        guard updateOffer != nil else { return }
        isShowingUpdateSheet = true
    }

    func dismissUpdateSheet() {
        isShowingUpdateSheet = false
    }

    func performUpdatePrimaryAction() {
        guard let offer = updateOffer else { return }

        switch offer.actionKind {
        case .installInApp:
            guard let environment else {
                statusMessage = DirectAppUpdateError.notConfigured.localizedDescription
                return
            }

            statusMessage = "Opening update download..."
            Task { @MainActor [weak self] in
                do {
                    try await environment.directAppUpdater.startUpdate(for: offer)
                    self?.isShowingUpdateSheet = false
                } catch {
                    self?.statusMessage = error.localizedDescription
                }
            }
        case .openAppStore:
            guard let url = offer.storeURL else {
                statusMessage = "App Store link unavailable for this build."
                return
            }

            if let environment {
                environment.externalURLOpener(url)
            } else {
                NSWorkspace.shared.open(url)
            }
            isShowingUpdateSheet = false
        case .unavailable:
            statusMessage = "Automatic updates are unavailable for this build."
        }
    }

    func checkForUpdatesIfNeeded(force: Bool = false, now: Date = Date()) async {
        guard let environment else { return }
        if force == false,
           let lastUpdateCheckAt,
           Calendar.current.isDate(lastUpdateCheckAt, inSameDayAs: now) {
            return
        }

        do {
            updateOffer = try await environment.updateService.fetchOffer()
        } catch {
            updateOffer = nil
        }

        lastUpdateCheckAt = now
        userDefaults.set(now, forKey: UserDefaultsKeys.lastUpdateCheckAt)
    }

    func ensureDefaultLaunchAtLogin() {
        guard userDefaults.bool(forKey: UserDefaultsKeys.launchAtLoginDefaultRegistrationAttempted) == false else {
            launchAtLoginEnabled = loginItemManager.isRegistered
            return
        }

        userDefaults.set(true, forKey: UserDefaultsKeys.launchAtLoginDefaultRegistrationAttempted)
        do {
            try loginItemManager.register()
            launchAtLoginEnabled = loginItemManager.isRegistered
            launchAtLoginStatusMessage = nil
        } catch {
            launchAtLoginEnabled = loginItemManager.isRegistered
            launchAtLoginStatusMessage = "Launch at Login setup failed: \(error.localizedDescription)"
        }
    }

    func setLaunchAtLoginEnabled(_ isEnabled: Bool) {
        userDefaults.set(true, forKey: UserDefaultsKeys.launchAtLoginDefaultRegistrationAttempted)
        do {
            if isEnabled {
                try loginItemManager.register()
            } else {
                try loginItemManager.unregister()
            }
            launchAtLoginEnabled = loginItemManager.isRegistered
            launchAtLoginStatusMessage = isEnabled ? "Launch at Login enabled" : "Launch at Login disabled"
        } catch {
            launchAtLoginEnabled = loginItemManager.isRegistered
            launchAtLoginStatusMessage = "Launch at Login setup failed: \(error.localizedDescription)"
        }
    }

    func saveSyncMemoryConfig(_ config: SyncMemoryConfig) {
        syncMemoryConfig = config
        syncMemoryConfig.save(to: userDefaults)
        do {
            try launchAgentManager.syncRegistration(
                executablePath: Bundle.main.executableURL?.path,
                hour: config.dailySyncHour,
                minute: config.dailySyncMinute,
                isEnabled: config.autoSyncEnabled
            )
            if config.autoSyncEnabled {
                let timeSummary = String(format: "%02d:%02d", config.dailySyncHour, config.dailySyncMinute)
                setSyncMemoryStatus("Auto Sync Daily enabled for \(timeSummary)")
            } else {
                setSyncMemoryStatus("Auto Sync Daily disabled")
            }
        } catch {
            setSyncMemoryStatus("Auto Sync Daily setup failed: \(error.localizedDescription)")
        }
    }

    func updateSyncMemoryChannel(_ channel: SyncMemoryChannel, resolvedPath: String, isEnabled: Bool = true) {
        var config = syncMemoryConfig
        switch channel {
        case .obsidian:
            config.obsidian.resolvedPath = resolvedPath
            config.obsidian.isEnabled = isEnabled
        case .openClaw:
            config.openClaw.resolvedPath = resolvedPath
            config.openClaw.isEnabled = isEnabled
        }
        saveSyncMemoryConfig(config)
    }

    func syncMemoryNow() {
        guard let environment else {
            setSyncMemoryStatus("Capture unavailable")
            return
        }

        var destinations: [SyncMemoryChannel: URL] = [:]
        if syncMemoryConfig.obsidian.isEnabled,
           let resolvedPath = normalizedSyncMemoryPath(syncMemoryConfig.obsidian.resolvedPath) {
            destinations[.obsidian] = URL(fileURLWithPath: resolvedPath, isDirectory: true)
        }
        if syncMemoryConfig.openClaw.isEnabled,
           let resolvedPath = normalizedSyncMemoryPath(syncMemoryConfig.openClaw.resolvedPath) {
            destinations[.openClaw] = URL(fileURLWithPath: resolvedPath, isDirectory: true)
        }

        guard !destinations.isEmpty else {
            setSyncMemoryStatus("No Sync Memory destinations enabled")
            return
        }

        let coordinator = SyncMemoryCoordinator()
        do {
            let results = try coordinator.syncDiaries(
                sourceVault: environment.vaultURL,
                destinations: destinations
            )
            let count = results.count
            let syncedFileCount = results.values.first?.copiedFileNames.count ?? 0
            guard syncedFileCount > 0 else {
                setSyncMemoryStatus("No Sync Memory destinations enabled")
                return
            }
            let noteNoun = syncedFileCount == 1 ? "note" : "notes"
            let destinationNoun = count == 1 ? "destination" : "destinations"
            setSyncMemoryStatus("Synced \(syncedFileCount) \(noteNoun) to \(count) \(destinationNoun)")
        } catch {
            setSyncMemoryStatus("Sync Memory failed: \(error.localizedDescription)")
        }
    }

    func saveKnowledgeImportConfig(_ config: KnowledgeImportConfig) {
        knowledgeImportConfig = config
        knowledgeImportConfig.save(to: userDefaults)
        refreshKnowledgeDocumentTree()
        do {
            try knowledgeImportLaunchAgentManager.knowledgeImportRegistration(
                executablePath: Bundle.main.executableURL?.path,
                hour: config.dailyImportHour,
                minute: config.dailyImportMinute,
                isEnabled: config.isImportEnabled
            )
            if config.isImportEnabled {
                let timeSummary = String(format: "%02d:%02d", config.dailyImportHour, config.dailyImportMinute)
                setKnowledgeImportStatus("Source scan enabled for \(timeSummary)")
            } else {
                setKnowledgeImportStatus("Source scan disabled")
            }
        } catch {
            setKnowledgeImportStatus("Source scan setup failed: \(error.localizedDescription)")
        }
    }

    private func queueInitialLinkedSourceScanIfNeeded() {
        guard knowledgeImportConfig.connectorInstances.contains(where: \.isEnabled),
              ProcessInfo.processInfo.arguments.contains("--import-knowledge-now") == false else {
            return
        }

        Task { @MainActor [weak self] in
            await self?.importKnowledgeNow()
        }
    }

    func saveKnowledgeImportBearerToken(_ token: String, connectorInstanceID: String) {
        KnowledgeImportCredentialStore(keychain: keychain, service: keychainService)
            .saveBearerToken(token, connectorInstanceID: connectorInstanceID)
    }

    func deleteKnowledgeImportBearerToken(connectorInstanceID: String) {
        KnowledgeImportCredentialStore(keychain: keychain, service: keychainService)
            .deleteBearerToken(connectorInstanceID: connectorInstanceID)
    }

    func importKnowledgeNow() async {
        guard let environment else {
            setKnowledgeImportStatus("Source scan unavailable")
            return
        }

        let connectors = makeKnowledgeImportConnectors(from: knowledgeImportConfig)
        guard !connectors.isEmpty else {
            setKnowledgeImportStatus("No linked sources enabled")
            return
        }

        let coordinator = KnowledgeImportCoordinator(
            store: KnowledgeImportStore(rootDirectory: environment.knowledgeSourcesDirectoryURL),
            databaseWriter: environment.databaseWriter,
            now: currentDate
        )
        let result = await coordinator.sync(connectors: connectors)
        let noun = result.changedDocumentCount == 1 ? "document" : "documents"
        setKnowledgeImportStatus("Refreshed \(result.changedDocumentCount) \(noun)")
        refreshKnowledgeDocumentTree()
        refreshVisibleKnowledgeSelectionAfterImport()
    }

    private func refreshVisibleKnowledgeSelectionAfterImport() {
        switch mainContentSelection {
        case .knowledgeConnector(let instanceID):
            guard knowledgeImportConfig.connectorInstances.contains(where: { $0.id == instanceID }) else {
                selectOtherSourceManager(focusAddConnector: false)
                return
            }
            selectedKnowledgeDocuments = fetchKnowledgeDocuments(connectorInstanceID: instanceID)
            selectedKnowledgeDocument = nil
            selectedKnowledgeDocumentMarkdown = nil
        case .knowledgeDocument(let connectorInstanceID, let documentID):
            guard knowledgeImportConfig.connectorInstances.contains(where: { $0.id == connectorInstanceID }) else {
                selectOtherSourceManager(focusAddConnector: false)
                return
            }

            let documents = fetchKnowledgeDocuments(connectorInstanceID: connectorInstanceID)
            selectedKnowledgeDocuments = documents
            if let document = documents.first(where: { $0.id == documentID }) {
                selectedKnowledgeDocument = document
                selectedKnowledgeDocumentMarkdown = loadKnowledgeDocumentMarkdown(document)
            } else {
                mainContentSelection = .knowledgeConnector(instanceID: connectorInstanceID)
                selectedKnowledgeDocument = documents.first
                selectedKnowledgeDocumentMarkdown = loadKnowledgeDocumentMarkdown(selectedKnowledgeDocument)
            }
        case .diary, .otherSourceManager:
            break
        }
    }

    private func normalizedSyncMemoryPath(_ path: String?) -> String? {
        guard let path else { return nil }
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func setSyncMemoryStatus(_ message: String) {
        syncMemoryStatusMessage = message
        statusMessage = message
    }

    private func setKnowledgeImportStatus(_ message: String) {
        knowledgeImportStatusMessage = message
        statusMessage = message
    }

    private func makeKnowledgeImportConnectors(from config: KnowledgeImportConfig) -> [any KnowledgeImportConnector] {
        return config.connectorInstances.compactMap { instance -> (any KnowledgeImportConnector)? in
            guard instance.isEnabled else {
                return nil
            }

            switch instance.connectorID {
            case .localFolderImport:
                guard let path = normalizedKnowledgeImportValue(instance.sourcePath) else {
                    return nil
                }
                return LocalFolderKnowledgeConnector(
                    connectorInstanceID: instance.id,
                    rootURL: URL(fileURLWithPath: path, isDirectory: true)
                )
            case .obsidianImport:
                guard let path = normalizedKnowledgeImportValue(instance.sourcePath) else {
                    return nil
                }
                return ObsidianKnowledgeConnector(
                    connectorInstanceID: instance.id,
                    vaultURL: URL(fileURLWithPath: path, isDirectory: true)
                )
            case .feishuImport:
                guard let path = normalizedKnowledgeImportValue(instance.sourcePath) else {
                    return nil
                }
                return FileBackedPlatformKnowledgeConnector(
                    connectorInstanceID: instance.id,
                    connectorID: .feishuImport,
                    rootURL: URL(fileURLWithPath: path, isDirectory: true)
                )
            case .notionImport:
                guard let path = normalizedKnowledgeImportValue(instance.sourcePath) else {
                    return nil
                }
                return FileBackedPlatformKnowledgeConnector(
                    connectorInstanceID: instance.id,
                    connectorID: .notionImport,
                    rootURL: URL(fileURLWithPath: path, isDirectory: true)
                )
            case .googleDriveImport:
                guard let path = normalizedKnowledgeImportValue(instance.sourcePath) else {
                    return nil
                }
                return FileBackedPlatformKnowledgeConnector(
                    connectorInstanceID: instance.id,
                    connectorID: .googleDriveImport,
                    rootURL: URL(fileURLWithPath: path, isDirectory: true)
                )
            case .obsidianExport, .openClawExport:
                return nil
            }
        }
    }

    private func normalizedKnowledgeImportValue(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func completeOnboarding(vaultURL: URL, preferredEngine: DiaryEngine) {
        applyVaultURL(vaultURL)

        var config = summarizerConfig
        config.defaultEngine = preferredEngine
        summarizerConfig = config
        defaultEngine = preferredEngine
        setAutoSelectionSuppressedByExplicitNone(preferredEngine == .none)
        persistSummarizerConfig()
        refreshEngineStatuses()
        statusMessage = preferredEngine == .none
            ? "Summarizer disabled"
            : "Default engine set to \(preferredEngine.displayName)"

        userDefaults.set(true, forKey: UserDefaultsKeys.hasCompletedOnboarding)
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
        Task { @MainActor [weak self] in
            await self?.refreshEndOfDayReminderAuthorizationStatus()
        }
    }

    func setEndOfDayReminderEnabled(_ isEnabled: Bool) async {
        endOfDayReminderConfig.isEnabled = isEnabled
        if isEnabled {
            let status = await endOfDayReminderService.requestAuthorization()
            endOfDayReminderConfig.authorizationStatus = status
            if status == .authorized {
                statusMessage = "Evening review reminder enabled"
            } else {
                statusMessage = "Evening review reminder is blocked until notifications are allowed"
            }
        } else {
            statusMessage = "Evening review reminder disabled"
            let today = ISO8601DayKey.format(currentDate())
            await endOfDayReminderService.cancelReminder(for: today)
            clearPendingReminder(for: today)
        }
        persistEndOfDayReminderConfig()
        syncEndOfDayReminderRegistration()
    }

    func refreshEndOfDayReminderAuthorizationStatus() async {
        let status = await endOfDayReminderService.authorizationStatus()
        guard endOfDayReminderConfig.authorizationStatus != status else { return }
        endOfDayReminderConfig.authorizationStatus = status
        persistEndOfDayReminderConfig()
        syncEndOfDayReminderRegistration()
    }

    func requestDailyReviewReminderAuthorization() async {
        let status = await endOfDayReminderService.requestAuthorization()
        endOfDayReminderConfig.authorizationStatus = status

        if status == .authorized {
            endOfDayReminderConfig.isEnabled = true
            statusMessage = "Daily review reminder enabled"
        } else {
            statusMessage = "Daily review reminder is blocked until notifications are allowed"
        }

        persistEndOfDayReminderConfig()
        syncEndOfDayReminderRegistration()
    }

    func sendTestEndOfDayReminderNow() async {
        let status = await endOfDayReminderService.requestAuthorization()
        endOfDayReminderConfig.authorizationStatus = status
        persistEndOfDayReminderConfig()

        guard status == .authorized else {
            statusMessage = "Evening review reminder is blocked until notifications are allowed"
            endOfDayReminderTestStatusMessage = "Notifications are blocked by macOS. Enable Know You in System Settings > Notifications."
            return
        }

        do {
            await endOfDayReminderService.cancelTestReminder()
            try await endOfDayReminderService.scheduleTestReminder(
                at: currentDate().addingTimeInterval(1),
                dayKey: ISO8601DayKey.format(currentDate())
            )
            statusMessage = "Sent a test evening review reminder"
            endOfDayReminderTestStatusMessage = "Test reminder sent. It should appear in about a second."
        } catch {
            statusMessage = "Evening review reminder unavailable: \(error.localizedDescription)"
            endOfDayReminderTestStatusMessage = "Unable to send the test reminder: \(error.localizedDescription)"
        }
    }

    func dayReviewState(for dayKey: String) -> DayReviewState? {
        dayReviewStates[dayKey]
    }

    func setPersistedDayReviewState(_ state: DayReviewState) {
        dayReviewStates[state.dayKey] = state
        persistDayReviewStates()
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
        reconcileDefaultEngineAfterStatusChange()
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

        reconcileDefaultEngineAfterStatusChange()
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
        if engine == defaultEngine, result.state == .green {
            refreshActiveSummarizer()
        }
        reconcileDefaultEngineAfterStatusChange()
        retestingEngines.remove(engine)
        isRetestingEngines = !retestingEngines.isEmpty
    }

    func testLLMAPIProvider(
        _ providerID: LLMAPIProviderID,
        draftConfig: SummarizerConfig
    ) async -> EngineRuntimeStatus {
        var configSnapshot = draftConfig
        configSnapshot.defaultEngine = .llmAPI
        configSnapshot.activeLLMAPIProviderID = providerID
        let configurationSignature = Self.configurationSignature(
            for: .llmAPI,
            config: configSnapshot,
            environment: processEnvironment
        )
        let result = await probeEngine(.llmAPI, configSnapshot, processEnvironment)
        let status = EngineRuntimeStatus(
            state: result.state,
            detail: result.detail,
            lastVerifiedAt: result.verifiedAt,
            configurationSignature: configurationSignature
        )

        if providerID == summarizerConfig.activeLLMAPIProviderID,
           Self.configurationSignature(
            for: .llmAPI,
            config: summarizerConfig,
            environment: processEnvironment
           ) == configurationSignature {
            engineStatuses[.llmAPI] = status
            if defaultEngine == .llmAPI, result.state == .green {
                refreshActiveSummarizer()
            }
            reconcileDefaultEngineAfterStatusChange()
        }

        return status
    }

    func selectDefaultEngine(_ engine: DiaryEngine) {
        defaultEngine = engine
        summarizerConfig.defaultEngine = engine
        setAutoSelectionSuppressedByExplicitNone(engine == .none)
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
                : "Saved \(requestedEngine.displayName) settings; \(defaultEngine.displayName) remains active"
    }

    private func reconcileDefaultEngineAfterStatusChange() {
        guard defaultEngine == .none, !autoSelectionSuppressedByExplicitNone else { return }
        guard let preferred = Self.autoSelectionPriority.first(where: { engineStatuses[$0]?.state == .green }) else {
            return
        }

        selectDefaultEngine(preferred)
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

        return "Last run: \(lastRunText) · Notifications: \(lastImportedNotificationCount) · History refresh is manual-only"
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
        static let onboardingProgressState = "onboardingProgressState"
        static let onboardingBootstrapState = "onboardingBootstrapState"
        static let onboardingBootstrapDayKeys = "onboardingBootstrapDayKeys"
        static let lastNotificationImportAt = "lastNotificationImportAt"
        static let lastNotificationImportDatabasePath = "lastNotificationImportDatabasePath"
        static let explicitlyDisabledSummarizerAutoSelection = "explicitlyDisabledSummarizerAutoSelection"
        static let lastUpdateCheckAt = "lastUpdateCheckAt"
        static let launchAtLoginDefaultRegistrationAttempted = "launchAtLoginDefaultRegistrationAttempted"
        static let dayReviewStates = "dayReviewStates"
    }

    private static func loadDayReviewStates(from userDefaults: UserDefaults) -> [String: DayReviewState] {
        guard
            let data = userDefaults.data(forKey: UserDefaultsKeys.dayReviewStates),
            let decoded = try? JSONDecoder().decode([String: DayReviewState].self, from: data)
        else {
            return [:]
        }
        return decoded
    }

    var currentOnboardingStep: OnboardingStep? {
        onboardingProgress.currentStep
    }

    var shouldShowOnboarding: Bool {
        !onboardingProgress.isComplete
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

    func resumeOnboardingStep(_ step: OnboardingStep) {
        guard !onboardingProgress.isComplete else { return }
        setOnboardingProgress(OnboardingProgress(step: step))
    }

    func restoreOnboardingProgress(
        isFullDiskAccessReady: Bool,
        isEngineReady: Bool,
        hasVoiceTool _: Bool = false,
        hasLaunchAtLogin _: Bool = false,
        allowsFullDiskAccessBypass: Bool = false
    ) {
        guard !onboardingProgress.isComplete else { return }
        setOnboardingProgress(
            onboardingProgress.restored(
                isFullDiskAccessReady: isFullDiskAccessReady,
                isEngineReady: isEngineReady,
                allowsFullDiskAccessBypass: allowsFullDiskAccessBypass
            )
        )
    }

    func completeOnboarding() {
        setOnboardingProgress(OnboardingProgress(state: .complete))
        restoreLiveReaderPresentationAfterOnboarding()
        queueOnboardingBootstrapIfNeeded()
        if automationTimer == nil, environment != nil {
            startAutomation(runImmediately: false)
        }
        resumeOnboardingBootstrapIfNeeded()
        syncEndOfDayReminderRegistration()
    }

    func markOnboardingBootstrapComplete() {
        onboardingBootstrapState = .complete
        onboardingBootstrapDayKeys = []
        dismissOnboardingBootstrapNotice()
        persistOnboardingBootstrapState()
    }

    func dismissOnboardingBootstrapNotice() {
        onboardingBootstrapNoticeDismissTask?.cancel()
        onboardingBootstrapNoticeDismissTask = nil
        onboardingBootstrapNotice = nil
    }

    private func setOnboardingProgress(_ progress: OnboardingProgress) {
        guard onboardingProgress != progress else { return }
        onboardingProgress = progress
        persistOnboardingProgress()
    }

    private func persistOnboardingProgress() {
        userDefaults.set(onboardingProgress.state.rawValue, forKey: UserDefaultsKeys.onboardingProgressState)
        userDefaults.set(onboardingProgress.isComplete, forKey: UserDefaultsKeys.hasCompletedOnboarding)
    }

    private func persistOnboardingBootstrapState() {
        userDefaults.set(onboardingBootstrapState.rawValue, forKey: UserDefaultsKeys.onboardingBootstrapState)
        userDefaults.set(onboardingBootstrapDayKeys, forKey: UserDefaultsKeys.onboardingBootstrapDayKeys)
    }

    private static func loadOnboardingProgress(from userDefaults: UserDefaults) -> OnboardingProgress {
        if let rawValue = userDefaults.string(forKey: UserDefaultsKeys.onboardingProgressState),
           let state = OnboardingProgressState(rawValue: rawValue) {
            return OnboardingProgress(state: state)
        }

        if let legacyValue = userDefaults.string(forKey: UserDefaultsKeys.onboardingProgressState) {
            switch legacyValue {
            case "demoPending":
                return OnboardingProgress(state: .demoReadPending)
            case "referencePending":
                return OnboardingProgress(state: .demoReferencePending)
            case "privacyPending":
                return OnboardingProgress(state: .privacyPending)
            case "permissionsPending":
                return OnboardingProgress(state: .permissionsPending)
            case "enginePending":
                return OnboardingProgress(state: .enginePromptPending)
            case "generatingPending":
                return OnboardingProgress(state: .firstGenerationInProgress)
            case "complete":
                return OnboardingProgress(state: .complete)
            default:
                break
            }
        }

        if userDefaults.bool(forKey: UserDefaultsKeys.hasCompletedOnboarding) {
            return OnboardingProgress(state: .complete)
        }

        return OnboardingProgress()
    }

    private static func loadOnboardingBootstrapState(from userDefaults: UserDefaults) -> OnboardingBootstrapState {
        guard
            let rawValue = userDefaults.string(forKey: UserDefaultsKeys.onboardingBootstrapState),
            let state = OnboardingBootstrapState(rawValue: rawValue)
        else {
            return .idle
        }

        return state
    }

    private static func loadOnboardingBootstrapDayKeys(from userDefaults: UserDefaults) -> [String] {
        guard let values = userDefaults.array(forKey: UserDefaultsKeys.onboardingBootstrapDayKeys) as? [String] else {
            return []
        }
        return values
    }

    private static func onboardingBootstrapDays(now: Date) -> [String] {
        let calendar = Calendar(identifier: .gregorian)
        return (0..<2).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: now) else { return nil }
            return ISO8601DayKey.format(date)
        }
    }

    private func queueOnboardingBootstrapIfNeeded() {
        guard onboardingBootstrapState != .complete else { return }

        onboardingBootstrapState = .pending
        onboardingBootstrapDayKeys = Self.onboardingBootstrapDays(now: currentDate())
        persistOnboardingBootstrapState()
        rebuildAvailableDates()
        showOnboardingBootstrapNotice()
    }

    private func resumeOnboardingBootstrapIfNeeded() {
        guard environment != nil else { return }
        guard onboardingBootstrapState == .pending || onboardingBootstrapState == .inProgress else { return }
        guard onboardingBootstrapTask == nil else { return }

        if onboardingBootstrapDayKeys.isEmpty {
            onboardingBootstrapDayKeys = Self.onboardingBootstrapDays(now: currentDate())
            persistOnboardingBootstrapState()
        }

        onboardingBootstrapState = .inProgress
        persistOnboardingBootstrapState()
        rebuildAvailableDates()

        onboardingBootstrapTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.onboardingBootstrapTask = nil }

            var completedDayKeys = self.onboardingBootstrapDayKeys.filter { self.noteIndex[$0] != nil }
            for dayKey in self.onboardingBootstrapDayKeys where completedDayKeys.contains(dayKey) == false {
                let didComplete = await self.generateOnboardingBootstrapNote(for: dayKey)
                if didComplete {
                    completedDayKeys.append(dayKey)
                }
            }

            let shouldNotifyCompletion =
                completedDayKeys.isEmpty == false
                && completedDayKeys.count == self.onboardingBootstrapDayKeys.count

            self.markOnboardingBootstrapComplete()
            self.rebuildAvailableDates()
            if shouldNotifyCompletion {
                self.notifyOnboardingBootstrapCompletion(completedDayKeys)
            }
        }
    }

    private static func bootstrapSyncMemoryConfigIfNeeded(
        startingFrom initialConfig: SyncMemoryConfig,
        userDefaults: UserDefaults
    ) -> SyncMemoryConfig {
        var config = initialConfig
        let detector = SyncMemoryPathDetector()
        let fileManager = FileManager.default
        let homeURL = fileManager.homeDirectoryForCurrentUser

        if !config.obsidian.isEnabled,
           config.obsidian.resolvedPath?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            let configuredVaults = detector.detectConfiguredObsidianVaults(
                configDirectory: detector.defaultObsidianConfigDirectory(homePath: homeURL.path)
            )
            let searchRoots = [
                homeURL.appendingPathComponent("Documents", isDirectory: true),
                homeURL,
            ].filter { fileManager.fileExists(atPath: $0.path) }

            if let vault = (configuredVaults + detector.detectObsidianVaults(searchRoots: searchRoots)).first {
                config.obsidian.resolvedPath = vault
                    .appendingPathComponent("KnowYou", isDirectory: true)
                    .appendingPathComponent("Daily Memories", isDirectory: true)
                    .path
                config.obsidian.isEnabled = true
                config.obsidian.lastDetectionSummary = "Detected Obsidian vault"
            }
        }

        if !config.openClaw.isEnabled,
           config.openClaw.resolvedPath?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            let workspace = detector.defaultOpenClawWorkspace(homePath: homeURL.path)
            if fileManager.fileExists(atPath: workspace.path) {
                config.openClaw.resolvedPath = detector.openClawMemoryDirectory(for: workspace).path
                config.openClaw.isEnabled = true
                config.openClaw.lastDetectionSummary = "Detected OpenClaw workspace"
            }
        }

        if config != initialConfig {
            config.save(to: userDefaults)
        }
        return config
    }

    func runAutomation(now: Date = Date()) async {
        guard let environment else {
            statusMessage = "Capture unavailable"
            return
        }

        lastAutomationRunAt = now
        refreshNotesIndex()
        let today = ISO8601DayKey.format(now)
        let todayStory = (try? environment.loadDailyStory(dayKey: today)) ?? nil
        let todayRefreshAction = environment.dailyAutomationPlanner.todayRefreshAction(
            todayStory: todayStory,
            hasVerifiedSummarizer: environment.summarizer != nil
        )
        let notificationSince = Self.startOfDay(for: today) ?? now
        updateNotificationAccessStatus(using: environment.notificationReader)

        do {
            let importResult = try environment.notificationCollector.importDeliveredNotifications(since: notificationSince)
            lastImportedNotificationCount = importResult.importedCount
            if shouldPersistNotificationWatermark(for: importResult) {
                persistLastNotificationImportAt(now, databasePath: environment.databaseURL.path)
            }
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
        pendingBackfillDays = []

        if let todayRefreshAction {
            let refreshStartedAt = Date()
            let refreshLog = RefreshLogBuffer(
                record: RefreshLogRecord(
                    dayKey: today,
                    trigger: .automation,
                    mode: todayRefreshAction == .incremental ? "incrementalUpdate" : "fullRecovery",
                    startedAt: refreshStartedAt,
                    notificationImportedCount: lastImportedNotificationCount,
                    notificationError: notificationStatus.lastError
                )
            )
            switch todayRefreshAction {
            case .incremental:
                _ = await incrementallyRefreshDay(
                    dayKey: today,
                    recordsRun: true,
                    now: now,
                    environment: environment,
                    trigger: .automation,
                    refreshLog: refreshLog
                )
            case .fullRecovery:
                _ = await refreshDayWithRetry(
                    dayKey: today,
                    recordsRun: true,
                    now: now,
                    environment: environment,
                    trigger: .automation,
                    refreshLog: refreshLog
                )
            }
            refreshLog.record.finishedAt = Date()
            refreshLog.record.totalDurationSeconds = refreshLog.record.finishedAt?.timeIntervalSince(refreshStartedAt)
            refreshLog.record.finalStatus = dayRefreshStatus.lastError == nil ? "completed" : "failed"
            refreshLog.record.finalSummary = dayRefreshStatus.detail ?? dayRefreshStatus.lastError
            persistRefreshLog(refreshLog.record, environment: environment)
        }

        if let lastError = notificationStatus.lastError {
            statusMessage = "Refresh completed with notification issue: \(lastError)"
        } else if todayRefreshAction != nil, let detail = dayRefreshStatus.detail, detail.contains(today) {
            statusMessage = detail
        } else if todayRefreshAction == nil, todayStory?.provenance?.generationMode != .model {
            statusMessage = "Configure and verify an engine to generate today's journal"
        } else {
            statusMessage = lastImportedNotificationCount == 0
                ? "Capture services ready"
                : "Imported \(lastImportedNotificationCount) notifications"
        }
    }

    func runNotificationCatchUp(now: Date = Date()) async {
        guard let environment else {
            statusMessage = "Capture unavailable"
            return
        }

        let calendar = Calendar(identifier: .gregorian)
        let todayStart = calendar.startOfDay(for: now)
        let baseline = lastNotificationImportAt ?? todayStart
        let importStart = max(todayStart, baseline.addingTimeInterval(-notificationOverlapBuffer))
        updateNotificationAccessStatus(using: environment.notificationReader)

        do {
            let result = try environment.notificationCollector.importDeliveredNotifications(
                from: importStart,
                through: now
            )
            applyNotificationAccessStatus(result.accessStatus)
            lastImportedNotificationCount = result.importedCount
            if shouldPersistNotificationWatermark(for: result) {
                persistLastNotificationImportAt(now, databasePath: environment.databaseURL.path)
            }
            notificationStatus.lastImportedAt = result.importedAt
            notificationStatus.lastImportedCount = result.importedCount
            if notificationStatus.isDatabaseAvailable {
                notificationStatus.lastError = nil
            }
        } catch {
            applyNotificationAccessStatus(environment.notificationCollector.accessStatus())
            lastImportedNotificationCount = 0
            notificationStatus.lastImportedAt = Date()
            notificationStatus.lastImportedCount = 0
            notificationStatus.lastError = error.localizedDescription
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

    func refreshDay(
        _ dayKey: String,
        now: Date,
        environment: AppEnvironment,
        trigger: RefreshTrigger = .manual,
        forcedMode: DayRefreshMode? = nil,
        chunkedFullRefreshContext: ChunkedFullRefreshContext? = nil
    ) async {
        guard refreshTasksByDay[dayKey] == nil else {
            return
        }
        guard refreshTasksByDay.count < maxConcurrentRefreshes else {
            statusMessage = "Two refreshes are already running"
            return
        }

        transitionRefreshJob(for: dayKey, stage: .syncingNotifications)
        let task = Task { @MainActor in
            await performRefreshDay(
                dayKey,
                now: now,
                environment: environment,
                trigger: trigger,
                forcedMode: forcedMode,
                chunkedFullRefreshContext: chunkedFullRefreshContext
            )
        }
        refreshTasksByDay[dayKey] = task
        _ = await task.value
    }

    private func performRefreshDay(
        _ dayKey: String,
        now: Date,
        environment: AppEnvironment,
        trigger: RefreshTrigger,
        forcedMode: DayRefreshMode?,
        chunkedFullRefreshContext: ChunkedFullRefreshContext?
    ) async -> Bool {
        defer {
            refreshTasksByDay.removeValue(forKey: dayKey)
        }

        let refreshStartedAt = Date()
        let refreshLog = RefreshLogBuffer(
            record: RefreshLogRecord(
                dayKey: dayKey,
                trigger: trigger,
                mode: "unknown",
                startedAt: refreshStartedAt
            )
        )

        let notificationStartedAt = Date()
        let syncOutcome = syncNotifications(for: dayKey, now: now, environment: environment)
        refreshLog.record.notificationImportedCount = syncOutcome.importedCount
        refreshLog.record.notificationError = syncOutcome.error
        refreshLog.record.stages.append(
            RefreshLogStageRecord(
                name: "syncingNotifications",
                durationSeconds: Date().timeIntervalSince(notificationStartedAt),
                detail: syncOutcome.error ?? "Imported \(syncOutcome.importedCount) notification(s)"
            )
        )
        let mode: DayRefreshMode
        if let forcedMode {
            mode = forcedMode
        } else {
            do {
                mode = try refreshMode(for: dayKey, environment: environment)
            } catch {
                dayRefreshStatus.lastRequestedDay = dayKey
                dayRefreshStatus.lastRefreshedAt = Date()
                dayRefreshStatus.lastError = error.localizedDescription
                statusMessage = "Daily note failed: \(error.localizedDescription)"
                refreshLog.record.finishedAt = Date()
                refreshLog.record.totalDurationSeconds = refreshLog.record.finishedAt?.timeIntervalSince(refreshStartedAt)
                refreshLog.record.finalStatus = "failed"
                refreshLog.record.finalSummary = error.localizedDescription
                persistRefreshLog(refreshLog.record, environment: environment)
                transitionRefreshJob(
                    for: dayKey,
                    stage: .failed,
                    detail: "Failed · \(error.localizedDescription)",
                    error: error.localizedDescription
                )
                return false
            }
        }
        refreshLog.record.mode = mode == .fullRecovery ? "fullRecovery" : "incrementalUpdate"
        let noteResult: DayRefreshGenerationResult
        if let chunkedFullRefreshContext,
           mode == .fullRecovery,
           let chunkedResult = await performChunkedFullRefreshIfNeeded(
                dayKey: dayKey,
                now: now,
                environment: environment,
                trigger: trigger,
                context: chunkedFullRefreshContext,
                refreshLog: refreshLog,
                onStageChange: { [weak self] stage, detail in
                    self?.transitionRefreshJob(for: dayKey, stage: stage, detail: detail)
                }
           ) {
            noteResult = chunkedResult
        } else {
            switch mode {
            case .fullRecovery:
                noteResult = await refreshDayWithRetry(
                    dayKey: dayKey,
                    recordsRun: true,
                    now: now,
                    environment: environment,
                    trigger: trigger,
                    refreshLog: refreshLog,
                    onStageChange: { [weak self] stage, detail in
                        self?.transitionRefreshJob(for: dayKey, stage: stage, detail: detail)
                    }
                )
            case .incrementalUpdate:
                noteResult = await incrementallyRefreshDay(
                    dayKey: dayKey,
                    recordsRun: true,
                    now: now,
                    environment: environment,
                    trigger: trigger,
                    refreshLog: refreshLog,
                    onStageChange: { [weak self] stage, detail in
                        self?.transitionRefreshJob(for: dayKey, stage: stage, detail: detail)
                    }
                )
            }
        }
        guard noteResult.stage == .completed else {
            refreshLog.record.finishedAt = Date()
            refreshLog.record.totalDurationSeconds = refreshLog.record.finishedAt?.timeIntervalSince(refreshStartedAt)
            refreshLog.record.finalStatus = "failed"
            refreshLog.record.finalSummary = dayRefreshStatus.lastRequestedDay == dayKey ? dayRefreshStatus.lastError : "Unknown error"
            persistRefreshLog(refreshLog.record, environment: environment)
            transitionRefreshJob(
                for: dayKey,
                stage: .failed,
                detail: "Failed · \(dayRefreshStatus.lastRequestedDay == dayKey ? (dayRefreshStatus.lastError ?? "Unknown error") : "Unknown error")",
                error: dayRefreshStatus.lastRequestedDay == dayKey ? dayRefreshStatus.lastError : nil
            )
            return false
        }

        let completionDetail: String
        let storySummary = noteResult.summary
        if dayKey == ISO8601DayKey.format(now) {
            if let error = syncOutcome.error {
                statusMessage = "Refreshed today without notifications: \(error)"
                completionDetail = "Completed · \(storySummary) · notification sync failed"
            } else if syncOutcome.importedCount == 0 {
                statusMessage = "Refreshed today with no new notifications"
                completionDetail = "Completed · \(storySummary)"
            } else {
                statusMessage = "Imported \(syncOutcome.importedCount) notifications and refreshed today"
                completionDetail = "Completed · \(storySummary)"
            }
        } else if let error = syncOutcome.error {
            statusMessage = "Refreshed \(dayKey) without notifications: \(error)"
            completionDetail = "Completed · \(storySummary) · notification sync failed"
        } else {
            statusMessage = syncOutcome.importedCount > 0
                ? "Refreshed \(dayKey) after syncing notifications"
                : "Refreshed \(dayKey)"
            completionDetail = "Completed · \(storySummary)"
        }
        refreshLog.record.finishedAt = Date()
        refreshLog.record.totalDurationSeconds = refreshLog.record.finishedAt?.timeIntervalSince(refreshStartedAt)
        refreshLog.record.finalStatus = "completed"
        refreshLog.record.finalSummary = completionDetail
        persistRefreshLog(refreshLog.record, environment: environment)
        transitionRefreshJob(for: dayKey, stage: .completed, detail: completionDetail)
        return true
    }

    private func generateOnboardingBootstrapNote(for dayKey: String) async -> Bool {
        guard let environment else {
            statusMessage = "Capture unavailable"
            return false
        }
        if noteIndex[dayKey] != nil {
            return true
        }
        guard refreshTasksByDay[dayKey] == nil else {
            return false
        }
        guard refreshTasksByDay.count < maxConcurrentRefreshes else {
            statusMessage = "Two refreshes are already running"
            return false
        }

        transitionRefreshJob(for: dayKey, stage: .syncingNotifications)
        let task = Task { @MainActor in
            await performRefreshDay(
                dayKey,
                now: currentDate(),
                environment: environment,
                trigger: .manual,
                forcedMode: nil,
                chunkedFullRefreshContext: .onboardingBootstrap
            )
        }
        refreshTasksByDay[dayKey] = task
        return await task.value
    }

    private func performChunkedFullRefreshIfNeeded(
        dayKey: String,
        now: Date,
        environment: AppEnvironment,
        trigger: RefreshTrigger,
        context: ChunkedFullRefreshContext,
        refreshLog: RefreshLogBuffer,
        onStageChange: ((DayRefreshStage, String?) -> Void)?
    ) async -> DayRefreshGenerationResult? {
        let allEvents = (try? environment.databaseWriter.fetchEvents(dayKey: dayKey))?
            .sorted { $0.capturedAt < $1.capturedAt } ?? []
        guard allEvents.count > refreshEventBatchSize else {
            return nil
        }
        onStageChange?(.loadingEvents, "Loaded \(allEvents.count) event(s)")

        let chunkedResult = await refreshDayInChunks(
            dayKey: dayKey,
            allEvents: allEvents,
            now: now,
            environment: environment,
            trigger: trigger,
            context: context,
            refreshLog: refreshLog,
            onStageChange: onStageChange
        )
        return chunkedResult
    }

    private func refreshDayInChunks(
        dayKey: String,
        allEvents: [EventRecord],
        now: Date,
        environment: AppEnvironment,
        trigger: RefreshTrigger,
        context: ChunkedFullRefreshContext,
        refreshLog: RefreshLogBuffer,
        onStageChange: ((DayRefreshStage, String?) -> Void)?
    ) async -> DayRefreshGenerationResult {
        let attempts = refreshAttempts(trigger: trigger, using: environment)
        guard !attempts.isEmpty else {
            return failFullRecoveryWithoutVerifiedEngine(dayKey: dayKey)
        }

        let runID = try? environment.databaseWriter.startRun(runType: "daily-note", dayKey: dayKey)
        let chunks = stride(from: 0, to: allEvents.count, by: refreshEventBatchSize).map { startIndex in
            Array(allEvents[startIndex..<min(startIndex + refreshEventBatchSize, allEvents.count)])
        }
        refreshLog.record.totalEventCount = allEvents.count
        refreshLog.record.stages.append(
            RefreshLogStageRecord(
                name: "chunkingPlan",
                durationSeconds: 0,
                detail: "Chunked \(context.logLabel) into \(chunks.count) batch(es) of up to \(refreshEventBatchSize) event(s)"
            )
        )

        let invocationContext = summaryInvocationContext(for: trigger)
        var cumulativeEvents: [EventRecord] = []
        var existingStory: DailyStory?
        var latestFileURL: URL?

        do {
            for (index, chunk) in chunks.enumerated() {
                cumulativeEvents.append(contentsOf: chunk)
                let chunkNumber = index + 1
                let chunkLabel = "chunk \(chunkNumber)/\(chunks.count)"
                let cumulativeCount = cumulativeEvents.count

                refreshLog.record.newEventCount = chunk.count
                refreshLog.record.stages.append(
                    RefreshLogStageRecord(
                        name: "loadingEvents",
                        durationSeconds: 0,
                        detail: "\(chunkLabel) loaded \(chunk.count) event(s); \(cumulativeCount)/\(allEvents.count) cumulative"
                    )
                )

                let detailPrefix = index == 0
                    ? "Preparing \(chunkLabel) from \(chunk.count) event(s)..."
                    : "Appending \(chunkLabel) with \(chunk.count) event(s); \(cumulativeCount)/\(allEvents.count) cumulative..."
                onStageChange?(.preparingStory, detailPrefix)

                let result: DayRefreshGenerationResult
                if index == 0 {
                    result = try await runChunkedFullRefreshFullChunk(
                        dayKey: dayKey,
                        chunkLabel: chunkLabel,
                        chunkIndex: chunkNumber,
                        chunkCount: chunks.count,
                        events: cumulativeEvents,
                        now: now,
                        environment: environment,
                        attempts: attempts,
                        trigger: trigger,
                        context: context,
                        invocationContext: invocationContext,
                        refreshLog: refreshLog,
                        onStageChange: onStageChange,
                        persistedStory: &existingStory,
                        latestFileURL: &latestFileURL
                    )
                } else {
                    guard let currentStory = existingStory else {
                        if let runID {
                            try? environment.databaseWriter.finishRun(id: runID, status: "failed")
                        }
                        dayRefreshStatus.lastRequestedDay = dayKey
                        dayRefreshStatus.lastRefreshedAt = Date()
                        dayRefreshStatus.lastError = context.missingStoryError
                        statusMessage = "Daily note failed: \(context.missingStoryError)"
                        return DayRefreshGenerationResult(stage: .failed, summary: "Failed")
                    }

                    result = try await runChunkedFullRefreshIncrementalChunk(
                        dayKey: dayKey,
                        chunkLabel: chunkLabel,
                        chunkIndex: chunkNumber,
                        chunkCount: chunks.count,
                        existingStory: currentStory,
                        newEvents: chunk,
                        cumulativeEvents: cumulativeEvents,
                        now: now,
                        environment: environment,
                        attempts: attempts,
                        trigger: trigger,
                        context: context,
                        invocationContext: invocationContext,
                        refreshLog: refreshLog,
                        onStageChange: onStageChange,
                        persistedStory: &existingStory,
                        latestFileURL: &latestFileURL
                    )
                }

                guard result.stage == .completed else {
                    if let runID {
                        try? environment.databaseWriter.finishRun(id: runID, status: "failed")
                    }
                    return result
                }
            }

            if let runID {
                try environment.databaseWriter.finishRun(id: runID, status: "succeeded")
            }

            guard let story = existingStory, let fileURL = latestFileURL else {
                dayRefreshStatus.lastRequestedDay = dayKey
                dayRefreshStatus.lastRefreshedAt = Date()
                dayRefreshStatus.lastError = "Chunked \(context.logLabel) produced no story"
                statusMessage = "Daily note failed: Chunked \(context.logLabel) produced no story"
                return DayRefreshGenerationResult(stage: .failed, summary: "Failed")
            }

            await finalizeSuccessfulRefresh(
                dayKey: dayKey,
                story: story,
                events: cumulativeEvents,
                fileURL: fileURL,
                detail: "Completed \(context.logLabel) in \(chunks.count) chunk(s) for \(dayKey)"
            )
            if let storyPath = storyURL(for: dayKey, environment: environment) {
                refreshLog.record.storyJSONPath = storyPath.path
            }
            refreshLog.record.markdownPath = fileURL.path
            refreshLog.record.wroteMarkdown = true
            refreshLog.record.wroteStoryJSON = true
            statusMessage = context.completionStatusMessage(for: dayKey, now: now)
            return DayRefreshGenerationResult(stage: .completed, summary: context.resultSummary)
        } catch {
            if let runID {
                try? environment.databaseWriter.finishRun(id: runID, status: "failed")
            }
            dayRefreshStatus.lastRequestedDay = dayKey
            dayRefreshStatus.lastRefreshedAt = Date()
            dayRefreshStatus.lastError = error.localizedDescription
            statusMessage = "Daily note failed: \(error.localizedDescription)"
            return DayRefreshGenerationResult(stage: .failed, summary: "Failed")
        }
    }

    private func runChunkedFullRefreshFullChunk(
        dayKey: String,
        chunkLabel: String,
        chunkIndex: Int,
        chunkCount: Int,
        events: [EventRecord],
        now: Date,
        environment: AppEnvironment,
        attempts: [RefreshSummarizerAttempt],
        trigger: RefreshTrigger,
        context: ChunkedFullRefreshContext,
        invocationContext: SummaryInvocationContext,
        refreshLog: RefreshLogBuffer,
        onStageChange: ((DayRefreshStage, String?) -> Void)?,
        persistedStory: inout DailyStory?,
        latestFileURL: inout URL?
    ) async throws -> DayRefreshGenerationResult {
        let prompt = environment.composer.storyPrompt(dayKey: dayKey, events: events)
        if trigger == .manual, let primaryAttempt = attempts.first {
            onStageChange?(.generatingStory, "Calling \(primaryAttempt.label) for \(chunkLabel)...")
            if let story = validateFullRecoveryResult(
                await runAttempt(
                    primaryAttempt,
                    dayKey: dayKey,
                    prompt: prompt,
                    context: invocationContext
                ),
                dayKey: dayKey,
                events: events,
                environment: environment,
                trigger: trigger,
                refreshLog: refreshLog
            ) {
                let fileURL = try await persistChunkedFullRefreshChunk(
                    dayKey: dayKey,
                    chunkLabel: chunkLabel,
                    chunkIndex: chunkIndex,
                    chunkCount: chunkCount,
                    story: story,
                    events: events,
                    environment: environment,
                    context: context,
                    refreshLog: refreshLog,
                    onStageChange: onStageChange
                )
                persistedStory = story
                latestFileURL = fileURL
                return DayRefreshGenerationResult(stage: .completed, summary: chunkLabel)
            }
        }

        let fallbackAttempts = trigger == .manual ? Array(attempts.dropFirst()) : attempts
        if !fallbackAttempts.isEmpty {
            let attemptDetail: String
            if trigger == .manual, !Array(attempts.dropFirst()).isEmpty {
                attemptDetail = "Default engine failed for \(chunkLabel). Trying \(fallbackAttempts.map(\.label).joined(separator: ", ")) in parallel..."
            } else {
                attemptDetail = "Calling \(fallbackAttempts[0].label) for \(chunkLabel)..."
            }
            onStageChange?(.generatingStory, attemptDetail)

            let results = trigger == .manual
                ? await runParallelAttempts(
                    fallbackAttempts,
                    dayKey: dayKey,
                    prompt: prompt,
                    context: invocationContext
                )
                : [await runAttempt(
                    fallbackAttempts[0],
                    dayKey: dayKey,
                    prompt: prompt,
                    context: invocationContext
                )]

            for result in results {
                guard let story = validateFullRecoveryResult(
                    result,
                    dayKey: dayKey,
                    events: events,
                    environment: environment,
                    trigger: trigger,
                    refreshLog: refreshLog
                ) else {
                    continue
                }
                let fileURL = try await persistChunkedFullRefreshChunk(
                    dayKey: dayKey,
                    chunkLabel: chunkLabel,
                    chunkIndex: chunkIndex,
                    chunkCount: chunkCount,
                    story: story,
                    events: events,
                    environment: environment,
                    context: context,
                    refreshLog: refreshLog,
                    onStageChange: onStageChange
                )
                persistedStory = story
                latestFileURL = fileURL
                return DayRefreshGenerationResult(stage: .completed, summary: chunkLabel)
            }
        }

        dayRefreshStatus.lastRequestedDay = dayKey
        dayRefreshStatus.lastRefreshedAt = Date()
        dayRefreshStatus.lastError = context.chunkFailureError(for: chunkLabel)
        statusMessage = "Daily note failed: \(context.chunkFailureError(for: chunkLabel))"
        return DayRefreshGenerationResult(stage: .failed, summary: "Failed")
    }

    private func runChunkedFullRefreshIncrementalChunk(
        dayKey: String,
        chunkLabel: String,
        chunkIndex: Int,
        chunkCount: Int,
        existingStory: DailyStory,
        newEvents: [EventRecord],
        cumulativeEvents: [EventRecord],
        now: Date,
        environment: AppEnvironment,
        attempts: [RefreshSummarizerAttempt],
        trigger: RefreshTrigger,
        context: ChunkedFullRefreshContext,
        invocationContext: SummaryInvocationContext,
        refreshLog: RefreshLogBuffer,
        onStageChange: ((DayRefreshStage, String?) -> Void)?,
        persistedStory: inout DailyStory?,
        latestFileURL: inout URL?
    ) async throws -> DayRefreshGenerationResult {
        let prompt = environment.composer.incrementalPrompt(
            dayKey: dayKey,
            existingStory: existingStory,
            newEvents: newEvents,
            allEvents: cumulativeEvents
        )

        if trigger == .manual, let primaryAttempt = attempts.first {
            onStageChange?(.generatingStory, "Appending \(chunkLabel) with \(primaryAttempt.label)...")
            if let mergedStory = validateIncrementalResult(
                await runIncrementalAttempt(
                    primaryAttempt,
                    dayKey: dayKey,
                    prompt: prompt,
                    context: invocationContext
                ),
                dayKey: dayKey,
                existingStory: existingStory,
                events: cumulativeEvents,
                newEvents: newEvents,
                environment: environment,
                trigger: trigger,
                refreshLog: refreshLog
            ) {
                let fileURL = try await persistChunkedFullRefreshChunk(
                    dayKey: dayKey,
                    chunkLabel: chunkLabel,
                    chunkIndex: chunkIndex,
                    chunkCount: chunkCount,
                    story: mergedStory,
                    events: cumulativeEvents,
                    environment: environment,
                    context: context,
                    refreshLog: refreshLog,
                    onStageChange: onStageChange
                )
                persistedStory = mergedStory
                latestFileURL = fileURL
                return DayRefreshGenerationResult(stage: .completed, summary: chunkLabel)
            }
        }

        let fallbackAttempts = trigger == .manual ? Array(attempts.dropFirst()) : attempts
        if !fallbackAttempts.isEmpty {
            let attemptDetail: String
            if trigger == .manual, !Array(attempts.dropFirst()).isEmpty {
                attemptDetail = "Default engine failed for \(chunkLabel). Trying \(fallbackAttempts.map(\.label).joined(separator: ", ")) in parallel..."
            } else {
                attemptDetail = "Appending \(chunkLabel) with \(fallbackAttempts[0].label)..."
            }
            onStageChange?(.generatingStory, attemptDetail)

            let mergedStory = trigger == .manual
                ? await firstValidParallelIncrementalStory(
                    fallbackAttempts,
                    dayKey: dayKey,
                    existingStory: existingStory,
                    events: cumulativeEvents,
                    newEvents: newEvents,
                    prompt: prompt,
                    context: invocationContext,
                    environment: environment,
                    trigger: trigger,
                    refreshLog: refreshLog
                )
                : validateIncrementalResult(
                    await runIncrementalAttempt(
                        fallbackAttempts[0],
                        dayKey: dayKey,
                        prompt: prompt,
                        context: invocationContext
                    ),
                    dayKey: dayKey,
                    existingStory: existingStory,
                    events: cumulativeEvents,
                    newEvents: newEvents,
                    environment: environment,
                    trigger: trigger,
                    refreshLog: refreshLog
                )

            if let mergedStory {
                let fileURL = try await persistChunkedFullRefreshChunk(
                    dayKey: dayKey,
                    chunkLabel: chunkLabel,
                    chunkIndex: chunkIndex,
                    chunkCount: chunkCount,
                    story: mergedStory,
                    events: cumulativeEvents,
                    environment: environment,
                    context: context,
                    refreshLog: refreshLog,
                    onStageChange: onStageChange
                )
                persistedStory = mergedStory
                latestFileURL = fileURL
                return DayRefreshGenerationResult(stage: .completed, summary: chunkLabel)
            }
        }

        dayRefreshStatus.lastRequestedDay = dayKey
        dayRefreshStatus.lastRefreshedAt = Date()
        let failureError = context.chunkFailureError(
            for: chunkLabel,
            persistedChunkCount: chunkIndex - 1
        )
        refreshLog.record.stages.append(
            RefreshLogStageRecord(
                name: "generatingStory",
                durationSeconds: 0,
                detail: failureError
            )
        )
        dayRefreshStatus.lastError = failureError
        statusMessage = "Daily note failed: \(failureError)"
        return DayRefreshGenerationResult(stage: .failed, summary: failureError)
    }

    private func persistChunkedFullRefreshChunk(
        dayKey: String,
        chunkLabel: String,
        chunkIndex: Int,
        chunkCount: Int,
        story: DailyStory,
        events: [EventRecord],
        environment: AppEnvironment,
        context: ChunkedFullRefreshContext,
        refreshLog: RefreshLogBuffer,
        onStageChange: ((DayRefreshStage, String?) -> Void)?
    ) async throws -> URL {
        let writeStartedAt = Date()
        onStageChange?(.writingFiles, "Writing \(chunkLabel) for \(dayKey)...")
        let fileURL = try persistArtifacts(dayKey: dayKey, story: story, events: events, environment: environment)
        refreshLog.record.stages.append(
            RefreshLogStageRecord(
                name: "writingFiles",
                durationSeconds: Date().timeIntervalSince(writeStartedAt),
                detail: "Persisted \(chunkLabel) (\(events.count) cumulative event(s))"
            )
        )
        await finalizeSuccessfulRefresh(
            dayKey: dayKey,
            story: story,
            events: events,
            fileURL: fileURL,
            detail: "Persisted \(chunkLabel) of \(chunkCount) for \(dayKey) during \(context.logLabel)"
        )
        return fileURL
    }

    func syncNotifications(
        for dayKey: String,
        now: Date,
        environment: AppEnvironment
    ) -> NotificationSyncOutcome {
        guard let dayStart = Self.startOfDay(for: dayKey) else {
            notificationStatus.lastImportedAt = Date()
            notificationStatus.lastImportedCount = 0
            lastImportedNotificationCount = 0
            return NotificationSyncOutcome(importedCount: 0, error: nil)
        }

        let calendar = Calendar(identifier: .gregorian)
        let nextDayStart = calendar.date(byAdding: .day, value: 1, to: dayStart)
        let isToday = dayKey == ISO8601DayKey.format(now)
        let todayWindowEnd: Date? = if isToday {
            if let nextDayStart {
                min(max(now, dayStart), nextDayStart)
            } else {
                max(now, dayStart)
            }
        } else {
            nil
        }

        do {
            let result: NotificationImportResult
            if let todayWindowEnd {
                result = try environment.notificationCollector.importDeliveredNotifications(
                    from: dayStart,
                    through: todayWindowEnd
                )
            } else if let nextDayStart {
                result = try environment.notificationCollector.importDeliveredNotifications(
                    from: dayStart,
                    until: nextDayStart
                )
            } else {
                result = try environment.notificationCollector.importDeliveredNotifications(
                    from: dayStart
                )
            }
            applyNotificationAccessStatus(result.accessStatus)
            lastImportedNotificationCount = result.importedCount
            if isToday, shouldPersistNotificationWatermark(for: result) {
                persistLastNotificationImportAt(todayWindowEnd ?? now, databasePath: environment.databaseURL.path)
            }
            notificationStatus.lastImportedAt = result.importedAt
            notificationStatus.lastImportedCount = result.importedCount
            if notificationStatus.isDatabaseAvailable {
                notificationStatus.lastError = nil
            }
            return NotificationSyncOutcome(importedCount: result.importedCount, error: nil)
        } catch {
            applyNotificationAccessStatus(environment.notificationCollector.accessStatus())
            lastImportedNotificationCount = 0
            notificationStatus.lastImportedAt = Date()
            notificationStatus.lastImportedCount = 0
            notificationStatus.lastError = error.localizedDescription
            return NotificationSyncOutcome(importedCount: 0, error: error.localizedDescription)
        }
    }

    private func refreshMode(for dayKey: String, environment: AppEnvironment) throws -> DayRefreshMode {
        guard let storyURL = storyURL(for: dayKey, environment: environment) else {
            return .fullRecovery
        }
        guard FileManager.default.fileExists(atPath: storyURL.path) else {
            return .fullRecovery
        }

        do {
            guard let existingStory = try environment.loadDailyStory(dayKey: dayKey) else {
                return .fullRecovery
            }
            return existingStory.provenance?.generationMode == .model ? .incrementalUpdate : .fullRecovery
        } catch {
            throw RefreshModeResolutionError.failedToLoadExistingStory(dayKey: dayKey, underlying: error)
        }
    }

    private func incrementallyRefreshDay(
        dayKey: String,
        recordsRun: Bool,
        now: Date,
        environment: AppEnvironment,
        trigger: RefreshTrigger,
        refreshLog: RefreshLogBuffer? = nil,
        onStageChange: ((DayRefreshStage, String?) -> Void)? = nil
    ) async -> DayRefreshGenerationResult {
        let runID = recordsRun ? try? environment.databaseWriter.startRun(runType: "daily-note", dayKey: dayKey) : nil

        do {
            guard let existingStory = try environment.loadDailyStory(dayKey: dayKey), existingStory.provenance?.generationMode == .model else {
                if let runID {
                    try environment.databaseWriter.finishRun(id: runID, status: "failed")
                }
                dayRefreshStatus.lastRequestedDay = dayKey
                dayRefreshStatus.lastRefreshedAt = Date()
                dayRefreshStatus.lastError = "No model story available for incremental update"
                statusMessage = "Daily note failed: No model story available for incremental update"
                return DayRefreshGenerationResult(stage: .failed, summary: "Failed")
            }

            onStageChange?(.loadingEvents, nil)
            let loadStartedAt = Date()
            let events = try environment.databaseWriter.fetchEvents(dayKey: dayKey)
            refreshLog?.record.totalEventCount = events.count
            refreshLog?.record.stages.append(
                RefreshLogStageRecord(
                    name: "loadingEvents",
                    durationSeconds: Date().timeIntervalSince(loadStartedAt),
                    detail: "Loaded \(events.count) event(s)"
                )
            )
            let newEvents = unwrittenEvents(events: events, existingStory: existingStory, environment: environment)
            refreshLog?.record.newEventCount = newEvents.count
            onStageChange?(.preparingStory, "Checking \(newEvents.count) new event(s) to append...")

            guard !newEvents.isEmpty else {
                if let runID {
                    try environment.databaseWriter.finishRun(id: runID, status: "succeeded")
                }
                dayRefreshStatus.lastRequestedDay = dayKey
                dayRefreshStatus.lastRefreshedAt = Date()
                dayRefreshStatus.lastError = nil
                dayRefreshStatus.detail = "No new events to append for \(dayKey)"
                statusMessage = "No new events to append for \(dayKey)"
                updateSelectedPresentation(dayKey: dayKey, story: existingStory, events: events)
                return DayRefreshGenerationResult(stage: .completed, summary: "No new events")
            }

            let attempts = refreshAttempts(trigger: trigger, using: environment)
            guard !attempts.isEmpty else {
                if let runID {
                    try environment.databaseWriter.finishRun(id: runID, status: "failed")
                }
                dayRefreshStatus.lastRequestedDay = dayKey
                dayRefreshStatus.lastRefreshedAt = Date()
                dayRefreshStatus.lastError = "No verified engine available for incremental update"
                statusMessage = "Daily note failed: No verified engine available for incremental update"
                return DayRefreshGenerationResult(stage: .failed, summary: "Failed")
            }

            if newEvents.count > refreshEventBatchSize {
                return try await refreshIncrementalDayInChunks(
                    dayKey: dayKey,
                    existingStory: existingStory,
                    events: events,
                    newEvents: newEvents,
                    runID: runID,
                    now: now,
                    environment: environment,
                    attempts: attempts,
                    trigger: trigger,
                    refreshLog: refreshLog,
                    onStageChange: onStageChange
                )
            }

            let prompt = environment.composer.incrementalPrompt(
                dayKey: dayKey,
                existingStory: existingStory,
                newEvents: newEvents,
                allEvents: events
            )
            let invocationContext = summaryInvocationContext(for: trigger)

            if trigger == .manual, let primaryAttempt = attempts.first {
                onStageChange?(.generatingStory, "Appending with \(primaryAttempt.label) (1/\(attempts.count))...")
                if let mergedStory = validateIncrementalResult(
                    await runIncrementalAttempt(
                        primaryAttempt,
                        dayKey: dayKey,
                        prompt: prompt,
                        context: invocationContext
                    ),
                    dayKey: dayKey,
                    existingStory: existingStory,
                    events: events,
                    newEvents: newEvents,
                    environment: environment,
                    trigger: trigger,
                    refreshLog: refreshLog
                ) {
                    let writeStartedAt = Date()
                    onStageChange?(.writingFiles, "Writing \(dayKey) artifacts...")
                    let fileURL = try persistArtifacts(dayKey: dayKey, story: mergedStory, events: events, environment: environment)
                    refreshLog?.record.stages.append(
                        RefreshLogStageRecord(
                            name: "writingFiles",
                            durationSeconds: Date().timeIntervalSince(writeStartedAt),
                            detail: "Persisted incremental update"
                        )
                    )
                    if let runID {
                        try environment.databaseWriter.finishRun(id: runID, status: "succeeded")
                    }
                    await finalizeSuccessfulRefresh(
                        dayKey: dayKey,
                        story: mergedStory,
                        events: events,
                        fileURL: fileURL,
                        detail: "Appended \(newEvents.count) new event(s) into \(dayKey)"
                    )
                    if let storyPath = storyURL(for: dayKey, environment: environment) {
                        refreshLog?.record.storyJSONPath = storyPath.path
                    }
                    refreshLog?.record.markdownPath = fileURL.path
                    refreshLog?.record.wroteMarkdown = true
                    refreshLog?.record.wroteStoryJSON = true
                    statusMessage = dayKey == ISO8601DayKey.format(now)
                        ? "Imported \(newEvents.count) new events and updated today"
                        : "Updated \(dayKey) with incremental events"
                    return DayRefreshGenerationResult(stage: .completed, summary: "incremental append")
                }
            }

            let fallbackAttempts = trigger == .manual ? Array(attempts.dropFirst()) : attempts
            if !fallbackAttempts.isEmpty {
                let attemptDetail: String
                if trigger == .manual, !Array(attempts.dropFirst()).isEmpty {
                    attemptDetail = "Default engine failed. Trying \(fallbackAttempts.map(\.label).joined(separator: ", ")) in parallel..."
                } else {
                    attemptDetail = "Appending with \(fallbackAttempts[0].label) (1/\(fallbackAttempts.count))..."
                }
                onStageChange?(.generatingStory, attemptDetail)

                let mergedStory = trigger == .manual
                    ? await firstValidParallelIncrementalStory(
                        fallbackAttempts,
                        dayKey: dayKey,
                        existingStory: existingStory,
                        events: events,
                        newEvents: newEvents,
                        prompt: prompt,
                        context: invocationContext,
                        environment: environment,
                        trigger: trigger,
                        refreshLog: refreshLog
                    )
                    : validateIncrementalResult(
                        await runIncrementalAttempt(
                            fallbackAttempts[0],
                            dayKey: dayKey,
                            prompt: prompt,
                            context: invocationContext
                        ),
                        dayKey: dayKey,
                        existingStory: existingStory,
                        events: events,
                        newEvents: newEvents,
                        environment: environment,
                        trigger: trigger,
                        refreshLog: refreshLog
                    )

                if let mergedStory {
                    let writeStartedAt = Date()
                    onStageChange?(.writingFiles, "Writing \(dayKey) artifacts...")
                    let fileURL = try persistArtifacts(dayKey: dayKey, story: mergedStory, events: events, environment: environment)
                    refreshLog?.record.stages.append(
                        RefreshLogStageRecord(
                            name: "writingFiles",
                            durationSeconds: Date().timeIntervalSince(writeStartedAt),
                            detail: "Persisted incremental update"
                        )
                    )
                    if let runID {
                        try environment.databaseWriter.finishRun(id: runID, status: "succeeded")
                    }
                    await finalizeSuccessfulRefresh(
                        dayKey: dayKey,
                        story: mergedStory,
                        events: events,
                        fileURL: fileURL,
                        detail: "Appended \(newEvents.count) new event(s) into \(dayKey)"
                    )
                    if let storyPath = storyURL(for: dayKey, environment: environment) {
                        refreshLog?.record.storyJSONPath = storyPath.path
                    }
                    refreshLog?.record.markdownPath = fileURL.path
                    refreshLog?.record.wroteMarkdown = true
                    refreshLog?.record.wroteStoryJSON = true
                    statusMessage = dayKey == ISO8601DayKey.format(now)
                        ? "Imported \(newEvents.count) new events and updated today"
                        : "Updated \(dayKey) with incremental events"
                    return DayRefreshGenerationResult(stage: .completed, summary: "incremental append")
                }
            }

            if let runID {
                try environment.databaseWriter.finishRun(id: runID, status: "failed")
            }
            dayRefreshStatus.lastRequestedDay = dayKey
            dayRefreshStatus.lastRefreshedAt = Date()
            dayRefreshStatus.lastError = "Incremental update failed after \(attempts.count) attempt(s)"
            statusMessage = "Daily note failed: Incremental update failed after \(attempts.count) attempt(s)"
            return DayRefreshGenerationResult(stage: .failed, summary: "Failed")
        } catch {
            if let runID {
                try? environment.databaseWriter.finishRun(id: runID, status: "failed")
            }
            dayRefreshStatus.lastRequestedDay = dayKey
            dayRefreshStatus.lastRefreshedAt = Date()
            dayRefreshStatus.lastError = error.localizedDescription
            statusMessage = "Daily note failed: \(error.localizedDescription)"
            return DayRefreshGenerationResult(stage: .failed, summary: "Failed")
        }
    }

    private func refreshIncrementalDayInChunks(
        dayKey: String,
        existingStory: DailyStory,
        events: [EventRecord],
        newEvents: [EventRecord],
        runID: UUID?,
        now: Date,
        environment: AppEnvironment,
        attempts: [RefreshSummarizerAttempt],
        trigger: RefreshTrigger,
        refreshLog: RefreshLogBuffer?,
        onStageChange: ((DayRefreshStage, String?) -> Void)?
    ) async throws -> DayRefreshGenerationResult {
        let chunks = stride(from: 0, to: newEvents.count, by: refreshEventBatchSize).map { startIndex in
            Array(newEvents[startIndex..<min(startIndex + refreshEventBatchSize, newEvents.count)])
        }
        refreshLog?.record.stages.append(
            RefreshLogStageRecord(
                name: "chunkingPlan",
                durationSeconds: 0,
                detail: "Chunked incremental update into \(chunks.count) batch(es) of up to \(refreshEventBatchSize) event(s)"
            )
        )

        let newEventIDs = Set(newEvents.map(\.id))
        var cumulativeEvents = events
            .filter { !newEventIDs.contains($0.id) }
            .sorted { $0.capturedAt < $1.capturedAt }
        var currentStory = existingStory
        var latestFileURL: URL?
        let context = ChunkedFullRefreshContext.incrementalUpdate
        let invocationContext = summaryInvocationContext(for: trigger)

        for (index, chunk) in chunks.enumerated() {
            cumulativeEvents.append(contentsOf: chunk)
            let chunkNumber = index + 1
            let chunkLabel = "chunk \(chunkNumber)/\(chunks.count)"
            refreshLog?.record.stages.append(
                RefreshLogStageRecord(
                    name: "loadingEvents",
                    durationSeconds: 0,
                    detail: "\(chunkLabel) loaded \(chunk.count) event(s); \(cumulativeEvents.count)/\(events.count) cumulative, \(min(chunkNumber * refreshEventBatchSize, newEvents.count))/\(newEvents.count) new event(s) appended"
                )
            )
            refreshLog?.record.newEventCount = newEvents.count
            onStageChange?(
                .preparingStory,
                "Appending \(chunkLabel) with \(chunk.count) event(s); \(min(chunkNumber * refreshEventBatchSize, newEvents.count))/\(newEvents.count) new event(s)..."
            )

            var persistedStory: DailyStory?
            var persistedFileURL: URL?
            let result = try await runChunkedFullRefreshIncrementalChunk(
                dayKey: dayKey,
                chunkLabel: chunkLabel,
                chunkIndex: chunkNumber,
                chunkCount: chunks.count,
                existingStory: currentStory,
                newEvents: chunk,
                cumulativeEvents: cumulativeEvents,
                now: now,
                environment: environment,
                attempts: attempts,
                trigger: trigger,
                context: context,
                invocationContext: invocationContext,
                refreshLog: refreshLog ?? RefreshLogBuffer(record: RefreshLogRecord(dayKey: dayKey, trigger: trigger, mode: "incrementalUpdate", startedAt: Date())),
                onStageChange: onStageChange,
                persistedStory: &persistedStory,
                latestFileURL: &persistedFileURL
            )

            guard result.stage == .completed, let persistedStory, let persistedFileURL else {
                if let runID {
                    try? environment.databaseWriter.finishRun(id: runID, status: "failed")
                }
                return result
            }
            currentStory = persistedStory
            latestFileURL = persistedFileURL
        }

        if let runID {
            try environment.databaseWriter.finishRun(id: runID, status: "succeeded")
        }
        guard let latestFileURL else {
            dayRefreshStatus.lastRequestedDay = dayKey
            dayRefreshStatus.lastRefreshedAt = Date()
            dayRefreshStatus.lastError = "Chunked incremental update produced no story"
            statusMessage = "Daily note failed: Chunked incremental update produced no story"
            return DayRefreshGenerationResult(stage: .failed, summary: "Failed")
        }

        await finalizeSuccessfulRefresh(
            dayKey: dayKey,
            story: currentStory,
            events: cumulativeEvents,
            fileURL: latestFileURL,
            detail: "Completed incremental update in \(chunks.count) chunk(s) for \(dayKey)"
        )
        if let storyPath = storyURL(for: dayKey, environment: environment) {
            refreshLog?.record.storyJSONPath = storyPath.path
        }
        refreshLog?.record.markdownPath = latestFileURL.path
        refreshLog?.record.wroteMarkdown = true
        refreshLog?.record.wroteStoryJSON = true
        statusMessage = context.completionStatusMessage(for: dayKey, now: now)
        return DayRefreshGenerationResult(stage: .completed, summary: context.resultSummary)
    }

    private func refreshDayWithRetry(
        dayKey: String,
        recordsRun: Bool,
        now: Date,
        environment: AppEnvironment,
        trigger: RefreshTrigger,
        refreshLog: RefreshLogBuffer? = nil,
        onStageChange: ((DayRefreshStage, String?) -> Void)? = nil
    ) async -> DayRefreshGenerationResult {
        let attempts = refreshAttempts(trigger: trigger, using: environment)
        guard !attempts.isEmpty else {
            return failFullRecoveryWithoutVerifiedEngine(dayKey: dayKey)
        }

        let runID = recordsRun ? try? environment.databaseWriter.startRun(runType: "daily-note", dayKey: dayKey) : nil
        do {
            onStageChange?(.loadingEvents, nil)
            let loadStartedAt = Date()
            let events = try environment.databaseWriter.fetchEvents(dayKey: dayKey)
            refreshLog?.record.totalEventCount = events.count
            refreshLog?.record.stages.append(
                RefreshLogStageRecord(
                    name: "loadingEvents",
                    durationSeconds: Date().timeIntervalSince(loadStartedAt),
                    detail: "Loaded \(events.count) event(s)"
                )
            )
            onStageChange?(.preparingStory, "Preparing journal from \(events.count) event(s)...")

            let prompt = environment.composer.storyPrompt(dayKey: dayKey, events: events)
            let invocationContext = summaryInvocationContext(for: trigger)

            if trigger == .manual, let primaryAttempt = attempts.first {
                onStageChange?(.generatingStory, "Calling \(primaryAttempt.label) (1/\(attempts.count))...")
                if let story = validateFullRecoveryResult(
                    await runAttempt(
                        primaryAttempt,
                        dayKey: dayKey,
                        prompt: prompt,
                        context: invocationContext
                    ),
                    dayKey: dayKey,
                    events: events,
                    environment: environment,
                    trigger: trigger,
                    refreshLog: refreshLog
                ) {
                    let writeStartedAt = Date()
                    onStageChange?(.writingFiles, "Writing \(dayKey) artifacts...")
                    let fileURL = try persistArtifacts(dayKey: dayKey, story: story, events: events, environment: environment)
                    refreshLog?.record.stages.append(
                        RefreshLogStageRecord(
                            name: "writingFiles",
                            durationSeconds: Date().timeIntervalSince(writeStartedAt),
                            detail: "Persisted full recovery"
                        )
                    )
                    if let runID {
                        try environment.databaseWriter.finishRun(id: runID, status: "succeeded")
                    }
                    await finalizeSuccessfulRefresh(
                        dayKey: dayKey,
                        story: story,
                        events: events,
                        fileURL: fileURL,
                        detail: events.isEmpty
                            ? "Refreshed \(dayKey) with no captured events"
                            : "Refreshed \(dayKey) into \(story.sections.flatMap(\.paragraphs).count) story segment(s)"
                    )
                    if let storyPath = storyURL(for: dayKey, environment: environment) {
                        refreshLog?.record.storyJSONPath = storyPath.path
                    }
                    refreshLog?.record.markdownPath = fileURL.path
                    refreshLog?.record.wroteMarkdown = true
                    refreshLog?.record.wroteStoryJSON = true
                    statusMessage = dayKey == ISO8601DayKey.format(now)
                        ? "Refreshed today with story view"
                        : "Refreshed \(dayKey) with story view"
                    return DayRefreshGenerationResult(stage: .completed, summary: refreshSummary(for: story))
                }
            }

            let fallbackAttempts = trigger == .manual ? Array(attempts.dropFirst()) : attempts
            if !fallbackAttempts.isEmpty {
                let attemptDetail: String
                if trigger == .manual, !Array(attempts.dropFirst()).isEmpty {
                    attemptDetail = "Default engine failed. Trying \(fallbackAttempts.map(\.label).joined(separator: ", ")) in parallel..."
                } else {
                    attemptDetail = "Calling \(fallbackAttempts[0].label) (1/\(fallbackAttempts.count))..."
                }
                onStageChange?(.generatingStory, attemptDetail)

                let results = trigger == .manual
                    ? await runParallelAttempts(
                        fallbackAttempts,
                        dayKey: dayKey,
                        prompt: prompt,
                        context: invocationContext
                    )
                    : [await runAttempt(
                        fallbackAttempts[0],
                        dayKey: dayKey,
                        prompt: prompt,
                        context: invocationContext
                    )]

                for result in results {
                    guard let story = validateFullRecoveryResult(
                        result,
                        dayKey: dayKey,
                        events: events,
                        environment: environment,
                        trigger: trigger,
                        refreshLog: refreshLog
                    ) else {
                        continue
                    }
                    let writeStartedAt = Date()
                    onStageChange?(.writingFiles, "Writing \(dayKey) artifacts...")
                    let fileURL = try persistArtifacts(dayKey: dayKey, story: story, events: events, environment: environment)
                    refreshLog?.record.stages.append(
                        RefreshLogStageRecord(
                            name: "writingFiles",
                            durationSeconds: Date().timeIntervalSince(writeStartedAt),
                            detail: "Persisted full recovery"
                        )
                    )
                    if let runID {
                        try environment.databaseWriter.finishRun(id: runID, status: "succeeded")
                    }
                    await finalizeSuccessfulRefresh(
                        dayKey: dayKey,
                        story: story,
                        events: events,
                        fileURL: fileURL,
                        detail: events.isEmpty
                            ? "Refreshed \(dayKey) with no captured events"
                            : "Refreshed \(dayKey) into \(story.sections.flatMap(\.paragraphs).count) story segment(s)"
                    )
                    if let storyPath = storyURL(for: dayKey, environment: environment) {
                        refreshLog?.record.storyJSONPath = storyPath.path
                    }
                    refreshLog?.record.markdownPath = fileURL.path
                    refreshLog?.record.wroteMarkdown = true
                    refreshLog?.record.wroteStoryJSON = true
                    statusMessage = dayKey == ISO8601DayKey.format(now)
                        ? "Refreshed today with story view"
                        : "Refreshed \(dayKey) with story view"
                    return DayRefreshGenerationResult(stage: .completed, summary: refreshSummary(for: story))
                }
            }

            if let runID {
                try environment.databaseWriter.finishRun(id: runID, status: "failed")
            }
            dayRefreshStatus.lastRequestedDay = dayKey
            dayRefreshStatus.lastRefreshedAt = Date()
            dayRefreshStatus.lastError = "Model refresh failed after \(attempts.count) attempt(s)"
            statusMessage = "Daily note failed: Model refresh failed after \(attempts.count) attempt(s)"
            return DayRefreshGenerationResult(stage: .failed, summary: "Failed")
        } catch {
            if let runID {
                try? environment.databaseWriter.finishRun(id: runID, status: "failed")
            }
            dayRefreshStatus.lastRequestedDay = dayKey
            dayRefreshStatus.lastRefreshedAt = Date()
            dayRefreshStatus.lastError = error.localizedDescription
            statusMessage = "Daily note failed: \(error.localizedDescription)"
            return DayRefreshGenerationResult(stage: .failed, summary: "Failed")
        }
    }

    private func failFullRecoveryWithoutVerifiedEngine(dayKey: String) -> DayRefreshGenerationResult {
        dayRefreshStatus.lastRequestedDay = dayKey
        dayRefreshStatus.lastRefreshedAt = Date()
        dayRefreshStatus.lastError = "Configure and verify an engine to generate this journal"
        statusMessage = "Daily note failed: Configure and verify an engine to generate this journal"
        return DayRefreshGenerationResult(stage: .failed, summary: "Failed")
    }

    private func unwrittenEvents(
        events: [EventRecord],
        existingStory: DailyStory,
        environment: AppEnvironment
    ) -> [EventRecord] {
        let usedIDs = environment.composer.usedSourceEventIDs(in: existingStory)
        return events.filter { !usedIDs.contains($0.id) }.sorted { $0.capturedAt < $1.capturedAt }
    }

    private func manualRefreshAttemptEngines() -> [DiaryEngine] {
        let selectedEngine = activeRefreshEngine(using: environment)

        var engines: [DiaryEngine] = []
        if selectedEngine != .none {
            engines.append(selectedEngine)
        }

        let greenFallbacks = Self.autoSelectionPriority.filter { engine in
            engine != .none &&
            engine != selectedEngine &&
            engineStatuses[engine]?.state == .green
        }
        engines.append(contentsOf: greenFallbacks)
        return Array(engines.prefix(5))
    }

    private func refreshAttempts(trigger: RefreshTrigger, using environment: AppEnvironment) -> [RefreshSummarizerAttempt] {
        let selectedEngine = activeRefreshEngine(using: environment)
        var attempts: [RefreshSummarizerAttempt] = []
        var appendedEngines: Set<DiaryEngine> = []

        if let summarizer = environment.summarizer {
            let injectedEngine = selectedEngine == .none ? nil : selectedEngine
            attempts.append(
                RefreshSummarizerAttempt(
                    engine: injectedEngine,
                    summarizer: summarizer
                )
            )
            if let injectedEngine {
                appendedEngines.insert(injectedEngine)
            }
        }

        if trigger == .automation {
            if attempts.isEmpty,
               selectedEngine != .none,
               let summarizer = makeSummarizer(selectedEngine, summarizerConfig, processEnvironment) {
                attempts.append(
                    RefreshSummarizerAttempt(
                        engine: selectedEngine,
                        summarizer: summarizer
                    )
                )
            }
            return Array(attempts.prefix(1))
        }

        for engine in manualRefreshAttemptEngines() where !appendedEngines.contains(engine) {
            guard let summarizer = makeSummarizer(engine, summarizerConfig, processEnvironment) else {
                continue
            }
            attempts.append(
                RefreshSummarizerAttempt(
                    engine: engine,
                    summarizer: summarizer
                )
            )
            appendedEngines.insert(engine)
        }

        return Array(attempts.prefix(5))
    }

    private func activeRefreshEngine(using environment: AppEnvironment?) -> DiaryEngine {
        if defaultEngine != .none {
            return defaultEngine
        }
        return Self.inferEngine(from: environment?.summarizer) ?? .none
    }

    private func summaryInvocationContext(for trigger: RefreshTrigger) -> SummaryInvocationContext {
        switch trigger {
        case .manual:
            return .manualRefresh
        case .automation:
            return .automationRefresh
        }
    }

    private func decodeFullRecoveryStory(
        raw: String,
        dayKey: String,
        events: [EventRecord],
        engine: DiaryEngine?,
        environment: AppEnvironment
    ) -> DailyStory? {
        guard let parsed = environment.composer.parseStory(dayKey: dayKey, raw: raw) else {
            return nil
        }

        let normalizedStory = environment.composer.normalizeStory(parsed, events: events)
        guard !normalizedStory.sections.flatMap(\.paragraphs).isEmpty else {
            return nil
        }

        return normalizedStory.withProvenance(
            makeStoryProvenance(
                mode: .model,
                engine: engine ?? activeRefreshEngine(using: environment),
                curatedEventCount: events.count
            )
        )
    }

    private func decodeIncrementalStory(
        raw: String,
        dayKey: String,
        existingStory: DailyStory,
        events: [EventRecord],
        newEvents: [EventRecord],
        engine: DiaryEngine?,
        environment: AppEnvironment
    ) -> DailyStory? {
        guard
            let update = environment.composer.parseIncrementalUpdate(raw: raw),
            let validatedUpdate = environment.composer.validatedIncrementalUpdate(
                update,
                allowedSourceEventIDs: Set(events.map(\.id)),
                allowedDetailSourceEventIDs: Set(newEvents.map(\.id))
            )
        else {
            return nil
        }

        return environment.composer.mergeIncrementalUpdate(
            dayKey: dayKey,
            existingStory: existingStory,
            update: validatedUpdate,
            allEvents: events,
            provenance: makeStoryProvenance(
                mode: .model,
                engine: engine ?? activeRefreshEngine(using: environment),
                curatedEventCount: events.count
            )
        )
    }

    private func validateFullRecoveryResult(
        _ result: RefreshAttemptRunResult,
        dayKey: String,
        events: [EventRecord],
        environment: AppEnvironment,
        trigger: RefreshTrigger,
        refreshLog: RefreshLogBuffer?
    ) -> DailyStory? {
        switch result {
        case .succeeded(let attempt, let raw, let startedAt, let finishedAt):
            guard let story = decodeFullRecoveryStory(
                raw: raw,
                dayKey: dayKey,
                events: events,
                engine: attempt.engine,
                environment: environment
            ) else {
                if let engine = attempt.engine {
                    recordEngineRuntime(
                        for: engine,
                        state: .yellow,
                        detail: "Story output was not valid structured JSON",
                        verifiedAt: Date()
                    )
                }
                appendAttemptLog(
                    engine: attempt.engine,
                    trigger: trigger,
                    startedAt: startedAt,
                    finishedAt: finishedAt,
                    outcome: "failed",
                    error: "Story output was not valid structured JSON",
                    refreshLog: refreshLog
                )
                return nil
            }
            if let engine = attempt.engine {
                recordEngineRuntime(for: engine, state: .green, detail: "Story generation succeeded.", verifiedAt: Date())
            }
            appendAttemptLog(
                engine: attempt.engine,
                trigger: trigger,
                startedAt: startedAt,
                finishedAt: finishedAt,
                outcome: "succeeded",
                error: nil,
                refreshLog: refreshLog
            )
            return story
        case .failed(let attempt, let error, let startedAt, let finishedAt):
            if let engine = attempt.engine {
                recordEngineRuntime(
                    for: engine,
                    state: .yellow,
                    detail: error.localizedDescription,
                    verifiedAt: Date()
                )
            }
            appendAttemptLog(
                engine: attempt.engine,
                trigger: trigger,
                startedAt: startedAt,
                finishedAt: finishedAt,
                outcome: "failed",
                error: error.localizedDescription,
                refreshLog: refreshLog
            )
            return nil
        case .cancelled(let attempt, let startedAt, let finishedAt):
            appendAttemptLog(
                engine: attempt.engine,
                trigger: trigger,
                startedAt: startedAt,
                finishedAt: finishedAt,
                outcome: "cancelled",
                error: nil,
                refreshLog: refreshLog
            )
            return nil
        }
    }

    private func validateIncrementalResult(
        _ result: RefreshAttemptRunResult,
        dayKey: String,
        existingStory: DailyStory,
        events: [EventRecord],
        newEvents: [EventRecord],
        environment: AppEnvironment,
        trigger: RefreshTrigger,
        refreshLog: RefreshLogBuffer?
    ) -> DailyStory? {
        switch result {
        case .succeeded(let attempt, let raw, let startedAt, let finishedAt):
            guard let story = decodeIncrementalStory(
                raw: raw,
                dayKey: dayKey,
                existingStory: existingStory,
                events: events,
                newEvents: newEvents,
                engine: attempt.engine,
                environment: environment
            ) else {
                if let engine = attempt.engine {
                    recordEngineRuntime(
                        for: engine,
                        state: .yellow,
                        detail: "Incremental output was not valid structured JSON",
                        verifiedAt: Date()
                    )
                }
                appendAttemptLog(
                    engine: attempt.engine,
                    trigger: trigger,
                    startedAt: startedAt,
                    finishedAt: finishedAt,
                    outcome: "failed",
                    error: "Incremental output was not valid structured JSON",
                    refreshLog: refreshLog
                )
                return nil
            }
            if let engine = attempt.engine {
                recordEngineRuntime(
                    for: engine,
                    state: .green,
                    detail: "Incremental story generation succeeded.",
                    verifiedAt: Date()
                )
            }
            appendAttemptLog(
                engine: attempt.engine,
                trigger: trigger,
                startedAt: startedAt,
                finishedAt: finishedAt,
                outcome: "succeeded",
                error: nil,
                refreshLog: refreshLog
            )
            return story
        case .failed(let attempt, let error, let startedAt, let finishedAt):
            if let engine = attempt.engine {
                recordEngineRuntime(
                    for: engine,
                    state: .yellow,
                    detail: error.localizedDescription,
                    verifiedAt: Date()
                )
            }
            appendAttemptLog(
                engine: attempt.engine,
                trigger: trigger,
                startedAt: startedAt,
                finishedAt: finishedAt,
                outcome: "failed",
                error: error.localizedDescription,
                refreshLog: refreshLog
            )
            return nil
        case .cancelled(let attempt, let startedAt, let finishedAt):
            appendAttemptLog(
                engine: attempt.engine,
                trigger: trigger,
                startedAt: startedAt,
                finishedAt: finishedAt,
                outcome: "cancelled",
                error: nil,
                refreshLog: refreshLog
            )
            return nil
        }
    }

    private func firstValidParallelIncrementalStory(
        _ attempts: [RefreshSummarizerAttempt],
        dayKey: String,
        existingStory: DailyStory,
        events: [EventRecord],
        newEvents: [EventRecord],
        prompt: String,
        context: SummaryInvocationContext,
        environment: AppEnvironment,
        trigger: RefreshTrigger,
        refreshLog: RefreshLogBuffer?
    ) async -> DailyStory? {
        await withTaskGroup(of: RefreshAttemptRunResult.self) { group in
            for attempt in attempts {
                group.addTask {
                    await AppState.runParallelIncrementalAttempt(
                        attempt,
                        dayKey: dayKey,
                        prompt: prompt,
                        context: context
                    )
                }
            }

            var mergedStory: DailyStory?
            while let result = await group.next() {
                if mergedStory == nil,
                   let validatedStory = validateIncrementalResult(
                    result,
                    dayKey: dayKey,
                    existingStory: existingStory,
                    events: events,
                    newEvents: newEvents,
                    environment: environment,
                    trigger: trigger,
                    refreshLog: refreshLog
                   ) {
                    mergedStory = validatedStory
                    group.cancelAll()
                    continue
                }

                _ = validateIncrementalResult(
                    result,
                    dayKey: dayKey,
                    existingStory: existingStory,
                    events: events,
                    newEvents: newEvents,
                    environment: environment,
                    trigger: trigger,
                    refreshLog: refreshLog
                )
            }

            return mergedStory
        }
    }

    private func runAttempt(
        _ attempt: RefreshSummarizerAttempt,
        dayKey: String,
        prompt: String,
        context: SummaryInvocationContext
    ) async -> RefreshAttemptRunResult {
        let startedAt = Date()
        do {
            let raw = try await attempt.summarizer.summarize(
                dayKey: dayKey,
                markdown: prompt,
                context: context
            )
            return .succeeded(
                attempt: attempt,
                raw: raw,
                startedAt: startedAt,
                finishedAt: Date()
            )
        } catch is CancellationError {
            return .cancelled(
                attempt: attempt,
                startedAt: startedAt,
                finishedAt: Date()
            )
        } catch {
            return .failed(
                attempt: attempt,
                error: error,
                startedAt: startedAt,
                finishedAt: Date()
            )
        }
    }

    private func runParallelAttempts(
        _ attempts: [RefreshSummarizerAttempt],
        dayKey: String,
        prompt: String,
        context: SummaryInvocationContext
    ) async -> [RefreshAttemptRunResult] {
        await withTaskGroup(of: RefreshAttemptRunResult.self) { group in
            for attempt in attempts {
                group.addTask {
                    await AppState.runParallelAttempt(
                        attempt,
                        dayKey: dayKey,
                        prompt: prompt,
                        context: context
                    )
                }
            }

            var results: [RefreshAttemptRunResult] = []
            while let result = await group.next() {
                results.append(result)
                switch result {
                case .succeeded:
                    group.cancelAll()
                case .failed, .cancelled:
                    break
                }
            }
            return results
        }
    }

    private func runIncrementalAttempt(
        _ attempt: RefreshSummarizerAttempt,
        dayKey: String,
        prompt: String,
        context: SummaryInvocationContext
    ) async -> RefreshAttemptRunResult {
        let startedAt = Date()
        do {
            let raw = try await attempt.summarizer.summarizeIncremental(
                dayKey: dayKey,
                markdown: prompt,
                context: context
            )
            return .succeeded(
                attempt: attempt,
                raw: raw,
                startedAt: startedAt,
                finishedAt: Date()
            )
        } catch is CancellationError {
            return .cancelled(
                attempt: attempt,
                startedAt: startedAt,
                finishedAt: Date()
            )
        } catch {
            return .failed(
                attempt: attempt,
                error: error,
                startedAt: startedAt,
                finishedAt: Date()
            )
        }
    }

    private func runParallelIncrementalAttempts(
        _ attempts: [RefreshSummarizerAttempt],
        dayKey: String,
        prompt: String,
        context: SummaryInvocationContext
    ) async -> [RefreshAttemptRunResult] {
        await withTaskGroup(of: RefreshAttemptRunResult.self) { group in
            for attempt in attempts {
                group.addTask {
                    await AppState.runParallelIncrementalAttempt(
                        attempt,
                        dayKey: dayKey,
                        prompt: prompt,
                        context: context
                    )
                }
            }

            var results: [RefreshAttemptRunResult] = []
            while let result = await group.next() {
                results.append(result)
            }
            return results
        }
    }

    nonisolated private static func runParallelAttempt(
        _ attempt: RefreshSummarizerAttempt,
        dayKey: String,
        prompt: String,
        context: SummaryInvocationContext
    ) async -> RefreshAttemptRunResult {
        let startedAt = Date()
        do {
            let raw = try await attempt.summarizer.summarize(
                dayKey: dayKey,
                markdown: prompt,
                context: context
            )
            return .succeeded(
                attempt: attempt,
                raw: raw,
                startedAt: startedAt,
                finishedAt: Date()
            )
        } catch is CancellationError {
            return .cancelled(
                attempt: attempt,
                startedAt: startedAt,
                finishedAt: Date()
            )
        } catch {
            return .failed(
                attempt: attempt,
                error: error,
                startedAt: startedAt,
                finishedAt: Date()
            )
        }
    }

    nonisolated private static func runParallelIncrementalAttempt(
        _ attempt: RefreshSummarizerAttempt,
        dayKey: String,
        prompt: String,
        context: SummaryInvocationContext
    ) async -> RefreshAttemptRunResult {
        let startedAt = Date()
        do {
            let raw = try await attempt.summarizer.summarizeIncremental(
                dayKey: dayKey,
                markdown: prompt,
                context: context
            )
            return .succeeded(
                attempt: attempt,
                raw: raw,
                startedAt: startedAt,
                finishedAt: Date()
            )
        } catch is CancellationError {
            return .cancelled(
                attempt: attempt,
                startedAt: startedAt,
                finishedAt: Date()
            )
        } catch {
            return .failed(
                attempt: attempt,
                error: error,
                startedAt: startedAt,
                finishedAt: Date()
            )
        }
    }

    private func timeoutSeconds(for trigger: RefreshTrigger) -> Int {
        switch trigger {
        case .manual:
            return 600
        case .automation:
            return 300
        }
    }

    private func appendAttemptLog(
        engine: DiaryEngine?,
        trigger: RefreshTrigger,
        startedAt: Date,
        finishedAt: Date,
        outcome: String,
        error: String?,
        refreshLog: RefreshLogBuffer?
    ) {
        guard let refreshLog else { return }
        refreshLog.record.attempts.append(
            RefreshLogAttemptRecord(
                engine: (engine ?? activeRefreshEngine(using: environment)).displayName,
                timeoutSeconds: timeoutSeconds(for: trigger),
                startedAt: startedAt,
                finishedAt: finishedAt,
                durationSeconds: finishedAt.timeIntervalSince(startedAt),
                outcome: outcome,
                failureKind: Self.failureKind(for: error)?.rawValue,
                error: error
            )
        )
    }

    private func storyURL(for dayKey: String, environment: AppEnvironment) -> URL? {
        environment.vaultURL.appending(path: "\(dayKey).story.json")
    }

    private func setSelectedDiaryDate(_ dayKey: String) {
        selectedDate = dayKey
        mainContentSelection = .diary(dayKey: dayKey)
    }

    private func persistArtifacts(
        dayKey: String,
        story: DailyStory,
        events: [EventRecord],
        environment: AppEnvironment
    ) throws -> URL {
        let finalMarkdown = environment.composer.compose(dayKey: dayKey, events: events, story: story)
        let fileURL = try environment.writeDailyNote(dayKey: dayKey, markdown: finalMarkdown)
        _ = try environment.writeDailyStory(story)
        return fileURL
    }

    private func finalizeSuccessfulRefresh(
        dayKey: String,
        story: DailyStory,
        events: [EventRecord],
        fileURL: URL,
        detail: String
    ) async {
        noteIndex[dayKey] = fileURL
        availableDates = noteIndex.keys.sorted(by: >)
        if selectedDate == dayKey || selectedDate == nil {
            setSelectedDiaryDate(dayKey)
            selectedMarkdownURL = fileURL
            selectedContentVersion += 1
        }
        updateSelectedPresentation(dayKey: dayKey, story: story, events: events)
        dayRefreshStatus.lastRequestedDay = dayKey
        dayRefreshStatus.lastRefreshedAt = Date()
        dayRefreshStatus.lastError = nil
        dayRefreshStatus.detail = detail
        await reevaluateEndOfDayReminder(for: dayKey, now: currentDate(), story: story, events: events)
    }

    private func persistRefreshLog(_ refreshLog: RefreshLogRecord, environment: AppEnvironment) {
        var persistedLog = refreshLog
        let startedText = ISO8601DateFormatter().string(from: refreshLog.startedAt)
            .replacingOccurrences(of: ":", with: "-")
        let filename = "\(startedText)__\(refreshLog.dayKey)__\(refreshLog.trigger.rawValue)__\(refreshLog.mode).json"

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let provisionalData = try encoder.encode(persistedLog)
            let fileURL = try environment.writeRefreshLog(filename: filename, data: provisionalData)
            persistedLog.logPath = fileURL.path
            let finalData = try encoder.encode(persistedLog)
            _ = try environment.writeRefreshLog(filename: filename, data: finalData)
            refreshLogNoticesByDay.removeValue(forKey: refreshLog.dayKey)
        } catch {
            refreshLogNoticesByDay[refreshLog.dayKey] = "Refresh log unavailable"
        }
    }

    func generateStory(
        dayKey: String,
        events: [EventRecord],
        environment: AppEnvironment,
        onStageDetail: ((String) -> Void)? = nil
    ) async -> DailyStory {
        let activeEngine = if defaultEngine == .none {
            summarizerConfig.defaultEngine != .none
                ? summarizerConfig.defaultEngine
                : (Self.inferEngine(from: environment.summarizer) ?? .none)
        } else {
            defaultEngine
        }
        let fallbackStory = environment.composer
            .fallbackStory(dayKey: dayKey, events: events)
            .withProvenance(
                makeStoryProvenance(
                    mode: .fallback,
                    engine: activeEngine,
                    curatedEventCount: events.count
                )
            )
        guard let summarizer = environment.summarizer else {
            onStageDetail?("No verified engine available; using local fallback")
            return fallbackStory
        }

        do {
            onStageDetail?("Calling \(activeEngine.displayName)...")
            let raw = try await summarizer.summarize(
                dayKey: dayKey,
                markdown: environment.composer.storyPrompt(dayKey: dayKey, events: events)
            )
            onStageDetail?("Parsing \(activeEngine.displayName) response...")
            if let parsed = environment.composer.parseStory(dayKey: dayKey, raw: raw) {
                let normalizedStory = environment.composer.normalizeStory(parsed, events: events)
                guard normalizedStory.sections.flatMap(\.paragraphs).isEmpty == false else {
                    recordActiveEngineRuntime(
                        state: .yellow,
                        detail: "Story output was not valid structured JSON",
                        verifiedAt: Date()
                    )
                    onStageDetail?("\(activeEngine.displayName) returned invalid output; using local fallback")
                    return fallbackStory
                }
                recordActiveEngineRuntime(state: .green, detail: "Story generation succeeded.", verifiedAt: Date())
                onStageDetail?("\(activeEngine.displayName) returned successfully")
                return normalizedStory.withProvenance(
                    makeStoryProvenance(
                        mode: .model,
                        engine: activeEngine,
                        curatedEventCount: events.count
                    )
                )
            }
            recordActiveEngineRuntime(
                state: .yellow,
                detail: "Story output was not valid structured JSON",
                verifiedAt: Date()
            )
            onStageDetail?("\(activeEngine.displayName) returned invalid output; using local fallback")
        } catch {
            recordActiveEngineRuntime(
                state: .yellow,
                detail: error.localizedDescription,
                verifiedAt: Date()
            )
            onStageDetail?("\(activeEngine.displayName) failed; using local fallback")
        }

        return fallbackStory
    }

    func loadDayPresentation(for dayKey: String) {
        if dayKey == OnboardingDemoStory.demoDayKey {
            loadDemoDayPresentation()
            return
        }
        if onboardingBootstrapDayKeys.contains(dayKey), noteIndex[dayKey] == nil {
            setSelectedDiaryDate(dayKey)
            selectedStory = nil
            selectedStoryParagraphID = nil
            selectedStorySourceEvents = []
            selectedDayEvents = []
            selectedMarkdownURL = nil
            selectedMarkdownText = nil
            selectedSourceNotesMarkdown = nil
            return
        }
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
        let loadedStory = (try? environment.loadDailyStory(dayKey: dayKey)) ?? nil
        let story = loadedStory ?? environment.composer.fallbackStory(dayKey: dayKey, events: events)
        updateSelectedPresentation(dayKey: dayKey, story: story, events: events)
    }

    func updateSelectedPresentation(dayKey: String, story: DailyStory, events: [EventRecord]) {
        setSelectedDiaryDate(dayKey)
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

    func presentOnboardingDemoIfNeeded() {
        guard shouldShowOnboarding else { return }

        if !isPresentingOnboardingDemo {
            liveReaderSnapshot = ReaderPresentationSnapshot(
                availableDates: availableDates,
                selectedDate: selectedDate,
                mainContentSelection: mainContentSelection,
                selectedMarkdownURL: selectedMarkdownURL,
                noteIndex: noteIndex,
                selectedStory: selectedStory,
                selectedStoryParagraphID: selectedStoryParagraphID,
                selectedStorySourceEvents: selectedStorySourceEvents,
                selectedDayEvents: selectedDayEvents,
                selectedMarkdownText: selectedMarkdownText,
                selectedSourceNotesMarkdown: selectedSourceNotesMarkdown,
                readerFocus: readerFocus
            )
            isPresentingOnboardingDemo = true
        }

        availableDates = [OnboardingDemoStory.demoDayKey]
        noteIndex = [:]
        setSelectedDiaryDate(OnboardingDemoStory.demoDayKey)
        selectedMarkdownURL = nil
        selectedStory = OnboardingDemoStory.demoStory
        selectedDayEvents = OnboardingDemoStory.demoEvents
        selectedMarkdownText = nil
        selectedSourceNotesMarkdown = generatedSourceNotesMarkdown(from: OnboardingDemoStory.demoEvents)
        if let selectedStoryParagraphID,
           selectedStoryParagraphs.contains(where: { $0.id == selectedStoryParagraphID }) == false {
            self.selectedStoryParagraphID = nil
        }
        selectedStorySourceEvents = []
        readerFocus = .storyParagraphs
        syncSelectedStorySources()
    }

    private func loadDemoDayPresentation() {
        selectedMarkdownURL = nil
        setSelectedDiaryDate(OnboardingDemoStory.demoDayKey)
        selectedStory = OnboardingDemoStory.demoStory
        selectedDayEvents = OnboardingDemoStory.demoEvents
        selectedMarkdownText = nil
        selectedSourceNotesMarkdown = generatedSourceNotesMarkdown(from: OnboardingDemoStory.demoEvents)
        if let selectedStoryParagraphID,
           selectedStoryParagraphs.contains(where: { $0.id == selectedStoryParagraphID }) == false {
            self.selectedStoryParagraphID = nil
        }
        if selectedStoryParagraphID == nil {
            selectedStorySourceEvents = []
        } else {
            syncSelectedStorySources()
        }
    }

    func restoreLiveReaderPresentationAfterOnboarding() {
        isPresentingOnboardingDemo = false
        if environment != nil {
            refreshNotesIndex()
            liveReaderSnapshot = nil
            return
        }

        guard let liveReaderSnapshot else { return }
        availableDates = liveReaderSnapshot.availableDates
        selectedDate = liveReaderSnapshot.selectedDate
        mainContentSelection = liveReaderSnapshot.mainContentSelection
        selectedMarkdownURL = liveReaderSnapshot.selectedMarkdownURL
        noteIndex = liveReaderSnapshot.noteIndex
        selectedStory = liveReaderSnapshot.selectedStory
        selectedStoryParagraphID = liveReaderSnapshot.selectedStoryParagraphID
        selectedStorySourceEvents = liveReaderSnapshot.selectedStorySourceEvents
        selectedDayEvents = liveReaderSnapshot.selectedDayEvents
        selectedMarkdownText = liveReaderSnapshot.selectedMarkdownText
        selectedSourceNotesMarkdown = liveReaderSnapshot.selectedSourceNotesMarkdown
        readerFocus = liveReaderSnapshot.readerFocus
        self.liveReaderSnapshot = nil
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
        if let active = selectedDate.flatMap({ refreshJobsByDay[$0] }), active.inFlight {
            return active.detail ?? ""
        }
        if let lastError = dayRefreshStatus.lastError, let dayKey = dayRefreshStatus.lastRequestedDay {
            return "Refresh failed for \(dayKey): \(lastError)"
        }
        if let detail = dayRefreshStatus.detail {
            return detail
        }
        return ""
    }

    func refreshLogNotice(for dayKey: String?) -> String? {
        guard let dayKey else { return nil }
        return refreshLogNoticesByDay[dayKey]
    }

    func isGeneratingJournal(for dayKey: String?) -> Bool {
        guard let dayKey else { return false }
        if refreshJobsByDay[dayKey]?.inFlight == true {
            return noteIndex[dayKey] == nil
        }
        if onboardingBootstrapState == .pending || onboardingBootstrapState == .inProgress {
            return onboardingBootstrapDayKeys.contains(dayKey) && noteIndex[dayKey] == nil
        }
        return false
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
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
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

        noteIndex = notes.filter { $0.key != OnboardingDemoStory.demoDayKey }
        refreshKnowledgeDocumentTree()
        rebuildAvailableDates()
        switch mainContentSelection {
        case .diary:
            if let selectedDate {
                loadDayPresentation(for: selectedDate)
            } else if let firstDate = availableDates.first {
                setSelectedDiaryDate(firstDate)
                loadDayPresentation(for: firstDate)
            }
        case .otherSourceManager, .knowledgeConnector, .knowledgeDocument:
            break
        }
    }

    private func rebuildAvailableDates() {
        let includeDemoDay = onboardingProgress.isComplete || isPresentingOnboardingDemo
        availableDates = JournalListOrdering.orderedDates(
            noteDays: Set(noteIndex.keys),
            placeholderDays: onboardingBootstrapState == .complete ? [] : onboardingBootstrapDayKeys,
            includeDemoDay: includeDemoDay
        )
    }

    func updateNotificationAccessStatus(using reader: any NotificationDatabaseReading) {
        let accessStatus = reader.accessStatus()
        applyNotificationAccessStatus(accessStatus)
    }

    func applyNotificationAccessStatus(_ accessStatus: NotificationDatabaseAccessStatus) {
        notificationStatus.isDatabaseAvailable = accessStatus.isAvailable
        notificationStatus.databasePath = accessStatus.databaseURL?.path
        notificationStatus.availabilityMessage = accessStatus.message
    }

    func startAutomation(runImmediately: Bool = true) {
        automationTimer?.invalidate()
        notificationCatchUpTimer?.invalidate()

        automationTimer = Timer.scheduledTimer(withTimeInterval: automationInterval, repeats: true) { [weak self] _ in
            guard let self else {
                return
            }

            let now = self.currentDate()
            Task { @MainActor in
                await self.checkForUpdatesIfNeeded(force: false, now: now)
                await self.runAutomation(now: now)
            }
        }

        notificationCatchUpTimer = Timer.scheduledTimer(withTimeInterval: notificationSyncInterval, repeats: true) { [weak self] _ in
            guard let self else {
                return
            }

            let now = self.currentDate()
            Task { @MainActor in
                await self.runNotificationCatchUp(now: now)
            }
        }

        if runImmediately {
            Task { @MainActor in
                let now = currentDate()
                await checkForUpdatesIfNeeded(force: true, now: now)
                await runAutomation(now: now)
                await runNotificationCatchUp(now: now)
            }
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

    private func transitionRefreshJob(
        for dayKey: String,
        stage: DayRefreshStage,
        detail: String? = nil,
        error: String? = nil
    ) {
        let resolvedDetail = detail ?? error ?? stage.detail
        var completedStages = refreshJobsByDay[dayKey]?.completedStages ?? []
        if let previousStage = refreshJobsByDay[dayKey]?.stage,
           previousStage.isProgressStep,
           previousStage != stage,
           !completedStages.contains(previousStage) {
            completedStages.append(previousStage)
        }
        if stage == .completed,
           !completedStages.contains(.writingFiles) {
            completedStages.append(.writingFiles)
        }
        refreshJobsByDay[dayKey] = DayRefreshJob(
            dayKey: dayKey,
            stage: stage,
            detail: resolvedDetail,
            error: error,
            completedStages: completedStages,
            summary: stage.isProgressStep ? nil : resolvedDetail
        )
        onRefreshStageChange?(
            DayRefreshJob(
                dayKey: dayKey,
                stage: stage,
                detail: resolvedDetail,
                error: error,
                completedStages: completedStages,
                summary: stage.isProgressStep ? nil : resolvedDetail
            )
        )
    }

    private func refreshSummary(for story: DailyStory) -> String {
        if story.provenance?.generationMode == .model {
            if let engineLabel = story.provenance?.engineLabel {
                return "\(engineLabel) returned successfully"
            }
            return "model returned successfully"
        }
        return "local fallback"
    }

    private func queueEndOfDayReminderBootstrap() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.refreshEndOfDayReminderAuthorizationStatus()
            self.syncEndOfDayReminderRegistration()
        }
    }

    private func syncEndOfDayReminderRegistration() {
        let isEnabled =
            onboardingProgress.isComplete &&
            endOfDayReminderConfig.isEnabled &&
            endOfDayReminderConfig.authorizationStatus == .authorized

        do {
            try endOfDayReminderLaunchAgentManager.endOfDayReminderRegistration(
                executablePath: Bundle.main.executableURL?.path,
                hour: endOfDayReminderConfig.reminderHour,
                minute: endOfDayReminderConfig.reminderMinute,
                isEnabled: isEnabled
            )
        } catch {
            statusMessage = "Evening review reminder setup failed: \(error.localizedDescription)"
        }
    }

    private func persistEndOfDayReminderConfig() {
        endOfDayReminderConfig.save(to: userDefaults)
    }

    private func persistDayReviewStates() {
        let data = try? JSONEncoder().encode(dayReviewStates)
        userDefaults.set(data, forKey: UserDefaultsKeys.dayReviewStates)
        userDefaults.synchronize()
    }

    private func normalizedDayReviewState(for dayKey: String, now: Date) -> DayReviewState {
        var state = dayReviewStates[dayKey] ?? DayReviewState(dayKey: dayKey)
        if let scheduledAt = state.lastReminderScheduledAt,
           state.lastReminderDeliveredAt == nil,
           scheduledAt <= now {
            state.lastReminderDeliveredAt = scheduledAt
        }
        return state
    }

    private func updateDayReviewState(_ state: DayReviewState) {
        dayReviewStates[state.dayKey] = state
        persistDayReviewStates()
    }

    private func clearPendingReminder(for dayKey: String) {
        var state = dayReviewStates[dayKey] ?? DayReviewState(dayKey: dayKey)
        state.lastReminderScheduledAt = nil
        updateDayReviewState(state)
    }

    private func reevaluateTodayEndOfDayReminder(now: Date) async {
        await reevaluateEndOfDayReminder(for: ISO8601DayKey.format(now), now: now)
    }

    private func reevaluateEndOfDayReminder(
        for dayKey: String,
        now: Date,
        story: DailyStory? = nil,
        events: [EventRecord]? = nil
    ) async {
        guard dayKey == ISO8601DayKey.format(now) else { return }
        guard let environment else { return }

        var state = normalizedDayReviewState(for: dayKey, now: now)
        let persistedStory = story ?? ((try? environment.loadDailyStory(dayKey: dayKey)) ?? nil)
        updateDayReviewState(state)

        let decision = endOfDayReminderPlanner.plan(
            context: EndOfDayReminderPlanContext(
                dayKey: dayKey,
                now: now,
                config: endOfDayReminderConfig,
                hasStory: persistedStory != nil,
                lastReminderScheduledAt: state.lastReminderScheduledAt,
                lastReminderDeliveredAt: state.lastReminderDeliveredAt,
                lastRefreshTriggeredAt: state.lastRefreshTriggeredAt
            )
        )

        switch decision {
        case .noOp:
            return
        case .cancelPending:
            if state.lastReminderScheduledAt != nil {
                await endOfDayReminderService.cancelReminder(for: dayKey)
            }
            clearPendingReminder(for: dayKey)
        case .triggerRefresh:
            state.lastRefreshTriggeredAt = now
            updateDayReviewState(state)
            await generateDailyNote(for: dayKey)
        case .scheduleNotification(let fireDate):
            if state.lastReminderScheduledAt != nil {
                await endOfDayReminderService.cancelReminder(for: dayKey)
            }
            let previousScheduledAt = state.lastReminderScheduledAt
            state.lastReminderScheduledAt = fireDate
            updateDayReviewState(state)
            do {
                try await endOfDayReminderService.scheduleReminder(for: dayKey, at: fireDate)
            } catch {
                state.lastReminderScheduledAt = previousScheduledAt
                updateDayReviewState(state)
                statusMessage = "Evening review reminder unavailable: \(error.localizedDescription)"
            }
        }
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
        refreshActiveSummarizer()
    }

    private func refreshActiveSummarizer() {
        environment?.summarizer = makeSummarizer(defaultEngine, summarizerConfig, processEnvironment)
    }

    private func setAutoSelectionSuppressedByExplicitNone(_ isSuppressed: Bool) {
        autoSelectionSuppressedByExplicitNone = isSuppressed
        userDefaults.set(isSuppressed, forKey: UserDefaultsKeys.explicitlyDisabledSummarizerAutoSelection)
    }

    private func persistLastNotificationImportAt(_ date: Date?, databasePath: String?) {
        lastNotificationImportAt = date
        if let date {
            userDefaults.set(date, forKey: UserDefaultsKeys.lastNotificationImportAt)
            userDefaults.set(databasePath, forKey: UserDefaultsKeys.lastNotificationImportDatabasePath)
        } else {
            userDefaults.removeObject(forKey: UserDefaultsKeys.lastNotificationImportAt)
            userDefaults.removeObject(forKey: UserDefaultsKeys.lastNotificationImportDatabasePath)
        }
    }

    private func restorePersistedNotificationImportAt(using environment: AppEnvironment, now: Date = Date()) {
        guard let persistedDate = userDefaults.object(forKey: UserDefaultsKeys.lastNotificationImportAt) as? Date else {
            lastNotificationImportAt = nil
            return
        }

        let persistedDatabasePath = userDefaults.string(forKey: UserDefaultsKeys.lastNotificationImportDatabasePath)
        guard persistedDatabasePath == environment.databaseURL.path else {
            persistLastNotificationImportAt(nil, databasePath: nil)
            return
        }

        let todayKey = ISO8601DayKey.format(now)
        let hasTodayNotificationEvents = ((try? environment.databaseWriter.fetchEvents(dayKey: todayKey)) ?? [])
            .contains(where: { $0.sourceType == .notification })
        guard hasTodayNotificationEvents else {
            persistLastNotificationImportAt(nil, databasePath: nil)
            return
        }

        lastNotificationImportAt = persistedDate
    }

    private func shouldPersistNotificationWatermark(for result: NotificationImportResult) -> Bool {
        result.accessStatus.isAvailable
    }

    private func makeStoryProvenance(
        mode: StoryGenerationMode,
        engine: DiaryEngine,
        curatedEventCount: Int
    ) -> StoryProvenance {
        StoryProvenance(
            generationMode: mode,
            engineKind: engine.rawValue,
            engineLabel: engine.displayName,
            model: engine == .llmAPI
                ? summarizerConfig.apiModel.trimmingCharacters(in: .whitespacesAndNewlines)
                : nil,
            pipelineVersion: "diary-story-v1",
            curatedEventCount: curatedEventCount
        )
    }

    private func recordActiveEngineRuntime(
        state: EngineIndicatorState,
        detail: String,
        verifiedAt: Date?
    ) {
        recordEngineRuntime(
            for: defaultEngine,
            state: state,
            detail: detail,
            verifiedAt: verifiedAt
        )
    }

    private func recordEngineRuntime(
        for engine: DiaryEngine,
        state: EngineIndicatorState,
        detail: String,
        verifiedAt: Date?
    ) {
        engineStatuses[engine] = EngineRuntimeStatus(
            state: state,
            detail: detail,
            lastVerifiedAt: verifiedAt ?? engineStatuses[engine]?.lastVerifiedAt,
            configurationSignature: Self.configurationSignature(
                for: engine,
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
        case .llmAPI:
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
        case .codexAuth:
            if config.makeSummarizer(for: engine, environment: environment) == nil {
                return EngineRuntimeStatus(
                    state: .gray,
                    detail: "Codex Auth is unavailable.",
                    lastVerifiedAt: nil,
                    configurationSignature: signature
                )
            }
            return EngineRuntimeStatus(
                state: .yellow,
                detail: "Codex Auth not tested. Retest required.",
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
        case .llmAPI:
            let providerConfig = config.activeLLMAPIProviderConfig
            let token = providerConfig.apiToken.trimmingCharacters(in: .whitespacesAndNewlines)
            let tokenSignature = token.isEmpty ? "token:empty" : "token:\(SHA256Hasher.hash(token))"
            return [
                "llmAPI",
                providerConfig.id.rawValue,
                providerConfig.baseURL.trimmingCharacters(in: .whitespacesAndNewlines),
                providerConfig.model.trimmingCharacters(in: .whitespacesAndNewlines),
                providerConfig.wireFormat.rawValue,
                tokenSignature
            ].joined(separator: "|")
        case .codexAuth:
            return "codexAuth|\((environment["CODEX_HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? "~/.codex")"
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

    private static func failureKind(for detail: String?) -> SummarizerRuntimeStatus.FailureKind? {
        guard let detail = detail?.trimmingCharacters(in: .whitespacesAndNewlines), !detail.isEmpty else {
            return nil
        }

        if detail.hasPrefix("Summarizer CLI timed out after") {
            return .timedOut
        }
        if detail.contains("exited with status") {
            return .nonZeroExit
        }
        if detail.contains("returned empty output") {
            return .emptyOutput
        }
        if detail.hasPrefix("Structured repair failed:") {
            return .repairFailed
        }
        if detail == "Story output was not valid structured JSON"
            || detail.contains("not valid structured JSON")
            || detail.contains("invalid structured JSON") {
            return .invalidStructuredOutput
        }

        return nil
    }

    private static func inferEngine(from summarizer: SummaryGenerating?) -> DiaryEngine? {
        switch summarizer {
        case is CloudSummarizer:
            return .llmAPI
        case is CodexDirectSummarizer:
            return .codexAuth
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
            reconciled.defaultEngine = .llmAPI
            reconciled.activeLLMAPIProviderID = summarizer.providerConfig.id
            reconciled.setLLMAPIProviderConfig(summarizer.providerConfig)
        case is CodexDirectSummarizer:
            reconciled.defaultEngine = .codexAuth
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

        return persistedEngine
    }

    private func showOnboardingBootstrapNotice() {
        let notice = OnboardingBootstrapNotice(
            message: "KnowYou is generating today and yesterday from your local context. Come back 2 minutes later."
        )
        onboardingBootstrapNotice = notice
        onboardingBootstrapNoticeDismissTask?.cancel()
        onboardingBootstrapNoticeDismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.onboardingBootstrapNotice?.id == notice.id else { return }
                self.onboardingBootstrapNoticeDismissTask = nil
                self.onboardingBootstrapNotice = nil
            }
        }
    }

    private static func deliverOnboardingBootstrapCompletionNotification(for dayKeys: [String]) async {
        let center = UNUserNotificationCenter.current()
        let authorizationGranted: Bool

        do {
            authorizationGranted = try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            return
        }

        guard authorizationGranted else { return }

        let content = UNMutableNotificationContent()
        content.title = "KnowYou entries are ready"
        content.body = dayKeys.count == 2
            ? "Today and yesterday are ready in KnowYou."
            : "Your new KnowYou entry is ready."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "onboarding-bootstrap-complete",
            content: content,
            trigger: nil
        )

        try? await center.add(request)
    }
}

struct NotificationSyncOutcome {
    let importedCount: Int
    let error: String?
}
