import SwiftUI

struct EngineConfigurationSection: View {
    @Binding var summarizerConfig: SummarizerConfig

    let lead: String
    let footnote: String?

    init(
        summarizerConfig: Binding<SummarizerConfig>,
        lead: String,
        footnote: String? = nil
    ) {
        _summarizerConfig = summarizerConfig
        self.lead = lead
        self.footnote = footnote
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(lead)
                .font(.callout)
                .foregroundStyle(.secondary)

            Picker("Engine", selection: $summarizerConfig.type) {
                Text("Choose an engine").tag(SummarizerType.none)
                Text(SummarizerType.claudeCLI.displayName).tag(SummarizerType.claudeCLI)
                Text(SummarizerType.codexCLI.displayName).tag(SummarizerType.codexCLI)
                Text(SummarizerType.geminiCLI.displayName).tag(SummarizerType.geminiCLI)
                Text(SummarizerType.openclawCLI.displayName).tag(SummarizerType.openclawCLI)
                Text(SummarizerType.openAI.displayName).tag(SummarizerType.openAI)
            }
            .pickerStyle(.menu)

            configurationFields

            Text(configurationHint)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let footnote {
                Text(footnote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var configurationFields: some View {
        switch summarizerConfig.type {
        case .none:
            Text("Choose the CLI or API you already use. KnowYou starts working once an engine is connected.")
                .font(.callout)
                .foregroundStyle(.secondary)

        case .openAI:
            SecureField("OpenAI API Key", text: $summarizerConfig.openAIKey)
                .textFieldStyle(.roundedBorder)

        case .claudeCLI:
            executablePathField("claude executable path", text: $summarizerConfig.claudeCLIPath)

        case .codexCLI:
            executablePathField("codex executable path", text: $summarizerConfig.codexCLIPath)

        case .geminiCLI:
            executablePathField("gemini executable path", text: $summarizerConfig.geminiCLIPath)

        case .openclawCLI:
            executablePathField("openclaw executable path", text: $summarizerConfig.openclawCLIPath)
        }
    }

    private var configurationHint: String {
        switch summarizerConfig.type {
        case .none:
            return "Select Claude Code, Codex, Gemini, or OpenAI to activate the writer."
        case .openAI:
            return "The API key stays on this Mac and is used only when KnowYou asks the selected engine to shape the diary."
        case .claudeCLI:
            return "Point this at the Claude Code executable already installed on this Mac."
        case .codexCLI:
            return "Point this at the Codex executable already installed on this Mac."
        case .geminiCLI:
            return "Point this at the Gemini executable already installed on this Mac."
        case .openclawCLI:
            return "Point this at the Openclaw executable already installed on this Mac."
        }
    }

    private func executablePathField(_ title: String, text: Binding<String>) -> some View {
        TextField(title, text: text)
            .textFieldStyle(.roundedBorder)
            .font(.system(.body, design: .monospaced))
    }
}
