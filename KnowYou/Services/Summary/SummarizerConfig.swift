import Foundation

enum SummarizerType: String, CaseIterable {
    case none
    case openAI
    case claudeCLI
    case codexCLI
    case geminiCLI

    var displayName: String {
        switch self {
        case .none: return "None"
        case .openAI: return "OpenAI API"
        case .claudeCLI: return "Claude Code (CLI)"
        case .codexCLI: return "Codex (CLI)"
        case .geminiCLI: return "Gemini (CLI)"
        }
    }
}

struct SummarizerConfig {
    var type: SummarizerType
    var openAIKey: String
    var claudeCLIPath: String
    var codexCLIPath: String
    var geminiCLIPath: String

    static let `default` = SummarizerConfig(
        type: .none,
        openAIKey: "",
        claudeCLIPath: "/usr/local/bin/claude",
        codexCLIPath: "/usr/local/bin/codex",
        geminiCLIPath: "/usr/local/bin/gemini"
    )

    private enum Keys {
        static let type = "summarizerType"
        static let claudeCLIPath = "summarizerClaudeCLIPath"
        static let codexCLIPath = "summarizerCodexCLIPath"
        static let geminiCLIPath = "summarizerGeminiCLIPath"
        // openAIKey is stored in Keychain, not UserDefaults
        static let openAIKey = "summarizerOpenAIKey"
    }

    func save(
        to defaults: UserDefaults = .standard,
        keychain: KeychainStoring = KeychainHelper.shared,
        keychainService: String = KeychainHelper.service
    ) {
        defaults.set(type.rawValue, forKey: Keys.type)
        defaults.set(claudeCLIPath, forKey: Keys.claudeCLIPath)
        defaults.set(codexCLIPath, forKey: Keys.codexCLIPath)
        defaults.set(geminiCLIPath, forKey: Keys.geminiCLIPath)
        if openAIKey.isEmpty {
            keychain.delete(forKey: Keys.openAIKey, service: keychainService)
        } else {
            keychain.save(openAIKey, forKey: Keys.openAIKey, service: keychainService)
        }
    }

    static func load(
        from defaults: UserDefaults = .standard,
        keychain: KeychainStoring = KeychainHelper.shared,
        keychainService: String = KeychainHelper.service
    ) -> SummarizerConfig {
        let rawType = defaults.string(forKey: Keys.type) ?? ""
        return SummarizerConfig(
            type: SummarizerType(rawValue: rawType) ?? .none,
            openAIKey: keychain.load(forKey: Keys.openAIKey, service: keychainService) ?? "",
            claudeCLIPath: defaults.string(forKey: Keys.claudeCLIPath) ?? SummarizerConfig.default.claudeCLIPath,
            codexCLIPath: defaults.string(forKey: Keys.codexCLIPath) ?? SummarizerConfig.default.codexCLIPath,
            geminiCLIPath: defaults.string(forKey: Keys.geminiCLIPath) ?? SummarizerConfig.default.geminiCLIPath
        )
    }

    func makeSummarizer() -> SummaryGenerating? {
        switch type {
        case .none:
            return nil
        case .openAI:
            let key = openAIKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { return nil }
            return CloudSummarizer(apiKey: key)
        case .claudeCLI:
            guard FileManager.default.isExecutableFile(atPath: claudeCLIPath) else { return nil }
            return CLISummarizer(tool: .claude, executablePath: claudeCLIPath)
        case .codexCLI:
            guard FileManager.default.isExecutableFile(atPath: codexCLIPath) else { return nil }
            return CLISummarizer(tool: .codex, executablePath: codexCLIPath)
        case .geminiCLI:
            guard FileManager.default.isExecutableFile(atPath: geminiCLIPath) else { return nil }
            return CLISummarizer(tool: .gemini, executablePath: geminiCLIPath)
        }
    }
}
