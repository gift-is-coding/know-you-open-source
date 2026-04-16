import SwiftUI

struct APIDetailSheet: View {
    @Binding var config: SummarizerConfig
    let status: EngineRuntimeStatus
    let isTesting: Bool
    let onClose: () -> Void
    let onSave: () -> Void
    let onTest: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("API Engine")
                        .font(.title3.weight(.semibold))
                    HStack(spacing: 8) {
                        EngineIndicatorLight(state: status.state)
                        Text(status.detail)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }

            VStack(alignment: .leading, spacing: 12) {
                TextField("Base URL", text: $config.apiBaseURL)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))

                TextField("Model", text: $config.apiModel)
                    .textFieldStyle(.roundedBorder)

                SecureField("API Token", text: $config.apiToken)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Where to find tokens")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Link("OpenAI API keys", destination: URL(string: "https://platform.openai.com/api-keys")!)
                Link("OpenRouter keys", destination: URL(string: "https://openrouter.ai/settings/keys")!)
            }
            .font(.caption)

            HStack {
                Button("Close", action: onClose)
                Spacer()
                Button(isTesting ? "Testing…" : "Test Connection", action: onTest)
                    .disabled(isTesting)
                Button("Save", action: onSave)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}
