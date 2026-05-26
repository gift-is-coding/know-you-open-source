import SwiftUI
import AppKit

private enum MainWindowMode {
    case journal
    case knowledgeOntology
}

struct MainWindowView: View {
    @Environment(AppState.self) private var appState
    @State private var keyMonitor: Any?
    @State private var isShowingEnginePanel = false
    @State private var isShowingAPIDetail = false
    @State private var apiConfigDraft = SummarizerConfig.load()
    @State private var isTestingAPIConnection = false
    @State private var mode: MainWindowMode = .journal
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
        Group {
            if mode == .knowledgeOntology {
                knowledgeOntologyWorkspace
            } else {
                NavigationSplitView {
                    sidebar
                        .navigationSplitViewColumnWidth(min: 180, ideal: 220)
                } content: {
                    Group {
                        switch appState.mainContentSelection {
                        case .diary:
                            diaryReaderView
                        case .otherSourceManager(let focusAddConnector):
                            otherSourceManagementView(focusAddConnector: focusAddConnector)
                        case .knowledgeConnector(let instanceID):
                            knowledgeSourceView(connectorInstanceID: instanceID)
                        case .knowledgeDocument(let instanceID, _):
                            knowledgeSourceView(connectorInstanceID: instanceID)
                        }
                    }
                } detail: {
                    detailPane
                }
            }
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
                DiaryEngineSelectorButton(
                    title: currentEngineTitle,
                    state: currentEngineState,
                    emphasized: showsOnboardingEngineButton || !appState.summarizerStatus.isConfigured,
                    action: openEngineSelector
                )
                .onboardingCoachmarkTarget(.engineButton)
                .popover(isPresented: $isShowingEnginePanel, arrowEdge: .top) {
                    DiaryEnginePanel(
                        rows: engineRows,
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
            APIDetailSheet(
                config: $apiConfigDraft,
                status: appState.engineStatuses[.openAI] ?? EngineRuntimeStatus(),
                isTesting: isTestingAPIConnection,
                onClose: {
                    isShowingAPIDetail = false
                },
                onSave: {
                    saveAPIConfig()
                    isShowingAPIDetail = false
                },
                onTest: testAPIConnection
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
            isActive: mode == .journal && appState.readerFocus == .dateList,
            isKnowledgeOntologySelected: mode == .knowledgeOntology,
            onSelectDiaryDate: { dayKey in
                mode = .journal
                appState.selectDate(dayKey)
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
            onOpenSyncMemory: openSyncMemoryPanel
        )
    }

    private var knowledgeOntologyWorkspace: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 228)

            Divider()

            KnowledgeOntologyPanel(
                sourceVault: appState.environment?.vaultURL,
                projectRoot: knowledgeOntologyProjectRoot,
                developmentSourceURL: KnowledgeOntologyLauncher.defaultDevelopmentSourceURL(),
                bundledHelperAppURL: KnowledgeOntologyLauncher.defaultBundledHelperAppURL(),
                selectedEntry: $selectedMyWikiEntry
            )
            .frame(minWidth: 860, maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.black)
    }

    private var currentEngineTitle: String {
        appState.defaultEngine == .none ? "Select Engine" : appState.defaultEngine.displayName
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
            onSelectParagraph: { paragraphID in
                appState.focusStoryParagraphs()
                appState.selectStoryParagraph(paragraphID)
                onStoryParagraphTap?(paragraphID)
            },
            onFocusStory: {
                appState.focusStoryParagraphs()
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
            switch appState.mainContentSelection {
            case .diary:
                StorySourceDetailView(
                    selectedParagraph: appState.selectedStoryParagraph,
                    selectedEvents: appState.selectedStorySourceEvents,
                    allEvents: appState.selectedDayEvents
                )
                .navigationSplitViewColumnWidth(min: 320, ideal: 360, max: 420)
                .onboardingCoachmarkTarget(.sourcesPanel)
            case .otherSourceManager, .knowledgeConnector, .knowledgeDocument:
                Color.clear
                    .navigationSplitViewColumnWidth(min: 0, ideal: 0, max: 0)
            }
        }
    }

    private var selectedSidebarItemID: String? {
        switch appState.mainContentSelection {
        case .diary(let dayKey):
            return dayKey.map { "diary:\($0)" } ?? "diary-root"
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
        apiConfigDraft.defaultEngine = .openAI
        isShowingEnginePanel = false
        isShowingAPIDetail = true
    }

    private func saveAPIConfig() {
        var config = apiConfigDraft
        config.defaultEngine = .openAI
        appState.applyEngineConfig(config)
        apiConfigDraft = config
    }

    private func testAPIConnection() {
        saveAPIConfig()
        isTestingAPIConnection = true
        Task { @MainActor in
            await appState.retestEngine(.openAI)
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

struct OnboardingBootstrapNoticePresentation: Equatable {
    let title: String
    let message: String

    init(notice: OnboardingBootstrapNotice) {
        title = "First entries are generating"
        message = notice.message
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
