import SwiftUI
import AppKit

struct OnboardingView: View {
    @Environment(AppState.self) private var appState
    let onComplete: () -> Void

    @State private var step = 0
    @State private var vaultPath: String = (try? AppState.defaultVaultURL().path) ?? ""
    @State private var summarizerConfig = SummarizerConfig.load()

    var body: some View {
        VStack(spacing: 0) {
            // Progress dots
            HStack(spacing: 8) {
                ForEach(0..<3) { i in
                    Circle()
                        .fill(i == step ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.top, 32)

            Spacer()

            switch step {
            case 0:
                vaultStep
            case 1:
                permissionsStep
            default:
                summarizerStep
            }

            Spacer()

            // Navigation buttons
            HStack {
                if step > 0 {
                    Button("Back") { step -= 1 }
                        .buttonStyle(.plain)
                }
                Spacer()
                if step < 2 {
                    Button("Continue") { step += 1 }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button("Finish") { finish() }
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 32)
        }
        .frame(width: 520, height: 420)
    }

    // MARK: - Step 1: Vault

    private var vaultStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "folder.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.accentColor)
            Text("Where should Know You store your notes?")
                .font(.title2)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)
            Text("Daily Markdown notes will be saved here. You can change this later in Settings.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            HStack {
                Text(vaultPath)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button("Choose…") { chooseVaultFolder() }
            }
            .padding(.horizontal, 40)
        }
    }

    // MARK: - Step 2: Permissions

    private var permissionsStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.shield")
                .font(.system(size: 48))
                .foregroundStyle(Color.accentColor)
            Text("Permissions")
                .font(.title2)
                .fontWeight(.semibold)
            VStack(alignment: .leading, spacing: 16) {
                PermissionRow(
                    icon: "doc.on.clipboard",
                    title: "Clipboard",
                    detail: "No permission required. Know You reads your clipboard automatically.",
                    ok: true
                )
                PermissionRow(
                    icon: "bell",
                    title: "Notifications (Full Disk Access)",
                    detail: appState.environment?.notificationReader.isAvailable == true
                        ? "Full Disk Access detected. Notifications will be imported."
                        : "To import notifications, grant Full Disk Access:\nSystem Settings → Privacy & Security → Full Disk Access → add Know You",
                    ok: appState.environment?.notificationReader.isAvailable == true
                )
            }
            .padding(.horizontal, 40)
        }
    }

    // MARK: - Step 3: Summarizer

    private var summarizerStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "sparkles")
                .font(.system(size: 48))
                .foregroundStyle(Color.accentColor)
            Text("How should Know You summarize your day?")
                .font(.title2)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)
            Text("Choose a summarizer. You can change this later in Settings.")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 12) {
                Picker("Type", selection: $summarizerConfig.type) {
                    ForEach(SummarizerType.allCases, id: \.self) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 240)

                switch summarizerConfig.type {
                case .none:
                    Text("Summaries will be skipped. Notes will still be generated.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .openAI:
                    SecureField("OpenAI API Key", text: $summarizerConfig.openAIKey)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 320)
                case .claudeCLI:
                    TextField("claude path", text: $summarizerConfig.claudeCLIPath)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 320)
                case .codexCLI:
                    TextField("codex path", text: $summarizerConfig.codexCLIPath)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 320)
                case .geminiCLI:
                    TextField("gemini path", text: $summarizerConfig.geminiCLIPath)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 320)
                }
            }
        }
    }

    // MARK: - Actions

    private func chooseVaultFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Select Vault Folder"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            vaultPath = url.path
        }
    }

    private func finish() {
        let vaultURL = URL(fileURLWithPath: vaultPath, isDirectory: true)
        appState.applyVaultURL(vaultURL)
        appState.applySummarizerConfig(summarizerConfig)
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        onComplete()
    }
}

private struct PermissionRow: View {
    let icon: String
    let title: String
    let detail: String
    let ok: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(ok ? .green : .orange)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 4) {
                Label(title, systemImage: icon)
                    .fontWeight(.medium)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
