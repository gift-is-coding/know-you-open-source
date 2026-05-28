import Foundation

enum DiaryEngine: String, CaseIterable, Codable, Sendable {
    case none
    case llmAPI
    case codexAuth
    case claudeCLI
    case codexCLI
    case geminiCLI
    case openclawCLI

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = Self.persistedEngine(rawValue: rawValue) ?? .none
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    static func persistedEngine(rawValue: String) -> DiaryEngine? {
        if rawValue == "openAI" {
            return .llmAPI
        }
        return DiaryEngine(rawValue: rawValue)
    }

    var displayName: String {
        switch self {
        case .none: return "None"
        case .llmAPI: return "LLM API"
        case .codexAuth: return "Codex Auth"
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
        case .llmAPI:
            return "Use the active cloud LLM API provider."
        case .codexAuth:
            return "Use the Codex CLI login directly through Codex Auth."
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
