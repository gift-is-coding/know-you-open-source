import SwiftUI
import AppKit

private enum MainWindowMode {
    case home
    case journal
    case knowledgeOntology
    case networkingComingSoon
}

enum MainWindowWorkspacePolicy {
    static let usesUnifiedNavigationSplitViewAcrossModes = true
    static let keepsEngineSelectorInGlobalToolbar = true
    static let showsPrivacyMessageOutsideEngineSelector = true
    static let privacyMessage = "Your data stays local. No backend server."
    static let privacyMessageFontSize: CGFloat = 14
}

struct MainWindowView: View {
    @Environment(AppState.self) private var appState
    @State private var keyMonitor: Any?
    @State private var isShowingEnginePanel = false
    @State private var isShowingAPIDetail = false
    @State private var apiConfigDraft = SummarizerConfig.load()
    @State private var apiProviderStatuses: [LLMAPIProviderID: EngineRuntimeStatus] = [:]
    @State private var isTestingAPIConnection = false
    @State private var mode: MainWindowMode = .home
    @State private var selectedMyWikiEntry: MyWikiEntry?
    let showsOnboardingEngineButton: Bool
    let onOpenEngineSetup: (() -> Void)?
    let onStoryParagraphTap: ((String) -> Void)?

    init(
        showsOnboardingEngineButton: Bool = false,
        onOpenEngineSetup: (() -> Void)? = nil,
        onStoryParagraphTap: ((String) -> Void)? = nil
    ) {
        self.showsOnboardingEngineButton = showsOnboardingEngineButton
        self.onOpenEngineSetup = onOpenEngineSetup
        self.onStoryParagraphTap = onStoryParagraphTap
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        } content: {
            mainContentPane
        } detail: {
            detailPane
        }
        .frame(minWidth: 1240, minHeight: 720)
        .overlay(alignment: .top) {
            if let notice = appState.onboardingBootstrapNotice {
                OnboardingBootstrapNoticeView(
                    presentation: OnboardingBootstrapNoticePresentation(notice: notice),
                    onDismiss: appState.dismissOnboardingBootstrapNotice
                )
                .padding(.top, 16)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            Text(AppBuildMetadata.current.badgeText)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(12)
                .allowsHitTesting(false)
                .accessibilityIdentifier("build-version-badge")
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                if let offer = appState.updateOffer {
                    UpdatePillView(title: offer.pillTitle) {
                        appState.openUpdateSheet()
                    }
                }
            }
            ToolbarItemGroup(placement: .primaryAction) {
                let engineToolbarPresentation = engineToolbarPresentation
                DiaryEngineSelectorButton(
                    title: engineToolbarPresentation.title,
                    state: engineToolbarPresentation.state,
                    emphasized: showsOnboardingEngineButton || engineToolbarPresentation.emphasized,
                    attentionSystemImage: engineToolbarPresentation.attentionSystemImage,
                    action: openEngineSelector
                )
                .onboardingCoachmarkTarget(.engineButton)
                .popover(isPresented: $isShowingEnginePanel, arrowEdge: .top) {
                    DiaryEnginePanel(
                        rows: engineRows,
                        recoveryNudge: engineRecoveryNudge,
                        isRetestingAll: appState.isRetestingEngines,
                        onSelectDefault: { engine in
                            appState.selectDefaultEngine(engine)
                            isShowingEnginePanel = false
                        },
                        onRetestEngine: { engine in
                            Task { @MainActor in
                                await appState.retestEngine(engine)
                            }
                        },
                        onRetestAll: {
                            Task { @MainActor in
                                await appState.retestAllEngines()
                            }
                        },
                        onConfigureAPI: {
                            openAPIDetail()
                        }
                    )
                }
            }
        }
        .sheet(
            isPresented: Binding(
                get: { appState.isShowingUpdateSheet },
                set: { isPresented in
                    if isPresented {
                        appState.openUpdateSheet()
                    } else {
                        appState.dismissUpdateSheet()
                    }
                }
            )
        ) {
            if let offer = appState.updateOffer {
                UpdateSheet(
                    currentVersion: AppBuildMetadata.current.marketingVersion,
                    offer: offer,
                    onPrimaryAction: {
                        appState.performUpdatePrimaryAction()
                    },
                    onClose: {
                        appState.dismissUpdateSheet()
                    }
                )
            }
        }
        .sheet(isPresented: $isShowingAPIDetail) {
            LLMAPIDetailSheet(
                config: $apiConfigDraft,
                activeStatus: appState.engineStatuses[.llmAPI] ?? EngineRuntimeStatus(),
                providerStatuses: apiProviderStatuses,
                isTesting: isTestingAPIConnection,
                onClose: {
                    isShowingAPIDetail = false
                },
                onSave: {
                    saveAPIConfig()
                    isShowingAPIDetail = false
                },
                onTestProvider: testAPIProvider,
                onSetActive: setActiveAPIProvider
            )
        }
        .sheet(
            isPresented: Binding(
                get: { appState.isShowingSyncMemoryPanel },
                set: { isPresented in
                    if isPresented {
                        appState.openSyncMemoryPanel()
                    } else {
                        appState.closeSyncMemoryPanel()
                    }
                }
            )
        ) {
            connectorsManagementSheet()
        }
        .onAppear {
            startKeyMonitor()
        }
        .onDisappear {
            stopKeyMonitor()
        }
    }

    private var sidebar: some View {
        DateSidebarView(
            dates: appState.availableDates,
            selectedDate: appState.selectedDate,
            selectedItemID: selectedSidebarItemID,
            knowledgeImportConfig: appState.knowledgeImportConfig,
            knowledgeDocumentsByConnector: appState.knowledgeDocumentsByConnector,
            isActive: mode == .home || mode == .knowledgeOntology || mode == .networkingComingSoon || (mode == .journal && appState.readerFocus == .dateList),
            isKnowledgeOntologySelected: mode == .knowledgeOntology,
            todoOpenCount: appState.openTodoCount,
            onOpenHome: {
                mode = .home
            },
            onSelectDiaryDate: { dayKey in
                mode = .journal
                appState.selectDate(dayKey)
            },
            onOpenTodo: {
                mode = .journal
                appState.openTodoInbox()
            },
            onSelectOtherSource: { focusAddConnector in
                mode = .journal
                appState.selectOtherSourceManager(focusAddConnector: focusAddConnector)
            },
            onSelectKnowledgeConnector: { instanceID in
                mode = .journal
                appState.selectKnowledgeConnector(instanceID: instanceID)
            },
            onSelectKnowledgeDocument: { instanceID, documentID in
                mode = .journal
                appState.selectKnowledgeDocument(connectorInstanceID: instanceID, documentID: documentID)
            },
            onOpenKnowledgeOntology: {
                mode = .knowledgeOntology
            },
            onOpenNetworkingComingSoon: {
                mode = .networkingComingSoon
            },
            onOpenSyncMemory: openSyncMemoryPanel
        )
    }

    @ViewBuilder
    private var mainContentPane: some View {
        if mode == .home {
            homeDashboardContent
        } else if mode == .knowledgeOntology {
            knowledgeOntologyContent
        } else if mode == .networkingComingSoon {
            networkingComingSoonContent
        } else {
            switch appState.mainContentSelection {
            case .diary:
                diaryReaderView
            case .todo:
                TodoInboxView(
                    items: appState.todoItems,
                    reviewCandidates: appState.todoReviewCandidates,
                    closeRecommendations: appState.todoCloseRecommendations,
                    automationStatusMessage: appState.todoAutomationStatusMessage,
                    nextUpdateDate: appState.nextTodoAutomationCheckDate,
                    lastUpdateDate: appState.automationJobSnapshots.first(where: { $0.kind == .todo })?.lastRunAt,
                    isUpdating: appState.isUpdatingTodoNow,
                    onAdd: { title in
                        appState.addTodo(title: title)
                    },
                    onAddCandidate: { id in
                        appState.addTodoCandidate(id: id)
                    },
                    onDismissCandidate: { id in
                        appState.dismissTodoReviewCandidate(id: id)
                    },
                    onToggleCompletion: { id in
                        appState.toggleTodoItemCompletion(id: id)
                    },
                    onUpdateTitle: { id, title in
                        appState.updateTodoItemTitle(id: id, title: title)
                    },
                    onDelete: { id in
                        appState.deleteTodoItem(id: id)
                    },
                    onCloseRecommendation: { id in
                        appState.closeTodoRecommendation(id: id)
                    },
                    onKeepRecommendation: { id in
                        appState.keepTodoCloseRecommendation(id: id)
                    },
                    onUpdateNow: {
                        Task { @MainActor in
                            await appState.runTodayTodoAutomationNow()
                        }
                    }
                )
            case .otherSourceManager(let focusAddConnector):
                otherSourceManagementView(focusAddConnector: focusAddConnector)
            case .knowledgeConnector(let instanceID):
                knowledgeSourceView(connectorInstanceID: instanceID)
            case .knowledgeDocument(let instanceID, _):
                knowledgeSourceView(connectorInstanceID: instanceID)
            }
        }
    }

    private var homeDashboardContent: some View {
        HomeDashboardView(
            nextDiaryCheckDate: appState.nextDiaryAutomationCheckDate ?? Date().addingTimeInterval(10_800),
            missingRecentDayCount: appState.missingRecentHistoryBootstrapDayKeys.count,
            jobSnapshots: appState.automationJobSnapshots,
            onOpenToday: {
                mode = .journal
                appState.selectDate(ISO8601DayKey.format(Date()))
            },
            onGenerateToday: {
                mode = .journal
                appState.selectDate(ISO8601DayKey.format(Date()))
                Task { @MainActor in
                    await appState.refreshSelectedDay()
                }
            },
            onOpenTodo: {
                mode = .journal
                appState.openTodoInbox()
            },
            onOpenMyWiki: {
                mode = .knowledgeOntology
            },
            onAddSources: {
                mode = .journal
                appState.selectOtherSourceManager(focusAddConnector: true)
            },
            onOpenNetworking: {
                mode = .networkingComingSoon
            },
            onGenerateRecentHistory: {
                _ = appState.queueRecentHistoryBootstrapIfNeeded(force: true)
            }
        )
    }

    private var networkingComingSoonContent: some View {
        NetworkingPreviewView(presentation: NetworkingPreviewPresentation())
    }

    private var knowledgeOntologyContent: some View {
        ZStack {
            Color.black
            KnowledgeOntologyPanel(
                sourceVault: appState.environment?.vaultURL,
                projectRoot: knowledgeOntologyProjectRoot,
                developmentSourceURL: KnowledgeOntologyLauncher.defaultDevelopmentSourceURL(),
                bundledHelperAppURL: KnowledgeOntologyLauncher.defaultBundledHelperAppURL(),
                importedDocuments: appState.knowledgeDocumentsByConnector.values.flatMap { $0 },
                nextDigestUpdateDate: appState.nextMyWikiAutomationCheckDate,
                selectedEntry: $selectedMyWikiEntry
            )
            .frame(minWidth: 860, maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var currentEngineTitle: String {
        appState.defaultEngine == .none ? "Select Engine" : appState.defaultEngine.displayName
    }

    private var engineToolbarPresentation: DiaryEngineToolbarPresentation {
        DiaryEngineToolbarPresentation.make(
            defaultEngine: appState.defaultEngine,
            engineStatuses: appState.engineStatuses,
            retestingEngines: appState.retestingEngines
        )
    }

    private var engineRecoveryNudge: DiaryEngineRecoveryNudgePresentation? {
        DiaryEngineRecoveryNudgePresentation.make(
            defaultEngine: appState.defaultEngine,
            engineStatuses: appState.engineStatuses
        )
    }

    private var selectedRefreshJob: DayRefreshJob? {
        guard let selectedDate = appState.selectedDate else { return nil }
        return appState.refreshJob(for: selectedDate)
    }

    private var knowledgeOntologyProjectRoot: URL? {
        appState.environment?.vaultURL
            .deletingLastPathComponent()
            .appending(path: "KnowledgeOntology/KnowYouContext", directoryHint: .isDirectory)
    }

    private var diaryReaderView: some View {
        DailyMarkdownView(
            story: appState.selectedStory,
            selectedParagraphID: appState.selectedStoryParagraphID,
            dayKey: appState.selectedDate,
            refreshJob: selectedRefreshJob,
            refreshLogNotice: appState.refreshLogNotice(for: appState.selectedDate),
            isGenerating: appState.isGeneratingJournal(for: appState.selectedDate),
            isActive: appState.readerFocus == .storyParagraphs,
            todoCandidates: appState.selectedTodoCandidatePresentations,
            onSelectParagraph: { paragraphID in
                appState.focusStoryParagraphs()
                appState.selectStoryParagraph(paragraphID)
                onStoryParagraphTap?(paragraphID)
            },
            onFocusStory: {
                appState.focusStoryParagraphs()
            },
            onAddTodoCandidate: { candidateID in
                appState.addTodoCandidate(id: candidateID)
            },
            onRefresh: {
                Task { @MainActor in
                    await appState.refreshSelectedDay()
                }
            },
            onTodayFullRefresh: {
                Task { @MainActor in
                    await appState.refreshSelectedDayFullRecovery()
                }
            },
            canFullRefresh: appState.selectedDate != nil && appState.selectedDate != OnboardingDemoStory.demoDayKey,
            fullRefreshMenuTitle: appState.selectedDate == ISO8601DayKey.format(Date())
                ? "Full Refresh Today (Overwriting)"
                : "Full Refresh (Overwriting)"
        )
        .onboardingCoachmarkTarget(.storyPanel)
    }

    private var detailPane: some View {
        Group {
            if mode == .home || mode == .knowledgeOntology || mode == .networkingComingSoon {
                Color.clear
                    .navigationSplitViewColumnWidth(min: 0, ideal: 0, max: 0)
            } else {
                switch appState.mainContentSelection {
                case .diary:
                    StorySourceDetailView(
                        selectedParagraph: appState.selectedStoryParagraph,
                        selectedEvents: appState.selectedStorySourceEvents,
                        allEvents: appState.selectedDayEvents
                    )
                    .navigationSplitViewColumnWidth(min: 320, ideal: 360, max: 420)
                    .onboardingCoachmarkTarget(.sourcesPanel)
                case .todo, .otherSourceManager, .knowledgeConnector, .knowledgeDocument:
                    Color.clear
                        .navigationSplitViewColumnWidth(min: 0, ideal: 0, max: 0)
                }
            }
        }
    }

    private var selectedSidebarItemID: String? {
        if mode == .home {
            return "home"
        } else if mode == .knowledgeOntology {
            return "my-wiki"
        } else if mode == .networkingComingSoon {
            return "networking"
        }
        switch appState.mainContentSelection {
        case .diary(let dayKey):
            return dayKey.map { "diary:\($0)" } ?? "diary-root"
        case .todo:
            return "todo-root"
        case .otherSourceManager:
            return "add-source"
        case .knowledgeConnector(let instanceID):
            return "connector:\(instanceID)"
        case .knowledgeDocument(let instanceID, _):
            if let documentID = appState.selectedKnowledgeDocument?.id {
                return "document:\(instanceID):\(documentID)"
            }
            return "connector:\(instanceID)"
        }
    }

    private var currentEngineState: EngineIndicatorState {
        appState.engineStatuses[appState.defaultEngine]?.state ?? .gray
    }

    private var knowledgeImportEnabledBinding: Binding<Bool> {
        Binding(
            get: { appState.knowledgeImportConfig.isImportEnabled },
            set: { isEnabled in
                var config = appState.knowledgeImportConfig
                config.isImportEnabled = isEnabled
                appState.saveKnowledgeImportConfig(config)
            }
        )
    }

    private var knowledgeImportTimeBinding: Binding<Date> {
        Binding(
            get: {
                var components = DateComponents()
                components.hour = appState.knowledgeImportConfig.dailyImportHour
                components.minute = appState.knowledgeImportConfig.dailyImportMinute
                return Calendar.current.date(from: components) ?? Date()
            },
            set: { date in
                let components = Calendar.current.dateComponents([.hour, .minute], from: date)
                var config = appState.knowledgeImportConfig
                config.dailyImportHour = components.hour ?? 7
                config.dailyImportMinute = components.minute ?? 30
                appState.saveKnowledgeImportConfig(config)
            }
        )
    }

    private var engineRows: [DiaryEnginePanelRow] {
        DiaryEngine.allCases
            .filter { $0 != .none }
            .map { engine in
                DiaryEnginePanelRow(
                    engine: engine,
                    status: appState.engineStatuses[engine] ?? EngineRuntimeStatus(),
                    isDefault: appState.defaultEngine == engine,
                    isRetesting: appState.retestingEngines.contains(engine)
                )
            }
    }

    private func startKeyMonitor() {
        guard keyMonitor == nil else { return }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak appState] event in
            guard let appState else { return event }
            let handled = handleKeyEvent(event, appState: appState)
            return handled ? nil : event
        }
    }

    private func stopKeyMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    @MainActor
    private func handleKeyEvent(_ event: NSEvent, appState: AppState) -> Bool {
        switch appState.readerFocus {
        case .dateList:
            switch event.keyCode {
            case 126: appState.handleReaderMove(.up);    return true  // ↑
            case 125: appState.handleReaderMove(.down);  return true  // ↓
            case 124: appState.handleReaderMove(.right); return true  // →
            case 36:  appState.handleReaderMove(.right); return true  // Return
            default:  return false
            }
        case .storyParagraphs:
            switch event.keyCode {
            case 126: appState.handleReaderMove(.up);   return true  // ↑
            case 125: appState.handleReaderMove(.down); return true  // ↓
            case 123: appState.handleReaderMove(.left); return true  // ←
            case 53:  appState.handleReaderExit();      return true  // Escape
            default:  return false
            }
        }
    }

    private func openEnginePanel() {
        isShowingEnginePanel = true
    }

    private func openEngineSelector() {
        if let onOpenEngineSetup {
            onOpenEngineSetup()
        } else {
            openEnginePanel()
            if engineRecoveryNudge?.kind == .repairRequired {
                Task { @MainActor in
                    _ = await appState.repairDefaultEngineIfNeeded()
                }
            }
        }
    }

    private func openSyncMemoryPanel() {
        appState.openSyncMemoryPanel()
    }

    private func connectorsManagementView(focusAddConnector: Bool) -> some View {
        connectorsManagementView(
            managementPresentation: connectorsManagementPresentation(
                focusAddConnector: focusAddConnector
            )
        )
    }

    private func otherSourceManagementView(focusAddConnector: Bool) -> some View {
        GeometryReader { proxy in
            ScrollView {
                connectorsManagementView(focusAddConnector: focusAddConnector)
                    .padding(28)
                    .frame(maxWidth: 860, alignment: .topLeading)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
    }

    private func knowledgeSourceView(connectorInstanceID: String) -> some View {
        let connector = appState.knowledgeImportConfig.connectorInstances.first { $0.id == connectorInstanceID }
        return Group {
            if let connector {
                KnowledgeSourceContentView(
                    presentation: KnowledgeSourceContentPresentation(
                        connector: connector,
                        documents: appState.selectedKnowledgeDocuments,
                        selectedDocumentID: appState.selectedKnowledgeDocument?.id,
                        selectedMarkdown: appState.selectedKnowledgeDocumentMarkdown,
                        statusMessage: appState.knowledgeImportStatusMessage
                    )
                )
            } else {
                Text("Connector not found")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func connectorsManagementSheet() -> some View {
        VStack(alignment: .leading, spacing: 18) {
            connectorsManagementView(focusAddConnector: false)

            HStack {
                Spacer()
                Button("Close") {
                    appState.closeSyncMemoryPanel()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 560, minHeight: 430)
    }

    private func connectorsManagementPresentation(focusAddConnector: Bool) -> ConnectorsManagementPresentation {
        ConnectorsManagementPresentation(
            panelPresentation: ConnectorsPanelPresentation(
                syncMemoryConfig: appState.syncMemoryConfig,
                knowledgeImportConfig: appState.knowledgeImportConfig,
                syncMemoryStatusMessage: appState.syncMemoryStatusMessage,
                knowledgeImportStatusMessage: appState.knowledgeImportStatusMessage
            ),
            surface: .otherSourceRoot,
            externalSourcesRootURL: appState.environment?.externalSourcesDirectoryURL
                ?? ExternalSourcePromptPresentation.defaultExternalSourcesRootURL()
        )
    }

    private func connectorsManagementView(
        managementPresentation: ConnectorsManagementPresentation
    ) -> some View {
        ConnectorsManagementView(
            managementPresentation: managementPresentation,
            isAutoImportEnabled: knowledgeImportEnabledBinding,
            dailyImportTime: knowledgeImportTimeBinding,
            onChooseObsidianExport: { chooseSyncMemoryFolder(for: .obsidian) },
            onChooseOpenClawExport: { chooseSyncMemoryFolder(for: .openClaw) },
            onOpenObsidianExport: { openSyncMemoryFolder(at: appState.syncMemoryConfig.obsidian.resolvedPath) },
            onOpenOpenClawExport: { openSyncMemoryFolder(at: appState.syncMemoryConfig.openClaw.resolvedPath) },
            onAddLocalFolderImport: { chooseKnowledgeImportFolder(for: .localFolderImport) },
            onAddObsidianImport: { chooseKnowledgeImportFolder(for: .obsidianImport) },
            onAddExternalPromptSource: addExternalPromptSource,
            onSetImportConnectorEnabled: setKnowledgeImportConnectorEnabled,
            onDeleteImportConnector: deleteKnowledgeImportConnector,
            onExportNow: {
                appState.syncMemoryNow()
            },
            onImportNow: {
                Task { @MainActor in
                    await appState.importKnowledgeNow()
                }
            }
        )
    }

    private func openAPIDetail() {
        apiConfigDraft = SummarizerConfig.load()
        apiConfigDraft.defaultEngine = .llmAPI
        apiProviderStatuses = [
            apiConfigDraft.activeLLMAPIProviderID: appState.engineStatuses[.llmAPI] ?? EngineRuntimeStatus()
        ]
        isShowingEnginePanel = false
        isShowingAPIDetail = true
    }

    private func saveAPIConfig() {
        var config = apiConfigDraft
        config.defaultEngine = .llmAPI
        appState.applyEngineConfig(config)
        apiConfigDraft = config
        apiProviderStatuses[config.activeLLMAPIProviderID] = appState.engineStatuses[.llmAPI] ?? EngineRuntimeStatus()
    }

    private func setActiveAPIProvider(_ providerID: LLMAPIProviderID) {
        apiConfigDraft.activeLLMAPIProviderID = providerID
        saveAPIConfig()
    }

    private func testAPIProvider(_ providerID: LLMAPIProviderID) {
        saveAPIConfig()
        let draft = apiConfigDraft
        isTestingAPIConnection = true
        Task { @MainActor in
            let status = await appState.testLLMAPIProvider(providerID, draftConfig: draft)
            apiProviderStatuses[providerID] = status
            isTestingAPIConnection = false
        }
    }

    private func chooseSyncMemoryFolder(for channel: SyncMemoryChannel) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Select Folder"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }

            let resolvedPath: String
            switch channel {
            case .obsidian:
                resolvedPath = url
                    .appendingPathComponent("KnowYou", isDirectory: true)
                    .appendingPathComponent("Daily Memories", isDirectory: true)
                    .path
            case .openClaw:
                resolvedPath = url
                    .appendingPathComponent("know-you-memory", isDirectory: true)
                    .path
            }
            appState.updateSyncMemoryChannel(channel, resolvedPath: resolvedPath)
        }
    }

    private func chooseKnowledgeImportFolder(for connectorID: KnowledgeConnectorID) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.prompt = "Add"
        if connectorID == .obsidianImport, let detectedVault = detectedObsidianVault() {
            panel.directoryURL = detectedVault.deletingLastPathComponent()
            panel.nameFieldStringValue = detectedVault.lastPathComponent
        }
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            addKnowledgeImportConnector(
                connectorID: connectorID,
                displayName: connectorID == .obsidianImport ? "Obsidian Vault" : url.lastPathComponent,
                sourcePath: url.path,
                accountID: nil
            )
        }
    }

    private func detectedObsidianVault() -> URL? {
        let detector = SyncMemoryPathDetector()
        let homeURL = FileManager.default.homeDirectoryForCurrentUser
        let configuredVaults = detector.detectConfiguredObsidianVaults(
            configDirectory: detector.defaultObsidianConfigDirectory(homePath: homeURL.path)
        )
        if let configuredVault = configuredVaults.first {
            return configuredVault
        }

        return detector.detectObsidianVaults(
            searchRoots: [
                homeURL.appendingPathComponent("Documents", isDirectory: true),
                homeURL.appendingPathComponent("Desktop", isDirectory: true),
            ]
        ).first
    }

    private func addKnowledgeImportConnector(
        connectorID: KnowledgeConnectorID,
        displayName: String,
        sourcePath: String?,
        accountID: String?
    ) {
        let connectorInstanceID = "\(connectorID.rawValue)-\(UUID().uuidString)"

        var config = appState.knowledgeImportConfig
        config.connectorInstances.append(
            KnowledgeConnectorInstanceConfig(
                id: connectorInstanceID,
                connectorID: connectorID,
                displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
                sourcePath: sourcePath?.trimmingCharacters(in: .whitespacesAndNewlines),
                accountID: accountID?.trimmingCharacters(in: .whitespacesAndNewlines),
                isEnabled: true
            )
        )
        appState.saveKnowledgeImportConfig(config)
    }

    private func addExternalPromptSource(
        connectorID: KnowledgeConnectorID,
        displayName: String,
        sourcePath: String
    ) {
        let sourceURL = URL(fileURLWithPath: sourcePath, isDirectory: true)
        try? FileManager.default.createDirectory(at: sourceURL, withIntermediateDirectories: true)

        var config = appState.knowledgeImportConfig
        if let index = config.connectorInstances.firstIndex(where: { $0.connectorID == connectorID }) {
            config.connectorInstances[index].displayName = displayName
            config.connectorInstances[index].sourcePath = sourcePath
            config.connectorInstances[index].accountID = nil
            config.connectorInstances[index].workspaceID = nil
            config.connectorInstances[index].isEnabled = true
        } else {
            config.connectorInstances.append(
                KnowledgeConnectorInstanceConfig(
                    id: "\(connectorID.rawValue)-\(UUID().uuidString)",
                    connectorID: connectorID,
                    displayName: displayName,
                    sourcePath: sourcePath,
                    accountID: nil,
                    workspaceID: nil,
                    isEnabled: true
                )
            )
        }
        appState.saveKnowledgeImportConfig(config)
    }

    private func setKnowledgeImportConnectorEnabled(id: String, isEnabled: Bool) {
        var config = appState.knowledgeImportConfig
        guard let index = config.connectorInstances.firstIndex(where: { $0.id == id }) else {
            return
        }
        config.connectorInstances[index].isEnabled = isEnabled
        appState.saveKnowledgeImportConfig(config)
    }

    private func deleteKnowledgeImportConnector(id: String) {
        var config = appState.knowledgeImportConfig
        config.connectorInstances.removeAll { $0.id == id }
        appState.deleteKnowledgeImportBearerToken(connectorInstanceID: id)
        appState.saveKnowledgeImportConfig(config)
        appState.didDeleteKnowledgeConnector(instanceID: id)
    }

    private func openSyncMemoryFolder(at path: String?) {
        guard let path, path.isEmpty == false else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: path, isDirectory: true))
    }
}

struct HomeFeatureCardPresentation: Equatable, Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let systemImage: String
}

struct HomeJobRowPresentation: Equatable, Identifiable {
    let id: AutomationJobKind
    let title: String
    let statusText: String
    let detail: String
    let progress: Double?
    let lastRunText: String?
    let nextRunText: String?
    let systemImage: String

    init(snapshot: AutomationJobSnapshot, displayTimeZone: TimeZone = .current) {
        id = snapshot.kind
        title = snapshot.title
        statusText = snapshot.status.displayText
        detail = snapshot.detail
        progress = snapshot.progress
        lastRunText = snapshot.lastRunAt.map { "Last \(Self.timeText(for: $0, timeZone: displayTimeZone))" }
        nextRunText = snapshot.nextRunAt.map { "Next \(Self.timeText(for: $0, timeZone: displayTimeZone))" }
        systemImage = switch snapshot.kind {
        case .diary:
            "book.pages"
        case .todo:
            "checklist"
        case .wiki:
            "point.3.connected.trianglepath.dotted"
        }
    }

    private static func timeText(for date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        return formatter.string(from: date)
            .replacingOccurrences(of: "\u{202F}", with: " ")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
    }
}

struct HomeDashboardPresentation: Equatable {
    let heroTitle = "KnowYou works quietly in the background."
    let nextCheckTitle = "Automatic Diary update"
    let nextCheckValue: String
    let generateTodayActionTitle = "Generate Now"
    let primaryActionTitle = "Generate Last 3 Days"
    let visualAssetName = "HomeDashboardHero"
    let activeJobsTitle = "Updating"
    let jobRows: [HomeJobRowPresentation]
    let featureCards: [HomeFeatureCardPresentation]
    let missingRecentDayCount: Int
    let showsRecentHistoryAction: Bool

    init(
        nextDiaryCheckDate: Date,
        now: Date,
        missingRecentDayCount: Int,
        jobSnapshots: [AutomationJobSnapshot] = [],
        displayTimeZone: TimeZone = .current
    ) {
        self.nextCheckValue = Self.checkTimeText(for: nextDiaryCheckDate, timeZone: displayTimeZone)
        self.missingRecentDayCount = missingRecentDayCount
        self.showsRecentHistoryAction = missingRecentDayCount > 0
        self.jobRows = jobSnapshots
            .filter { Self.shouldShowJob($0.status) }
            .sorted { $0.kind.sortIndex < $1.kind.sortIndex }
            .map { HomeJobRowPresentation(snapshot: $0, displayTimeZone: displayTimeZone) }
        self.featureCards = [
            HomeFeatureCardPresentation(
                id: "networking",
                title: "Networking (Coming soon)",
                subtitle: "Create separate profiles for work, hiring, social, and founder moments when you are ready to share.",
                systemImage: "network"
            ),
            HomeFeatureCardPresentation(
                id: "todo",
                title: "Todo",
                subtitle: "Turn loose follow-ups into a simple inbox, then keep, close, or track them across days.",
                systemImage: "checklist"
            ),
            HomeFeatureCardPresentation(
                id: "wiki",
                title: "My Wiki",
                subtitle: "Turn diaries and selected sources into people, projects, patterns, and searchable memory.",
                systemImage: "point.3.connected.trianglepath.dotted"
            ),
            HomeFeatureCardPresentation(
                id: "today",
                title: "Today’s Diary",
                subtitle: "Generate or refresh today’s diary from local notifications and clipboard context while the app runs.",
                systemImage: "book.pages"
            ),
            HomeFeatureCardPresentation(
                id: "sources",
                title: "Other Source",
                subtitle: "Connect folders or prompt-backed Feishu, Notion, and Google Drive exports for richer context.",
                systemImage: "plus.square.on.square"
            ),
        ]
    }

    private static func checkTimeText(for date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "h:mm a"
        formatter.timeZone = timeZone
        return formatter.string(from: date)
    }

    private static func shouldShowJob(_ status: AutomationJobStatus) -> Bool {
        switch status {
        case .running, .degraded, .failed, .blocked:
            return true
        case .scheduled, .completed:
            return false
        }
    }
}

private struct HomeDashboardView: View {
    let nextDiaryCheckDate: Date
    let missingRecentDayCount: Int
    let jobSnapshots: [AutomationJobSnapshot]
    let onOpenToday: () -> Void
    let onGenerateToday: () -> Void
    let onOpenTodo: () -> Void
    let onOpenMyWiki: () -> Void
    let onAddSources: () -> Void
    let onOpenNetworking: () -> Void
    let onGenerateRecentHistory: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let presentation = HomeDashboardPresentation(
                nextDiaryCheckDate: nextDiaryCheckDate,
                now: context.date,
                missingRecentDayCount: missingRecentDayCount,
                jobSnapshots: jobSnapshots
            )
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    hero(presentation)
                    featureGrid(presentation)
                }
                .padding(28)
                .frame(maxWidth: 980, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor))
        }
    }

    private func hero(_ presentation: HomeDashboardPresentation) -> some View {
        HStack(alignment: .center, spacing: 24) {
            Image(presentation.visualAssetName)
                .resizable()
                .scaledToFill()
                .frame(width: 340, height: 210)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 16) {
                Text(presentation.heroTitle)
                    .font(.system(size: 32, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)

                HStack(alignment: .bottom, spacing: 12) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            Label(presentation.nextCheckTitle, systemImage: "clock.arrow.circlepath")
                                .font(.headline)
                            Text(presentation.nextCheckValue)
                                .font(.title2.monospacedDigit().weight(.semibold))
                        }

                        HStack(spacing: 10) {
                            Button(action: onGenerateToday) {
                                Label(presentation.generateTodayActionTitle, systemImage: "arrow.clockwise")
                            }
                            .buttonStyle(.borderedProminent)

                            if presentation.showsRecentHistoryAction {
                                Button(action: onGenerateRecentHistory) {
                                    Label(presentation.primaryActionTitle, systemImage: "sparkles")
                                }
                                .buttonStyle(.bordered)
                                .help("\(presentation.missingRecentDayCount) recent day(s) need a generated diary.")
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
                    .controlSize(.large)

                    jobList(presentation)
                }
            }
        }
    }

    private func featureGrid(_ presentation: HomeDashboardPresentation) -> some View {
        VStack(spacing: 12) {
            ForEach(presentation.featureCards) { card in
                Button {
                    open(card)
                } label: {
                    HStack(alignment: .center, spacing: 16) {
                        Image(systemName: card.systemImage)
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 34, height: 34)
                            .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))

                        VStack(alignment: .leading, spacing: 5) {
                            Text(card.title)
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Text(card.subtitle)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 12)

                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func jobList(_ presentation: HomeDashboardPresentation) -> some View {
        if presentation.jobRows.isEmpty == false {
            VStack(alignment: .leading, spacing: 8) {
                Text(presentation.activeJobsTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                VStack(spacing: 6) {
                    ForEach(presentation.jobRows) { row in
                        Button {
                            open(row.id)
                        } label: {
                            HStack(alignment: .center, spacing: 8) {
                                Image(systemName: row.systemImage)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Color.accentColor)
                                    .frame(width: 24, height: 24)
                                    .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))

                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Text(row.title)
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.primary)
                                        Text(row.statusText)
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                    }
                                    Text(row.detail)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                    if let progress = row.progress, progress < 1 {
                                        ProgressView(value: progress)
                                            .progressViewStyle(.linear)
                                            .frame(maxWidth: 160)
                                    }
                                }

                                Spacer(minLength: 6)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .frame(width: 260, alignment: .leading)
                            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func open(_ card: HomeFeatureCardPresentation) {
        switch card.id {
        case "today":
            onOpenToday()
        case "todo":
            onOpenTodo()
        case "wiki":
            onOpenMyWiki()
        case "sources":
            onAddSources()
        case "networking":
            onOpenNetworking()
        default:
            break
        }
    }

    private func open(_ kind: AutomationJobKind) {
        switch kind {
        case .diary:
            onOpenToday()
        case .todo:
            onOpenTodo()
        case .wiki:
            onOpenMyWiki()
        }
    }
}

struct NetworkingPreviewPresentation: Equatable {
    let title = "Networking"
    let status = "Coming soon"
    let visualAssetName = "NetworkingPreviewHero"
    let profileLabels = ["Career", "Founder", "Social"]
    let statements = [
        "My Diary and selected sources build My Wiki.",
        "Profiles stay local until you choose what to share.",
        "Data boundary keeps the full wiki out of public platforms.",
    ]

    var visibleCopy: [String] {
        [status, title] + profileLabels + statements
    }
}

private struct NetworkingPreviewView: View {
    let presentation: NetworkingPreviewPresentation

    var body: some View {
        HStack(alignment: .center, spacing: 28) {
            Image(presentation.visualAssetName)
                .resizable()
                .scaledToFill()
                .frame(width: 430, height: 310)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 18) {
                Text(presentation.status)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                Text(presentation.title)
                    .font(.largeTitle.weight(.semibold))
                HStack(spacing: 8) {
                    ForEach(presentation.profileLabels, id: \.self) { label in
                        Text(label)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                ForEach(presentation.statements, id: \.self) { statement in
                    Label(statement, systemImage: "checkmark.circle.fill")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.primary)
                }
            }
            .frame(maxWidth: 460, alignment: .leading)
        }
        .padding(34)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }
}

struct OnboardingBootstrapNoticePresentation: Equatable {
    let title: String
    let message: String
    let progressText: String?

    init(notice: OnboardingBootstrapNotice) {
        title = "First 3 days are generating"
        message = notice.message
        progressText = notice.progress?.presentationText
    }
}

private struct OnboardingBootstrapNoticeView: View {
    let presentation: OnboardingBootstrapNoticePresentation
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "sparkles")
                .font(.headline.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 28, height: 28)
                .background(Color.accentColor.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(presentation.title)
                    .font(.headline)
                Text(presentation.message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if let progressText = presentation.progressText {
                    Text(progressText)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .background(Color.primary.opacity(0.06), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss generation notice")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: Capsule(style: .continuous))
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.16), radius: 20, x: 0, y: 12)
        .padding(.horizontal, 20)
        .transition(.move(edge: .top).combined(with: .opacity))
        .zIndex(1)
    }
}
