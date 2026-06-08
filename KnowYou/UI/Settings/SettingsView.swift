import SwiftUI
import AppKit

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var vaultPath: String = AppRuntimeProfile.userDefaults()
        .string(forKey: AppState.UserDefaultsKeys.vaultPath) ?? ""
    @State private var presentedDocument: AppSupportDocument?
    @State private var selectedTab: Tab = .general

    private enum Tab: Hashable {
        case general
        case services
        case engines
        case about
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralTab(
                vaultPath: $vaultPath,
                chooseVaultFolder: chooseVaultFolder,
                openNotificationSettings: openNotificationSettings
            )
            .tabItem { Label("General", systemImage: "gearshape") }
            .tag(Tab.general)

            ServicesTab(openFullDiskAccess: openFullDiskAccess)
                .tabItem { Label("Services", systemImage: "bolt.horizontal.circle") }
                .tag(Tab.services)

            EnginesTab()
                .tabItem { Label("Engines", systemImage: "brain") }
                .tag(Tab.engines)

            AboutTab(presentedDocument: $presentedDocument, openURL: open)
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag(Tab.about)
        }
        .frame(width: 560, height: 560)
        .onAppear {
            appState.refreshServiceStatuses()
        }
        .sheet(item: $presentedDocument) { document in
            AppSupportDocumentSheet(document: document)
        }
    }

    private func chooseVaultFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Select Vault Folder"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            vaultPath = url.path
            appState.applyVaultURL(url)
        }
    }

    private func openFullDiskAccess() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    private func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    private func openNotificationSettings() {
        if let deepLink = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension"),
           NSWorkspace.shared.open(deepLink) {
            return
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
    }
}

private struct GeneralTab: View {
    @Environment(AppState.self) private var appState
    @Binding var vaultPath: String
    let chooseVaultFolder: () -> Void
    let openNotificationSettings: () -> Void

    var body: some View {
        SettingsScrollContainer {
            SettingsCard(title: "Status", icon: "waveform") {
                VStack(alignment: .leading, spacing: 6) {
                    Text(appState.statusMessage ?? "Idle")
                        .font(.body)
                    Text(appState.automationStatusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if !appState.statusDetails.isEmpty {
                        Divider().padding(.vertical, 2)
                        ForEach(appState.statusDetails, id: \.self) { detail in
                            Text(detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            SettingsCard(title: "Vault Folder", icon: "folder") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(vaultPath.isEmpty ? (try? AppState.defaultVaultURL().path) ?? "Default" : vaultPath)
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))

                    HStack {
                        Spacer()
                        Button("Choose Folder…", action: chooseVaultFolder)
                    }
                }
            }

            SettingsCard(title: "Automation", icon: "clock.arrow.circlepath") {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Runs on launch and every 15 minutes", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                    Text("Open Sync Memory from the sidebar ellipsis menu in the main window.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            SettingsCard(title: "Daily Review Reminder", icon: "bell.badge") {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle(
                        "Enable 8:30 PM reminder",
                        isOn: Binding(
                            get: { appState.endOfDayReminderConfig.isEnabled },
                            set: { isEnabled in
                                Task { @MainActor in
                                    await appState.setEndOfDayReminderEnabled(isEnabled)
                                }
                            }
                        )
                    )

                    Text(appState.endOfDayReminderStatusSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("KnowYou sends a daily reminder at 8:30 PM in your local time.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if appState.endOfDayReminderConfig.authorizationStatus == .denied {
                        HStack {
                            Button {
                                openNotificationSettings()
                            } label: {
                                Label("Open Notification Settings", systemImage: "bell.slash")
                            }
                            Spacer()
                        }
                    }
                }
            }
        }
    }
}

private struct ServicesTab: View {
    @Environment(AppState.self) private var appState
    let openFullDiskAccess: () -> Void

    var body: some View {
        SettingsScrollContainer {
            SettingsCard(title: "Service Health", icon: "bolt.horizontal.circle") {
                VStack(spacing: 10) {
                    StatusRow(
                        label: "Clipboard capture",
                        detail: appState.clipboardServiceDetail,
                        ok: appState.clipboardStatus.isActive
                    )
                    Divider()
                    StatusRow(
                        label: "Local storage",
                        detail: appState.environment?.vaultURL.path ?? "Unavailable",
                        ok: appState.environment != nil
                    )
                    Divider()
                    StatusRow(
                        label: "Notification import",
                        detail: appState.notificationStatus.availabilityMessage
                            .map { "\($0) \(appState.notificationServiceDetail)" }
                            ?? appState.notificationServiceDetail,
                        ok: appState.notificationStatus.isDatabaseAvailable
                    )
                    Divider()
                    StatusRow(
                        label: "Diary engine",
                        detail: appState.defaultEngine == .none
                            ? "No verified default engine selected"
                            : "\(appState.defaultEngine.displayName) active",
                        ok: appState.defaultEngine != .none
                    )
                }
            }

            SettingsCard(title: "Actions", icon: "wrench.and.screwdriver") {
                HStack {
                    Button {
                        appState.refreshServiceStatuses()
                    } label: {
                        Label("Re-check Services", systemImage: "arrow.clockwise")
                    }

                    Button {
                        openFullDiskAccess()
                    } label: {
                        Label("Full Disk Access…", systemImage: "lock.shield")
                    }

                    Spacer()
                }
            }
        }
    }
}

private struct EnginesTab: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        SettingsScrollContainer {
            SettingsCard(title: "Diary Engines", icon: "brain") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Manage diary engines from the top-right selector in the main window. This view is a read-only reference.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text("Clipboard capture, notifications, and local note generation keep working even if you leave the default engine disabled.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            SettingsCard(title: "Engine States", icon: "circle.hexagongrid") {
                VStack(spacing: 0) {
                    let engines = DiaryEngine.allCases.filter { $0 != .none }
                    ForEach(Array(engines.enumerated()), id: \.element) { index, engine in
                        let status = appState.engineStatuses[engine] ?? EngineRuntimeStatus()
                        HStack(alignment: .center, spacing: 12) {
                            EngineIndicatorLight(state: status.state)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(engine.displayName)
                                        .fontWeight(appState.defaultEngine == engine ? .semibold : .regular)
                                    if appState.defaultEngine == engine {
                                        Text("DEFAULT")
                                            .font(.caption2)
                                            .fontWeight(.bold)
                                            .foregroundStyle(.tint)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 1)
                                            .background(Color.accentColor.opacity(0.15), in: Capsule())
                                    }
                                }
                                Text(status.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 8)

                        if index < engines.count - 1 {
                            Divider()
                        }
                    }

                    HStack {
                        Spacer()
                        Button {
                            appState.refreshEngineStatuses()
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                    }
                    .padding(.top, 10)
                }
            }
        }
    }
}

private struct AboutTab: View {
    @Binding var presentedDocument: AppSupportDocument?
    let openURL: (URL) -> Void

    var body: some View {
        SettingsScrollContainer {
            VStack(spacing: 8) {
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.tint)
                Text("KnowYou")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text(AppSupportMetadata.productTagline)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)

            SettingsCard(title: "Contact", icon: "person.2") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Button {
                            openURL(AppSupportMetadata.twitterURL)
                        } label: {
                            Label(AppSupportMetadata.twitterButtonTitle, systemImage: "bubble.left.and.text.bubble.right")
                        }

                        Button {
                            openURL(AppSupportMetadata.emailURL)
                        } label: {
                            Label(AppSupportMetadata.emailButtonTitle, systemImage: "envelope")
                        }

                        if let discordURL = AppSupportMetadata.discordURL {
                            Button {
                                openURL(discordURL)
                            } label: {
                                Label(AppSupportMetadata.discordButtonTitle, systemImage: "person.3")
                            }
                        }
                    }
                    .labelStyle(.titleAndIcon)

                    Text(AppSupportMetadata.discordDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            SettingsCard(title: "Policies & Docs", icon: "doc.text") {
                VStack(alignment: .leading, spacing: 10) {
                    FlowButtons(documents: [.privacy, .terms, .community, .launchChecklist]) { document in
                        presentedDocument = document
                    }
                    Text(AppSupportMetadata.supportDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text(AppSupportMetadata.copyrightLine)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
        }
    }
}

private struct SettingsScrollContainer<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                content
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundStyle(.secondary)
                    .font(.callout)
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }

            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.secondary.opacity(0.15), lineWidth: 1)
                )
        }
    }
}

private struct FlowButtons: View {
    let documents: [AppSupportDocument]
    let action: (AppSupportDocument) -> Void

    var body: some View {
        let columns = [GridItem(.adaptive(minimum: 140), spacing: 8)]
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(documents) { document in
                Button(document.buttonTitle) {
                    action(document)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

private struct AppSupportDocumentSheet: View {
    let document: AppSupportDocument
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(document.title)
                    .font(.title3)
                    .fontWeight(.semibold)
                Spacer()
                Button("Close") {
                    dismiss()
                }
            }

            ScrollView {
                Text(document.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
        .padding(20)
        .frame(minWidth: 520, minHeight: 420)
    }
}

private struct StatusRow: View {
    let label: String
    let detail: String
    let ok: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(ok ? .green : .orange)
                .font(.title3)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .fontWeight(.medium)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
    }
}
