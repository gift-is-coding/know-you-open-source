import SwiftUI
import AppKit

@main
struct KnowYouApp: App {
    private let launchMode: LaunchMode
    private let shouldEnsureDefaultLaunchAtLogin: Bool
    @State private var appState: AppState

    init() {
        self.launchMode = CommandLine.arguments.contains("--sync-memory-now") ? .syncMemory : .interactive
        self.shouldEnsureDefaultLaunchAtLogin = launchMode == .interactive && Self.isRunningUnderXCTest == false
        _appState = State(initialValue: AppState())
    }

    var body: some Scene {
        WindowGroup("KnowYou", id: "main") {
            Group {
                if launchMode == .syncMemory {
                    SyncMemoryLaunchView()
                        .environment(appState)
                } else {
                    if appState.shouldShowOnboarding {
                        OnboardingView(
                            onComplete: {},
                            initialStep: appState.currentOnboardingStep ?? .demoRead
                        )
                        .environment(appState)
                    } else {
                        MainWindowView()
                            .environment(appState)
                    }
                }
            }
            .task {
                if shouldEnsureDefaultLaunchAtLogin {
                    appState.ensureDefaultLaunchAtLogin()
                }
            }
        }

        MenuBarExtra("KnowYou", systemImage: "book.closed") {
            MenuBarContentView()
                .environment(appState)
        }

        Settings {
            SettingsView()
                .environment(appState)
        }
    }

    private static var isRunningUnderXCTest: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || CommandLine.arguments.contains { argument in
                argument.contains(".xctest") || argument.contains("xctestconfiguration")
            }
    }
}

private enum LaunchMode {
    case interactive
    case syncMemory
}

private struct SyncMemoryLaunchView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Text("Sync Memory")
            .hidden()
            .task {
                appState.syncMemoryNow()
                NSApp.terminate(nil)
            }
    }
}

private struct MenuBarContentView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("KnowYou")
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

            Button("Open KnowYou") {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }

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
