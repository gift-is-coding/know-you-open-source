import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Form {
            Section("Status") {
                Text(appState.statusMessage ?? "Idle")
            }

            Section("Storage") {
                Text(appState.environment?.vaultURL.path ?? "Vault unavailable")
                    .textSelection(.enabled)
            }

            Section("Automation") {
                Text("Runs on launch and every 15 minutes")
                Text("Notification import uses a read-only snapshot of macOS Notification Center storage when available")
            }

            Section("Summary") {
                Text(appState.environment?.summarizer == nil ? "OpenAI key not configured" : "Cloud summary ready")
            }
        }
        .padding()
        .frame(width: 420)
    }
}
