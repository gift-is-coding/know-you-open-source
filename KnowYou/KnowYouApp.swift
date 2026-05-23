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

@MainActor
private enum KnowYouWindowPresenter {
    private static var manualMainWindow: NSWindow?
    private static var manualLaunchMode: LaunchMode?
    private static var manualAppState: AppState?

    static func configureManualWindow(appState: AppState, launchMode: LaunchMode) {
        manualAppState = appState
        manualLaunchMode = launchMode
    }

    static func shouldPresentMainWindowOnLaunch(arguments: [String] = CommandLine.arguments) -> Bool {
        LaunchMode(arguments: arguments) == .interactive && isRunningUnderXCTest == false
    }

    static func presentExistingMainWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        guard let window = mainWindow() ?? makeManualMainWindow() else { return }
        window.deminiaturize(nil)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    static func presentExistingMainWindowSoon() {
        DispatchQueue.main.async {
            presentExistingMainWindow()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            presentExistingMainWindow()
        }
    }

    private static var isRunningUnderXCTest: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || CommandLine.arguments.contains { argument in
                argument.contains(".xctest") || argument.contains("xctestconfiguration")
            }
    }

    private static func mainWindow() -> NSWindow? {
        NSApp.windows.first { window in
            window.title == "KnowYou"
                || window.identifier?.rawValue.contains("main") == true
        }
    }

    private static func makeManualMainWindow() -> NSWindow? {
        if let manualMainWindow {
            return manualMainWindow
        }
        guard let manualAppState, let manualLaunchMode else {
            return NSApp.windows.first
        }

        let rootView = AppRootView(launchMode: manualLaunchMode)
            .environment(manualAppState)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1180, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.identifier = NSUserInterfaceItemIdentifier("main")
        window.title = "KnowYou"
        window.center()
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: rootView)
        manualMainWindow = window
        return window
    }
}

final class KnowYouAppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func applicationDidFinishLaunching(_: Notification) {
        guard KnowYouWindowPresenter.shouldPresentMainWindowOnLaunch() else { return }
        KnowYouWindowPresenter.presentExistingMainWindowSoon()
    }

    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if flag == false {
            KnowYouWindowPresenter.presentExistingMainWindow()
        }
        return true
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
                KnowYouWindowPresenter.presentExistingMainWindow()
            }
        }
        completionHandler()
    }
}

@main
enum KnowYouMain {
    static func main() {
        if #available(macOS 15.0, *) {
            KnowYouPresentedApp.main()
        } else {
            KnowYouLegacyApp.main()
        }
    }
}

@available(macOS 15.0, *)
private struct KnowYouPresentedApp: App {
    @NSApplicationDelegateAdaptor(KnowYouAppDelegate.self) private var appDelegate
    private let launchMode: LaunchMode
    private let shouldEnsureDefaultLaunchAtLogin: Bool
    @State private var appState: AppState

    init() {
        let launchMode = LaunchMode(arguments: CommandLine.arguments)
        let appState = AppState(bootstrapServices: launchMode != .endOfDayReminder)
        self.launchMode = launchMode
        self.shouldEnsureDefaultLaunchAtLogin = launchMode == .interactive && Self.isRunningUnderXCTest == false
        _appState = State(initialValue: appState)
        KnowYouWindowPresenter.configureManualWindow(appState: appState, launchMode: launchMode)
    }

    var body: some Scene {
        Window("KnowYou", id: "main") {
            AppRootView(launchMode: launchMode)
                .environment(appState)
            .task {
                if shouldEnsureDefaultLaunchAtLogin {
                    appState.ensureDefaultLaunchAtLogin()
                }
            }
        }
        .defaultLaunchBehavior(.presented)
        .commands {
            MainWindowCommands()
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

private struct KnowYouLegacyApp: App {
    @NSApplicationDelegateAdaptor(KnowYouAppDelegate.self) private var appDelegate
    private let launchMode: LaunchMode
    private let shouldEnsureDefaultLaunchAtLogin: Bool
    @State private var appState: AppState

    init() {
        let launchMode = LaunchMode(arguments: CommandLine.arguments)
        let appState = AppState(bootstrapServices: launchMode != .endOfDayReminder)
        self.launchMode = launchMode
        self.shouldEnsureDefaultLaunchAtLogin = launchMode == .interactive && Self.isRunningUnderXCTest == false
        _appState = State(initialValue: appState)
        KnowYouWindowPresenter.configureManualWindow(appState: appState, launchMode: launchMode)
    }

    var body: some Scene {
        Window("KnowYou", id: "main") {
            AppRootView(launchMode: launchMode)
                .environment(appState)
            .task {
                if shouldEnsureDefaultLaunchAtLogin {
                    appState.ensureDefaultLaunchAtLogin()
                }
            }
        }
        .commands {
            MainWindowCommands()
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

private struct MainWindowCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Open KnowYou") {
                openWindow(id: "main")
                KnowYouWindowPresenter.presentExistingMainWindowSoon()
            }
            .keyboardShortcut("n")
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
            } else if launchMode == .importKnowledge {
                ImportKnowledgeLaunchView()
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
            KnowYouWindowPresenter.presentExistingMainWindow()
        }
        appState.openDayFromEndOfDayReminder(route.dayKey, action: route.action)
    }
}

private enum LaunchMode {
    case interactive
    case syncMemory
    case importKnowledge
    case endOfDayReminder

    init(arguments: [String]) {
        if arguments.contains("--sync-memory-now") {
            self = .syncMemory
        } else if arguments.contains("--import-knowledge-now") {
            self = .importKnowledge
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

private struct ImportKnowledgeLaunchView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Text("Import Knowledge")
            .hidden()
            .task {
                await appState.importKnowledgeNow()
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
                KnowYouWindowPresenter.presentExistingMainWindowSoon()
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
