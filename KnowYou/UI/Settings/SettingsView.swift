import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Form {
            Section("Status") {
                Text(appState.statusMessage ?? "Idle")
            }

            Section("Configuration") {
                Text("Vault and API settings will live here.")
            }
        }
        .padding()
        .frame(width: 420)
    }
}
