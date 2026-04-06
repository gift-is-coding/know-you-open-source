import SwiftUI

@main
struct KnowYouApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup("Know You") {
            MainWindowView()
                .environment(appState)
        }

        MenuBarExtra("Know You", systemImage: "book.closed") {
            SettingsLink()
            Divider()
            Text(appState.statusMessage ?? "Capturing context")
                .font(.footnote)
        }

        Settings {
            SettingsView()
                .environment(appState)
        }
    }
}
