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
        .toolbar {
            Button(action: {
                Task { @MainActor in
                    await appState.runAutomation()
                }
            }) {
                Label("Catch Up Now", systemImage: "arrow.clockwise.circle")
            }
            .help("Catch Up Now")

            if let selectedDate = appState.selectedDate {
                Button(action: {
                    Task { @MainActor in
                        await appState.generateDailyNote(for: selectedDate)
                    }
                }) {
                    Label("Rebuild Day", systemImage: "hammer")
                }
                .help("Rebuild Day")
            }
        }
    }
}
