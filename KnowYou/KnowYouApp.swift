import SwiftUI
import AppKit
import UserNotifications
import Darwin

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

    func applicationDidFinishLaunching(_: Notification) {
        DispatchQueue.main.async {
            KnowYouMainWindowPresenter.shared.showConfiguredWindowIfNeeded()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                KnowYouMainWindowPresenter.shared.showConfiguredWindowIfNeeded()
            }
        }
    }

    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if flag == false {
            Task { @MainActor in
                KnowYouMainWindowPresenter.shared.showConfiguredWindowIfNeeded()
            }
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
                KnowYouMainWindowPresenter.shared.showConfiguredWindowIfNeeded()
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
        if launchMode == .myWikiContext {
            Self.runMyWikiContextCommandAndExit(arguments: CommandLine.arguments)
        }
        if launchMode == .myWikiMCP {
            Self.runMyWikiMCPCommandAndExit(arguments: CommandLine.arguments)
        }

        self.launchMode = launchMode
        let initialAppState = AppState(bootstrapServices: Self.shouldBootstrapServices(for: launchMode))
        _appState = State(
            initialValue: initialAppState
        )
        KnowYouMainWindowPresenter.shared.configure(
            launchMode: launchMode,
            appState: initialAppState
        )
    }

    var body: some Scene {
        MenuBarExtra(AppRuntimeProfile.current.displayName, systemImage: "book.closed") {
            MenuBarContentView {
                KnowYouMainWindowPresenter.shared.showConfiguredWindowIfNeeded()
            }
                .environment(appState)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open \(AppRuntimeProfile.current.displayName)") {
                    KnowYouMainWindowPresenter.shared.showConfiguredWindowIfNeeded()
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
                .environment(appState)
        }
    }

    fileprivate static var isRunningUnderXCTest: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || CommandLine.arguments.contains { argument in
                argument.contains(".xctest") || argument.contains("xctestconfiguration")
            }
    }

    private static func shouldBootstrapServices(for launchMode: LaunchMode) -> Bool {
        launchMode != .endOfDayReminder
            && launchMode != .myWikiContext
            && launchMode != .myWikiMCP
            && isRunningUnderXCTest == false
    }

    private static func runMyWikiContextCommandAndExit(arguments: [String]) -> Never {
        let result = MyWikiContextPackCommand.run(arguments: arguments)
        write(result.stdout, to: .standardOutput)
        write(result.stderr, to: .standardError)
        Darwin.exit(result.exitCode)
    }

    private static func runMyWikiMCPCommandAndExit(arguments: [String]) -> Never {
        let exitCode = MyWikiMCPCommand.serve(arguments: arguments)
        Darwin.exit(exitCode)
    }

    private static func write(_ string: String, to fileHandle: FileHandle) {
        guard string.isEmpty == false,
              let data = string.data(using: .utf8) else {
            return
        }
        fileHandle.write(data)
    }
}

enum KnowYouMainWindowLaunchPolicy {
    static var title: String { AppRuntimeProfile.current.displayName }
    static let usesSwiftUIWindowScene = false
    static let usesAppKitPresenter = true
}

@MainActor
private final class KnowYouMainWindowPresenter {
    static let shared = KnowYouMainWindowPresenter()

    private var appState: AppState?
    private var launchMode: LaunchMode = .interactive
    private var windowController: NSWindowController?

    private init() {}

    func configure(launchMode: LaunchMode, appState: AppState) {
        self.launchMode = launchMode
        self.appState = appState
    }

    func showConfiguredWindowIfNeeded() {
        guard launchMode == .interactive, let appState else { return }
        show(launchMode: launchMode, appState: appState)
    }

    private func show(launchMode: LaunchMode, appState: AppState) {
        let controller = windowController ?? makeWindowController(launchMode: launchMode, appState: appState)
        windowController = controller
        guard let window = controller.window else { return }

        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeWindowController(launchMode: LaunchMode, appState: AppState) -> NSWindowController {
        let hostingController = NSHostingController(
            rootView: AppRootView(launchMode: launchMode)
                .environment(appState)
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = KnowYouMainWindowLaunchPolicy.title
        window.contentViewController = hostingController
        window.center()
        window.setFrameAutosaveName("KnowYouMainWindow")
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace]
        return NSWindowController(window: window)
    }
}

private struct AppRootView: View {
    let launchMode: LaunchMode

    @Environment(AppState.self) private var appState

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
            if launchMode == .interactive && KnowYouApp.isRunningUnderXCTest == false {
                appState.ensureDefaultLaunchAtLogin()
            }
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
            KnowYouMainWindowPresenter.shared.showConfiguredWindowIfNeeded()
        } else {
            KnowYouMainWindowPresenter.shared.showConfiguredWindowIfNeeded()
        }
        appState.openDayFromEndOfDayReminder(route.dayKey, action: route.action)
    }
}

enum LaunchMode: Equatable {
    case interactive
    case syncMemory
    case importKnowledge
    case endOfDayReminder
    case myWikiContext
    case myWikiMCP

    init(arguments: [String]) {
        if arguments.contains("--sync-memory-now") {
            self = .syncMemory
        } else if arguments.contains("--import-knowledge-now") {
            self = .importKnowledge
        } else if arguments.contains("--end-of-day-reminder-now") {
            self = .endOfDayReminder
        } else if arguments.contains(MyWikiContextPackCommand.launchArgument) {
            self = .myWikiContext
        } else if arguments.contains(MyWikiMCPCommand.launchArgument) {
            self = .myWikiMCP
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
    let onOpenKnowYou: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(AppRuntimeProfile.current.displayName)
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

            Button("Open \(AppRuntimeProfile.current.displayName)") {
                onOpenKnowYou()
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
