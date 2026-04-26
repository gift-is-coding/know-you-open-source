import SwiftUI
import AppKit

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var vaultPath: String = UserDefaults.standard.string(forKey: AppState.UserDefaultsKeys.vaultPath) ?? ""
    @State private var presentedDocument: AppSupportDocument?

    var body: some View {
        ScrollView {
            Form {
                Section("Status") {
                    Text(appState.statusMessage ?? "Idle")
                    Text(appState.automationStatusText)
                        .foregroundStyle(.secondary)
                    ForEach(appState.statusDetails, id: \.self) { detail in
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Services") {
                    StatusRow(
                        label: "Clipboard capture",
                        detail: appState.clipboardServiceDetail,
                        ok: appState.clipboardStatus.isActive
                    )
                    StatusRow(
                        label: "Local storage",
                        detail: appState.environment?.vaultURL.path ?? "Unavailable",
                        ok: appState.environment != nil
                    )
                    StatusRow(
                        label: "Notification import",
                        detail: appState.notificationStatus.availabilityMessage
                            .map { "\($0) \(appState.notificationServiceDetail)" }
                            ?? appState.notificationServiceDetail,
                        ok: appState.notificationStatus.isDatabaseAvailable
                    )
                    StatusRow(
                        label: "Diary engine",
                        detail: appState.defaultEngine == .none
                            ? "No verified default engine selected"
                            : "\(appState.defaultEngine.displayName) active",
                        ok: appState.defaultEngine != .none
                    )

                    HStack {
                        Button("Re-check Services") {
                            appState.refreshServiceStatuses()
                        }
                        Button("Open Full Disk Access") {
                            openFullDiskAccess()
                        }
                    }
                }

                Section("Vault Folder") {
                    HStack {
                        Text(vaultPath.isEmpty ? (try? AppState.defaultVaultURL().path) ?? "Default" : vaultPath)
                            .foregroundStyle(.secondary)
                            .font(.system(.body, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button("Choose…") {
                            chooseVaultFolder()
                        }
                    }
                }

                Section("Diary Engine") {
                    Text("Manage diary engines from the top-right selector in the main window. This page is now a secondary reference view.")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    Text("Clipboard capture, notifications, and local note generation keep working even if you leave the default engine disabled.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(DiaryEngine.allCases.filter { $0 != .none }, id: \.self) { engine in
                        let status = appState.engineStatuses[engine] ?? EngineRuntimeStatus()
                        HStack(alignment: .top, spacing: 10) {
                            EngineIndicatorLight(state: status.state)
                                .padding(.top, 4)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(engine.displayName)
                                    .fontWeight(appState.defaultEngine == engine ? .semibold : .regular)
                                Text(status.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Button("Refresh Engine States") {
                        appState.refreshEngineStatuses()
                    }
                }

                Section("Automation") {
                    Toggle(
                        "Launch at Login",
                        isOn: Binding(
                            get: { appState.launchAtLoginEnabled },
                            set: { appState.setLaunchAtLoginEnabled($0) }
                        )
                    )
                    Text("KnowYou registers this automatically the first time you open the app.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let launchAtLoginStatusMessage = appState.launchAtLoginStatusMessage {
                        Text(launchAtLoginStatusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text("Runs on launch and every 15 minutes")
                        .foregroundStyle(.secondary)
                    Text("Open Sync Memory from the sidebar ellipsis menu in the main window.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Evening Review Reminder") {
                    VStack(alignment: .leading, spacing: 14) {
                        Toggle(
                            "Evening review reminder",
                            isOn: Binding(
                                get: { appState.endOfDayReminderConfig.isEnabled },
                                set: { isEnabled in
                                    Task { @MainActor in
                                        await appState.setEndOfDayReminderEnabled(isEnabled)
                                    }
                                }
                            )
                        )

                        Divider()

                        VStack(alignment: .leading, spacing: 8) {
                            SettingsMetaLabel("Status")
                            SettingsSectionBlurb(appState.endOfDayReminderStatusSummary)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            SettingsMetaLabel("Schedule")
                            SettingsSectionBlurb("KnowYou checks in at 8:30 PM in your local time, even if the app was not open during the day.")
                            SettingsSectionNote("If today's diary exists, the notification says “Come review today's diary.” If not, it says “Come generate today's diary.”")
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            SettingsMetaLabel("Testing")
                            SettingsSectionNote("Use this to verify the real KnowYou notification style, icon, and permission flow right now.")
                            HStack(spacing: 10) {
                                Button("Send Test Reminder Now") {
                                    Task { @MainActor in
                                        await appState.sendTestEndOfDayReminderNow()
                                    }
                                }
                                .buttonStyle(.borderedProminent)

                                if appState.endOfDayReminderConfig.authorizationStatus == .denied {
                                    Button("Open System Settings") {
                                        openNotificationSettings()
                                    }
                                }
                            }

                            if let testStatus = appState.endOfDayReminderTestStatusMessage {
                                SettingsSectionNote(testStatus)
                            }
                        }
                    }
                }

                Section("About & Community") {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("KnowYou")
                            .font(.headline)
                        Text(AppSupportMetadata.productTagline)
                            .font(.callout)
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Contact")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            HStack(spacing: 10) {
                                Button {
                                    open(AppSupportMetadata.twitterURL)
                                } label: {
                                    Label(AppSupportMetadata.twitterButtonTitle, systemImage: "bubble.left.and.text.bubble.right")
                                }

                                Button {
                                    open(AppSupportMetadata.emailURL)
                                } label: {
                                    Label(AppSupportMetadata.emailButtonTitle, systemImage: "envelope")
                                }

                                if let discordURL = AppSupportMetadata.discordURL {
                                    Button {
                                        open(discordURL)
                                    } label: {
                                        Label(AppSupportMetadata.discordButtonTitle, systemImage: "person.3")
                                    }
                                }
                            }
                            .labelStyle(.titleAndIcon)
                        }

                        Text(AppSupportMetadata.discordDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Divider()

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Policies & Docs")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    Button(AppSupportDocument.privacy.buttonTitle) {
                                        presentedDocument = .privacy
                                    }
                                    Button(AppSupportDocument.terms.buttonTitle) {
                                        presentedDocument = .terms
                                    }
                                    Button(AppSupportDocument.community.buttonTitle) {
                                        presentedDocument = .community
                                    }
                                    Button(AppSupportDocument.launchChecklist.buttonTitle) {
                                        presentedDocument = .launchChecklist
                                    }
                                }
                            }
                        }

                        Text(AppSupportMetadata.supportDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Divider()

                        Text(AppSupportMetadata.copyrightLine)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .padding()
        .scrollIndicators(.visible)
        .frame(width: 540, height: 760)
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
        if let deepLink = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
            if NSWorkspace.shared.open(deepLink) {
                return
            }
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
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

private struct SettingsMetaLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text.uppercased())
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.tertiary)
    }
}

private struct SettingsSectionBlurb: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct SettingsSectionNote: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct StatusRow: View {
    let label: String
    let detail: String
    let ok: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(ok ? .green : .orange)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .fontWeight(.medium)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }
}
