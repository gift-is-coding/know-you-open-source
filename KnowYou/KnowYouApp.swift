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
            MenuBarContentView()
                .environment(appState)
        }

        Settings {
            SettingsView()
                .environment(appState)
        }
    }
}

private struct MenuBarContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Know You")
                .font(.headline)
            Text(appState.statusMessage ?? "Capturing context")
                .font(.footnote)
                .foregroundStyle(.secondary)
            ForEach(appState.statusDetails.prefix(3), id: \.self) { detail in
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            Button("Refresh Selected Day") {
                Task { @MainActor in
                    await appState.refreshSelectedDay()
                }
            }

            SettingsLink()
        }
        .padding(12)
        .frame(width: 280, alignment: .leading)
    }
}
