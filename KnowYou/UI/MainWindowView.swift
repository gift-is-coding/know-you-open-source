import SwiftUI
import AppKit

struct MainWindowView: View {
    @Environment(AppState.self) private var appState
    @State private var isRefreshing = false
    @State private var keyMonitor: Any?
    @State private var isShowingEnginePanel = false
    @State private var isShowingAPIDetail = false
    @State private var apiConfigDraft = SummarizerConfig.load()
    @State private var isTestingAPIConnection = false

    var body: some View {
        NavigationSplitView {
            DateSidebarView(
                dates: appState.availableDates,
                selectedDate: appState.selectedDate,
                isActive: appState.readerFocus == .dateList,
                onSelect: appState.selectDate
            )
            .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        } content: {
            DailyMarkdownView(
                story: appState.selectedStory,
                selectedParagraphID: appState.selectedStoryParagraphID,
                dayKey: appState.selectedDate,
                isRefreshing: isRefreshing,
                isActive: appState.readerFocus == .storyParagraphs,
                onSelectParagraph: { paragraphID in
                    appState.focusStoryParagraphs()
                    appState.selectStoryParagraph(paragraphID)
                },
                onFocusStory: {
                    appState.focusStoryParagraphs()
                },
                onRefresh: {
                    guard !isRefreshing else { return }
                    isRefreshing = true
                    Task { @MainActor in
                        await appState.refreshSelectedDay()
                        isRefreshing = false
                    }
                }
            )
        } detail: {
            StorySourceDetailView(
                selectedParagraph: appState.selectedStoryParagraph,
                selectedEvents: appState.selectedStorySourceEvents,
                allEvents: appState.selectedDayEvents
            )
            .navigationSplitViewColumnWidth(min: 320, ideal: 360, max: 420)
        }
        .frame(minWidth: 1240, minHeight: 720)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                DiaryEngineSelectorButton(
                    title: currentEngineTitle,
                    state: currentEngineState,
                    action: openEnginePanel
                )
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
        .onAppear {
            startKeyMonitor()
        }
        .onDisappear {
            stopKeyMonitor()
        }
    }

    private var currentEngineTitle: String {
        appState.defaultEngine == .none ? "Select Engine" : appState.defaultEngine.displayName
    }

    private var currentEngineState: EngineIndicatorState {
        appState.engineStatuses[appState.defaultEngine]?.state ?? .gray
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
}
