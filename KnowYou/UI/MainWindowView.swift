import SwiftUI

struct MainWindowView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        NavigationSplitView {
            DateSidebarView(
                dates: appState.availableDates,
                selectedDate: appState.selectedDate,
                onSelect: appState.selectDate
            )
            .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        } content: {
            VStack(spacing: 0) {
                StatusBannerView(
                    message: appState.statusMessage,
                    details: appState.statusDetails
                )
                DailyMarkdownView(
                    story: appState.selectedStory,
                    selectedParagraphID: appState.selectedStoryParagraphID,
                    onSelectParagraph: appState.selectStoryParagraph,
                    onMoveSelection: appState.selectAdjacentStoryParagraph(step:)
                )
            }
        } detail: {
            StorySourceDetailView(
                selectedParagraph: appState.selectedStoryParagraph,
                selectedEvents: appState.selectedStorySourceEvents,
                allEvents: appState.selectedDayEvents
            )
        }
        .frame(minWidth: 1240, minHeight: 720)
        .toolbar {
            Button(action: {
                Task { @MainActor in
                    await appState.refreshSelectedDay()
                }
            }) {
                Label("Regenerate Selected Day", systemImage: "arrow.clockwise.circle")
            }
            .help("Regenerate the selected day")
        }
    }
}
