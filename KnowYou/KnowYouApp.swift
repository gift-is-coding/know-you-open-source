import SwiftUI
import AppKit
import UserNotifications

@MainActor
final class EndOfDayReminderNavigationCenter {
    static let shared = EndOfDayReminderNavigationCenter()

    private(set) var pendingRoute: EndOfDayReminderRoute?

    func enqueue(dayKey: String, action: EndOfDayReminderAction) {
        let route = EndOfDayReminderRoute(dayKey: dayKey, action: action)
        pendingRoute = route
        NotificationCenter.default.post(
            name: .endOfDayReminderOpened,
            object: nil,
            userInfo: route.userInfo
        )
    }

    func takePendingRoute() -> EndOfDayReminderRoute? {
        defer { pendingRoute = nil }
        return pendingRoute
    }
}

struct EndOfDayReminderRoute: Equatable {
    let dayKey: String
    let action: EndOfDayReminderAction

    var userInfo: [String: String] {
        [
            EndOfDayReminderNotificationPayload.dayKey: dayKey,
            EndOfDayReminderNotificationPayload.action: action.rawValue,
        ]
    }

    static func from(userInfo: [AnyHashable: Any]) -> EndOfDayReminderRoute? {
        guard
            let dayKey = userInfo[EndOfDayReminderNotificationPayload.dayKey] as? String,
            let rawAction = userInfo[EndOfDayReminderNotificationPayload.action] as? String,
            let action = EndOfDayReminderAction(rawValue: rawAction)
        else {
            return nil
        }
        return EndOfDayReminderRoute(dayKey: dayKey, action: action)
    }
}

final class KnowYouAppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent _: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler(EndOfDayReminderNotificationPresentation.foregroundOptions)
    }

    func userNotificationCenter(
        _: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let route = EndOfDayReminderRoute.from(userInfo: response.notification.request.content.userInfo) {
            Task { @MainActor in
                EndOfDayReminderNavigationCenter.shared.enqueue(dayKey: route.dayKey, action: route.action)
                NSApp.activate(ignoringOtherApps: true)
                NSApp.windows.first?.makeKeyAndOrderFront(nil)
            }
        }
        completionHandler()
    }
}

@main
struct KnowYouApp: App {
    @NSApplicationDelegateAdaptor(KnowYouAppDelegate.self) private var appDelegate
    private let launchMode: LaunchMode
    @State private var appState: AppState

    init() {
        let launchMode = LaunchMode(arguments: CommandLine.arguments)
        self.launchMode = launchMode
        _appState = State(
            initialValue: AppState(bootstrapServices: launchMode != .endOfDayReminder)
        )
    }

    var body: some Scene {
        WindowGroup("KnowYou", id: "main") {
            AppRootView(launchMode: launchMode)
                .environment(appState)
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
}

private struct AppRootView: View {
    let launchMode: LaunchMode

    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if launchMode == .syncMemory {
                SyncMemoryLaunchView()
            } else if launchMode == .endOfDayReminder {
                EndOfDayReminderLaunchView()
            } else if appState.shouldShowOnboarding {
                OnboardingView(
                    onComplete: {},
                    initialStep: appState.currentOnboardingStep ?? .demoRead
                )
            } else {
                MainWindowView()
            }
        }
        .task {
            routePendingReminderIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .endOfDayReminderOpened)) { notification in
            guard let userInfo = notification.userInfo,
                  let route = EndOfDayReminderRoute.from(userInfo: userInfo) else {
                return
            }
            routeToReminder(route)
        }
    }

    private func routePendingReminderIfNeeded() {
        guard let route = EndOfDayReminderNavigationCenter.shared.takePendingRoute() else { return }
        routeToReminder(route)
    }

    private func routeToReminder(_ route: EndOfDayReminderRoute) {
        if NSApp.windows.isEmpty {
            openWindow(id: "main")
        } else {
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
        appState.openDayFromEndOfDayReminder(route.dayKey, action: route.action)
    }
}

private enum LaunchMode {
    case interactive
    case syncMemory
    case endOfDayReminder

    init(arguments: [String]) {
        if arguments.contains("--sync-memory-now") {
            self = .syncMemory
        } else if arguments.contains("--end-of-day-reminder-now") {
            self = .endOfDayReminder
        } else {
            self = .interactive
        }
    }
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

private struct EndOfDayReminderLaunchView: View {
    var body: some View {
        Text("End Of Day Reminder")
            .hidden()
            .task {
                do {
                    let runner = EndOfDayReminderRunner()
                    _ = try await runner.run()
                } catch {
                    NSLog("End-of-day reminder failed: %@", error.localizedDescription)
                }
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
