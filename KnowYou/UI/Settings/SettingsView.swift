import SwiftUI
import AppKit

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var summarizerConfig = SummarizerConfig.load()
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
                    label: "Summarizer",
                    detail: appState.summarizerStatus.isConfigured
                        ? "\(appState.summarizerStatus.mode) active"
                        : "No summarizer configured",
                    ok: appState.summarizerStatus.isConfigured
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

            Section("Summarizer") {
                Text("Optional after onboarding. Your vault, clipboard capture, and notification capture keep working even if you leave summarization off.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Text("Set up Claude, Codex, Gemini, or OpenAI here whenever you want extra help shaping the daily story.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("Type", selection: $summarizerConfig.defaultEngine) {
                    ForEach(DiaryEngine.allCases, id: \.self) { engine in
                        Text(engine.displayName).tag(engine)
                    }
                }
                .pickerStyle(.menu)

                switch summarizerConfig.defaultEngine {
                case .none:
                    EmptyView()
                case .openAI:
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("API base URL", text: $summarizerConfig.apiBaseURL)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                        TextField("Model", text: $summarizerConfig.apiModel)
                            .textFieldStyle(.roundedBorder)
                        SecureField("API token", text: $summarizerConfig.apiToken)
                            .textFieldStyle(.roundedBorder)
                    }
                case .claudeCLI:
                    TextField("claude executable path", text: $summarizerConfig.claudeCLIPath)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                case .codexCLI:
                    TextField("codex executable path", text: $summarizerConfig.codexCLIPath)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                case .geminiCLI:
                    TextField("gemini executable path", text: $summarizerConfig.geminiCLIPath)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                case .openclawCLI:
                    TextField("openclaw executable path", text: $summarizerConfig.openclawCLIPath)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                }

                Button("Save Summarizer Settings") {
                    if !vaultPath.isEmpty {
                        appState.applyVaultURL(URL(fileURLWithPath: vaultPath, isDirectory: true))
                    }
                    appState.applySummarizerConfig(summarizerConfig)
                }
                .buttonStyle(.borderedProminent)
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
            // Not applied yet — user must press Save
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
