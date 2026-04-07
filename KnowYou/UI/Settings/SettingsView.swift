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

            Section("Summary") {
                Text(appState.environment?.summarizer == nil ? "OpenAI key not configured" : "Cloud summary ready")
            }
        }
        .padding()
        .frame(width: 420)
    }
}
