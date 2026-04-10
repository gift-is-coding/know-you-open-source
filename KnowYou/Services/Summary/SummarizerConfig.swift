import Foundation

struct SummarizerConfig {
    var defaultEngine: DiaryEngine
    var claudeCLIPath: String
    var codexCLIPath: String
    var geminiCLIPath: String
    var openclawCLIPath: String
    var apiBaseURL: String
    var apiModel: String
    var apiToken: String

    var type: DiaryEngine {
        get { defaultEngine }
        set { defaultEngine = newValue }
    }

    var openAIKey: String {
        get { apiToken }
        set { apiToken = newValue }
    }

    var apiConfigurationIsComplete: Bool {
        validatedAPIBaseURL() != nil &&
        !apiModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !apiToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static let `default` = SummarizerConfig(
        defaultEngine: .none,
        claudeCLIPath: "/usr/local/bin/claude",
        codexCLIPath: "/usr/local/bin/codex",
        geminiCLIPath: "/usr/local/bin/gemini",
        openclawCLIPath: "/usr/local/bin/openclaw",
        apiBaseURL: "https://api.openai.com/v1/responses",
        apiModel: "gpt-5",
        apiToken: ""
    )

    private enum Keys {
        static let defaultEngine = "summarizerDefaultEngine"
        static let legacyType = "summarizerType"
        static let claudeCLIPath = "summarizerClaudeCLIPath"
        static let codexCLIPath = "summarizerCodexCLIPath"
        static let geminiCLIPath = "summarizerGeminiCLIPath"
        static let openclawCLIPath = "summarizerOpenclawCLIPath"
        static let apiBaseURL = "summarizerAPIBaseURL"
        static let apiModel = "summarizerAPIModel"
        static let apiToken = "summarizerAPIToken"
        static let legacyOpenAIKey = "summarizerOpenAIKey"
    }

    func save(
        to defaults: UserDefaults = .standard,
        keychain: KeychainStoring = KeychainHelper.shared,
        keychainService: String = KeychainHelper.service
    ) {
        defaults.set(defaultEngine.rawValue, forKey: Keys.defaultEngine)
        defaults.set(defaultEngine.rawValue, forKey: Keys.legacyType)
        defaults.set(claudeCLIPath, forKey: Keys.claudeCLIPath)
        defaults.set(codexCLIPath, forKey: Keys.codexCLIPath)
        defaults.set(geminiCLIPath, forKey: Keys.geminiCLIPath)
        defaults.set(openclawCLIPath, forKey: Keys.openclawCLIPath)
        defaults.set(apiBaseURL, forKey: Keys.apiBaseURL)
        defaults.set(apiModel, forKey: Keys.apiModel)
        if apiToken.isEmpty {
            keychain.delete(forKey: Keys.apiToken, service: keychainService)
            keychain.delete(forKey: Keys.legacyOpenAIKey, service: keychainService)
        } else {
            keychain.save(apiToken, forKey: Keys.apiToken, service: keychainService)
            keychain.save(apiToken, forKey: Keys.legacyOpenAIKey, service: keychainService)
        }
    }

    static func load(
        from defaults: UserDefaults = .standard,
        keychain: KeychainStoring = KeychainHelper.shared,
        keychainService: String = KeychainHelper.service
    ) -> SummarizerConfig {
        let rawType = defaults.string(forKey: Keys.defaultEngine)
            ?? defaults.string(forKey: Keys.legacyType)
            ?? ""
        return SummarizerConfig(
            defaultEngine: DiaryEngine(rawValue: rawType) ?? .none,
            claudeCLIPath: defaults.string(forKey: Keys.claudeCLIPath) ?? SummarizerConfig.default.claudeCLIPath,
            codexCLIPath: defaults.string(forKey: Keys.codexCLIPath) ?? SummarizerConfig.default.codexCLIPath,
            geminiCLIPath: defaults.string(forKey: Keys.geminiCLIPath) ?? SummarizerConfig.default.geminiCLIPath,
            openclawCLIPath: defaults.string(forKey: Keys.openclawCLIPath) ?? SummarizerConfig.default.openclawCLIPath,
            apiBaseURL: defaults.string(forKey: Keys.apiBaseURL) ?? SummarizerConfig.default.apiBaseURL,
            apiModel: defaults.string(forKey: Keys.apiModel) ?? SummarizerConfig.default.apiModel,
            apiToken: keychain.load(forKey: Keys.apiToken, service: keychainService)
                ?? keychain.load(forKey: Keys.legacyOpenAIKey, service: keychainService)
                ?? ""
        )
    }

    func makeSummarizer(environment: [String: String] = ProcessInfo.processInfo.environment) -> SummaryGenerating? {
        makeSummarizer(for: defaultEngine, environment: environment)
    }

    func makeSummarizer(
        for engine: DiaryEngine,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> SummaryGenerating? {
        switch engine {
        case .none:
            return nil
        case .openAI:
            let key = apiToken.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedModel = apiModel.trimmingCharacters(in: .whitespacesAndNewlines)
            guard
                !key.isEmpty,
                !trimmedModel.isEmpty,
                let url = validatedAPIBaseURL()
            else {
                return nil
            }
            return CloudSummarizer(apiKey: key, apiURL: url, model: trimmedModel)
        case .claudeCLI:
            guard let path = Self.resolvedExecutablePath(configuredPath: claudeCLIPath, commandName: "claude", environment: environment) else {
                return nil
            }
            return CLISummarizer(tool: .claude, executablePath: path)
        case .codexCLI:
            guard let path = Self.resolvedExecutablePath(configuredPath: codexCLIPath, commandName: "codex", environment: environment) else {
                return nil
            }
            return CLISummarizer(tool: .codex, executablePath: path)
        case .geminiCLI:
            guard let path = Self.resolvedExecutablePath(configuredPath: geminiCLIPath, commandName: "gemini", environment: environment) else {
                return nil
            }
            return CLISummarizer(tool: .gemini, executablePath: path)
        case .openclawCLI:
            guard let path = Self.resolvedExecutablePath(configuredPath: openclawCLIPath, commandName: "openclaw", environment: environment) else {
                return nil
            }
            return CLISummarizer(tool: .openclaw, executablePath: path)
        }
    }

    static func resolvedExecutablePath(
        configuredPath: String,
        commandName: String,
        environment: [String: String]
    ) -> String? {
        let trimmedConfiguredPath = configuredPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if FileManager.default.isExecutableFile(atPath: trimmedConfiguredPath) {
            return trimmedConfiguredPath
        }

        let pathEntries = (environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
            .filter { !$0.isEmpty }

        for entry in pathEntries {
            let candidate = URL(fileURLWithPath: entry).appendingPathComponent(commandName).path
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }

        return nil
    }

    private func validatedAPIBaseURL() -> URL? {
        let trimmedBaseURL = apiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBaseURL.isEmpty else {
            return nil
        }

        guard
            let components = URLComponents(string: trimmedBaseURL),
            let scheme = components.scheme?.lowercased(),
            scheme == "http" || scheme == "https",
            components.host != nil,
            let url = components.url
        else {
            return nil
        }

        return url
    }
}
