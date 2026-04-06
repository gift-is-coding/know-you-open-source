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
        } detail: {
            VStack(spacing: 0) {
                StatusBannerView(message: appState.statusMessage)
                DailyMarkdownView(markdownURL: appState.selectedMarkdownURL)
            }
        }
        .frame(minWidth: 960, minHeight: 640)
    }
}
