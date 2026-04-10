import SwiftUI
import AppKit

struct MainWindowView: View {
    @Environment(AppState.self) private var appState
    @State private var isRefreshing = false
    @State private var keyMonitor: Any?

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
                    appState.selectStoryParagraph(paragraphID)
                },
                onFocusStory: {
                    guard appState.readerFocus != .storyParagraphs else { return }
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
        .onAppear {
            startKeyMonitor()
        }
        .onDisappear {
            stopKeyMonitor()
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
}
