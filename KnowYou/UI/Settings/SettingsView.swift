import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState

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
                        : "Notification Center database not accessible — notifications will not be imported",
                    ok: appState.environment?.notificationReader.isAvailable == true
                )
                StatusRow(
                    label: "Cloud summary",
                    detail: appState.environment?.summarizer != nil
                        ? "OpenAI key configured"
                        : "Set OPENAI_API_KEY to enable summaries",
                    ok: appState.environment?.summarizer != nil
                )
            }

            Section("Automation") {
                Text("Runs on launch and every 15 minutes")
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(width: 440)
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
