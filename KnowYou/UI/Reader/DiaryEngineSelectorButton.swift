import SwiftUI

struct DiaryEngineSelectorButton: View {
    let title: String
    let state: EngineIndicatorState
    let emphasized: Bool
    let attentionSystemImage: String?
    let action: () -> Void

    init(
        title: String,
        state: EngineIndicatorState,
        emphasized: Bool = false,
        attentionSystemImage: String? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.state = state
        self.emphasized = emphasized
        self.attentionSystemImage = attentionSystemImage
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                EngineIndicatorLight(state: state)
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(backgroundStyle, in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(borderColor, lineWidth: emphasized ? 1.5 : 0)
            )
            .overlay(alignment: .topTrailing) {
                if let attentionSystemImage {
                    Image(systemName: attentionSystemImage)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.red)
                        .background(Color(nsColor: .windowBackgroundColor), in: Circle())
                        .offset(x: 5, y: -5)
                        .accessibilityLabel("Diary engine needs attention")
                }
            }
            .shadow(color: emphasized ? Color.accentColor.opacity(0.18) : .clear, radius: 10, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }

    private var backgroundStyle: some ShapeStyle {
        if emphasized {
            return AnyShapeStyle(Color.accentColor.opacity(0.12))
        }
        return AnyShapeStyle(.regularMaterial)
    }

    private var borderColor: Color {
        emphasized ? .accentColor.opacity(0.85) : .clear
    }
}

struct DiaryEngineTitlebarSelector: View {
    let appState: AppState

    @State private var isShowingEnginePanel = false
    @State private var isShowingAPIDetail = false
    @State private var apiConfigDraft = SummarizerConfig.load()
    @State private var apiProviderStatuses: [LLMAPIProviderID: EngineRuntimeStatus] = [:]
    @State private var isTestingAPIConnection = false

    var body: some View {
        let presentation = engineToolbarPresentation

        DiaryEngineSelectorButton(
            title: presentation.title,
            state: presentation.state,
            emphasized: presentation.emphasized,
            attentionSystemImage: presentation.attentionSystemImage,
            action: openEngineSelector
        )
        .onboardingCoachmarkTarget(.engineButton)
        .accessibilityIdentifier("diary-engine-titlebar-selector")
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

    private func openEngineSelector() {
        if appState.openOnboardingEngineSetupFromTitlebarIfNeeded() {
            return
        }
        isShowingEnginePanel = true
        if engineRecoveryNudge?.kind == .repairRequired {
            Task { @MainActor in
                _ = await appState.repairDefaultEngineIfNeeded()
            }
        }
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
}

struct DiaryEngineToolbarPresentation: Equatable {
    let title: String
    let state: EngineIndicatorState
    let emphasized: Bool
    let attentionSystemImage: String?
    let attentionColorName: String?

    static func make(
        defaultEngine: DiaryEngine,
        engineStatuses: [DiaryEngine: EngineRuntimeStatus],
        retestingEngines: Set<DiaryEngine>
    ) -> DiaryEngineToolbarPresentation {
        if defaultEngine == .none {
            return DiaryEngineToolbarPresentation(
                title: "Add Diary Engine",
                state: .yellow,
                emphasized: true,
                attentionSystemImage: "exclamationmark.circle.fill",
                attentionColorName: "red"
            )
        }

        let status = engineStatuses[defaultEngine] ?? EngineRuntimeStatus()
        if status.state == .green {
            return DiaryEngineToolbarPresentation(
                title: defaultEngine.displayName,
                state: .green,
                emphasized: false,
                attentionSystemImage: nil,
                attentionColorName: nil
            )
        }

        let title = retestingEngines.contains(defaultEngine)
            ? "Testing \(defaultEngine.displayName)"
            : "Fix Diary Engine"
        return DiaryEngineToolbarPresentation(
            title: title,
            state: .yellow,
            emphasized: true,
            attentionSystemImage: "exclamationmark.circle.fill",
            attentionColorName: "red"
        )
    }
}

enum DiaryEngineRecoveryNudgeKind: Equatable {
    case setupRequired
    case repairRequired
}

struct DiaryEngineRecoveryNudgePresentation: Equatable {
    let kind: DiaryEngineRecoveryNudgeKind
    let toolbarTitle: String
    let toolbarState: EngineIndicatorState
    let title: String
    let detail: String

    static func make(
        defaultEngine: DiaryEngine,
        engineStatuses: [DiaryEngine: EngineRuntimeStatus]
    ) -> DiaryEngineRecoveryNudgePresentation? {
        if defaultEngine == .none {
            return DiaryEngineRecoveryNudgePresentation(
                kind: .setupRequired,
                toolbarTitle: "Add Diary Engine",
                toolbarState: .yellow,
                title: "Choose a Diary Engine",
                detail: "Connect any engine to generate and refresh diary entries."
            )
        }

        let status = engineStatuses[defaultEngine] ?? EngineRuntimeStatus()
        guard status.state == .green else {
            return DiaryEngineRecoveryNudgePresentation(
                kind: .repairRequired,
                toolbarTitle: "Fix Diary Engine",
                toolbarState: .yellow,
                title: "Diary Engine needs attention",
                detail: "\(defaultEngine.displayName) is not ready. Retest it or configure another engine."
            )
        }

        return nil
    }
}

struct EngineIndicatorLight: View {
    let state: EngineIndicatorState

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
    }

    private var color: Color {
        switch state {
        case .gray:
            return .gray
        case .yellow:
            return .yellow
        case .green:
            return .green
        }
    }
}
