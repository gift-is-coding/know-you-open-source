import Foundation

enum DiaryEngine: String, CaseIterable, Codable, Sendable {
    case none
    case openAI
    case claudeCLI
    case codexCLI
    case geminiCLI
    case openclawCLI

    var displayName: String {
        switch self {
        case .none: return "None"
        case .openAI: return "OpenAI API"
        case .claudeCLI: return "Claude Code (CLI)"
        case .codexCLI: return "Codex (CLI)"
        case .geminiCLI: return "Gemini (CLI)"
        case .openclawCLI: return "Openclaw (CLI)"
        }
    }

    var shortDescription: String {
        switch self {
        case .none:
            return "No summarizer selected."
        case .openAI:
            return "Use an OpenAI-compatible API endpoint."
        case .claudeCLI:
            return "Use the local Claude Code CLI."
        case .codexCLI:
            return "Use the local Codex CLI."
        case .geminiCLI:
            return "Use the local Gemini CLI."
        case .openclawCLI:
            return "Use the local Openclaw CLI."
        }
    }
}

enum EngineIndicatorState: Equatable, Sendable {
    case gray
    case yellow
    case green
}
