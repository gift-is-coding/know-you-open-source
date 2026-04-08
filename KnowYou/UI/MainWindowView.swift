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
                StatusBannerView(
                    message: appState.statusMessage,
                    details: appState.statusDetails
                )
                DailyMarkdownView(
                    markdownURL: appState.selectedMarkdownURL,
                    contentVersion: appState.selectedContentVersion
                )
            }
        }
        .frame(minWidth: 960, minHeight: 640)
        .toolbar {
            Button(action: {
                Task { @MainActor in
                    await appState.refreshSelectedDay()
                }
            }) {
                Label("Refresh Selected Day", systemImage: "arrow.clockwise")
            }
            .help("Refresh Selected Day")
        }
    }
}
