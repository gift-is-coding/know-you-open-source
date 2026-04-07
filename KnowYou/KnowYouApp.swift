import SwiftUI

@main
struct KnowYouApp: App {
    @State private var appState = AppState()
    @State private var hasCompletedOnboarding = UserDefaults.standard.bool(forKey: AppState.UserDefaultsKeys.hasCompletedOnboarding)

    var body: some Scene {
        WindowGroup("Know You") {
            if hasCompletedOnboarding {
                MainWindowView()
                    .environment(appState)
            } else {
                OnboardingView {
                    hasCompletedOnboarding = true
                }
                .environment(appState)
            }
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
