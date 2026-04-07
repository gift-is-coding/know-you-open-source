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
            }

            Section("Services") {
                StatusRow(
                    label: "Local storage",
                    detail: appState.environment?.vaultURL.path ?? "Unavailable",
                    ok: appState.environment != nil
                )
                StatusRow(
                    label: "Notification import",
                    detail: appState.environment?.notificationReader.isAvailable == true
                        ? "Notification Center database found"
                        : "Notification Center database not accessible — grant Full Disk Access in System Settings",
                    ok: appState.environment?.notificationReader.isAvailable == true
                )
                StatusRow(
                    label: "Summarizer",
                    detail: appState.environment?.summarizer != nil
                        ? "\(summarizerConfig.type.displayName) active"
                        : "No summarizer configured",
                    ok: appState.environment?.summarizer != nil
                )
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
                Picker("Type", selection: $summarizerConfig.type) {
                    ForEach(SummarizerType.allCases, id: \.self) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                .pickerStyle(.menu)

                switch summarizerConfig.type {
                case .none:
                    EmptyView()
                case .openAI:
                    SecureField("OpenAI API Key", text: $summarizerConfig.openAIKey)
                        .textFieldStyle(.roundedBorder)
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
                }

                Button("Save") {
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
