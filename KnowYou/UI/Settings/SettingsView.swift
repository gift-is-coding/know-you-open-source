import SwiftUI
import AppKit

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var vaultPath: String = UserDefaults.standard.string(forKey: AppState.UserDefaultsKeys.vaultPath) ?? ""

    var body: some View {
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
                Text("Runs on launch and every 15 minutes")
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(width: 460)
        .onAppear {
            appState.refreshServiceStatuses()
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
