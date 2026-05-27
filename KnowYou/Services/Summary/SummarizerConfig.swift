import Foundation

typealias SummarizerType = DiaryEngine

enum LLMAPIProviderID: String, CaseIterable, Codable, Sendable, Identifiable {
    case openAI
    case anthropic
    case deepSeek
    case openRouter
    case gemini
    case qwen
    case kimi
    case zhipu
    case customOpenAICompatible

    var id: String { rawValue }

    var descriptor: LLMAPIProviderDescriptor {
        switch self {
        case .openAI:
            return LLMAPIProviderDescriptor(
                id: self,
                displayName: "OpenAI",
                defaultBaseURL: "https://api.openai.com/v1/responses",
                defaultModel: "gpt-5",
                defaultWireFormat: .openAIResponses,
                keyURL: URL(string: "https://platform.openai.com/api-keys")!,
                docsURL: URL(string: "https://platform.openai.com/docs/guides/text?api-mode=responses")!,
                isOpenAICompatible: true
            )
        case .anthropic:
            return LLMAPIProviderDescriptor(
                id: self,
                displayName: "Anthropic",
                defaultBaseURL: "https://api.anthropic.com/v1/messages",
                defaultModel: "claude-sonnet-4-5",
                defaultWireFormat: .anthropicMessages,
                keyURL: URL(string: "https://console.anthropic.com/settings/keys")!,
                docsURL: URL(string: "https://docs.anthropic.com/en/api/messages-examples")!,
                isOpenAICompatible: false
            )
        case .deepSeek:
            return LLMAPIProviderDescriptor(
                id: self,
                displayName: "DeepSeek",
                defaultBaseURL: "https://api.deepseek.com",
                defaultModel: "deepseek-v4-pro",
                defaultWireFormat: .openAIChat,
                keyURL: URL(string: "https://platform.deepseek.com/api_keys")!,
                docsURL: URL(string: "https://api-docs.deepseek.com/")!,
                isOpenAICompatible: true
            )
        case .openRouter:
            return LLMAPIProviderDescriptor(
                id: self,
                displayName: "OpenRouter",
                defaultBaseURL: "https://openrouter.ai/api/v1",
                defaultModel: "openai/gpt-5",
                defaultWireFormat: .openAIChat,
                keyURL: URL(string: "https://openrouter.ai/settings/keys")!,
                docsURL: URL(string: "https://openrouter.ai/docs/api-reference/chat-completion")!,
                isOpenAICompatible: true
            )
        case .gemini:
            return LLMAPIProviderDescriptor(
                id: self,
                displayName: "Google Gemini",
                defaultBaseURL: "https://generativelanguage.googleapis.com/v1beta",
                defaultModel: "gemini-3.5-flash",
                defaultWireFormat: .geminiGenerateContent,
                keyURL: URL(string: "https://aistudio.google.com/app/apikey")!,
                docsURL: URL(string: "https://ai.google.dev/gemini-api/docs/text-generation")!,
                isOpenAICompatible: false
            )
        case .qwen:
            return LLMAPIProviderDescriptor(
                id: self,
                displayName: "Qwen / 通义千问",
                defaultBaseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1",
                defaultModel: "qwen-plus",
                defaultWireFormat: .openAIChat,
                keyURL: URL(string: "https://bailian.console.aliyun.com/?apiKey=1")!,
                docsURL: URL(string: "https://help.aliyun.com/zh/model-studio/compatibility-of-openai-with-dashscope")!,
                isOpenAICompatible: true
            )
        case .kimi:
            return LLMAPIProviderDescriptor(
                id: self,
                displayName: "Kimi / Moonshot",
                defaultBaseURL: "https://api.moonshot.ai/v1",
                defaultModel: "kimi-k2.5",
                defaultWireFormat: .openAIChat,
                keyURL: URL(string: "https://platform.moonshot.ai/console/api-keys")!,
                docsURL: URL(string: "https://platform.moonshot.ai/docs/guide/kimi-k2-5-quickstart")!,
                isOpenAICompatible: true
            )
        case .zhipu:
            return LLMAPIProviderDescriptor(
                id: self,
                displayName: "Zhipu GLM",
                defaultBaseURL: "https://open.bigmodel.cn/api/paas/v4",
                defaultModel: "glm-5.1",
                defaultWireFormat: .openAIChat,
                keyURL: URL(string: "https://bigmodel.cn/usercenter/proj-mgmt/apikeys")!,
                docsURL: URL(string: "https://docs.bigmodel.cn/cn/guide/start/quick-start")!,
                isOpenAICompatible: true
            )
        case .customOpenAICompatible:
            return LLMAPIProviderDescriptor(
                id: self,
                displayName: "Custom OpenAI-compatible",
                defaultBaseURL: "",
                defaultModel: "",
                defaultWireFormat: .openAIChat,
                keyURL: URL(string: "https://platform.openai.com/docs/api-reference/chat")!,
                docsURL: URL(string: "https://platform.openai.com/docs/api-reference/chat")!,
                isOpenAICompatible: true
            )
        }
    }

    var defaultConfig: LLMAPIProviderConfig {
        let descriptor = descriptor
        return LLMAPIProviderConfig(
            id: self,
            baseURL: descriptor.defaultBaseURL,
            model: descriptor.defaultModel,
            wireFormat: descriptor.defaultWireFormat,
            apiToken: ""
        )
    }

    static func inferredProviderID(forLegacyBaseURL baseURL: String?) -> LLMAPIProviderID {
        let lowercasedBaseURL = (baseURL ?? "").lowercased()
        if lowercasedBaseURL.contains("openrouter.ai") {
            return .openRouter
        }
        if lowercasedBaseURL.contains("deepseek.com") {
            return .deepSeek
        }
        if lowercasedBaseURL.contains("dashscope.aliyuncs.com") {
            return .qwen
        }
        if lowercasedBaseURL.contains("moonshot.ai") {
            return .kimi
        }
        if lowercasedBaseURL.contains("bigmodel.cn") || lowercasedBaseURL.contains("open.bigmodel.cn") {
            return .zhipu
        }
        if lowercasedBaseURL.contains("anthropic.com") {
            return .anthropic
        }
        if lowercasedBaseURL.contains("generativelanguage.googleapis.com") {
            return .gemini
        }
        if lowercasedBaseURL.isEmpty || lowercasedBaseURL.contains("api.openai.com") {
            return .openAI
        }
        return .customOpenAICompatible
    }
}

enum LLMAPIWireFormat: String, CaseIterable, Codable, Sendable {
    case openAIResponses = "openai_responses"
    case openAIChat = "openai_chat"
    case anthropicMessages = "anthropic_messages"
    case geminiGenerateContent = "gemini_generate_content"

    var displayName: String {
        switch self {
        case .openAIResponses:
            return "OpenAI Responses"
        case .openAIChat:
            return "OpenAI-compatible Chat"
        case .anthropicMessages:
            return "Anthropic Messages"
        case .geminiGenerateContent:
            return "Gemini generateContent"
        }
    }

    var shortDescription: String {
        switch self {
        case .openAIResponses:
            return "POST { model, input } and read output_text or output message text."
        case .openAIChat:
            return "POST { model, messages, stream:false } and read choices[0].message.content."
        case .anthropicMessages:
            return "POST Messages API with x-api-key and anthropic-version headers."
        case .geminiGenerateContent:
            return "POST generateContent with x-goog-api-key and read candidate text parts."
        }
    }
}

struct LLMAPIProviderDescriptor: Identifiable, Equatable, Sendable {
    let id: LLMAPIProviderID
    let displayName: String
    let defaultBaseURL: String
    let defaultModel: String
    let defaultWireFormat: LLMAPIWireFormat
    let keyURL: URL
    let docsURL: URL
    let isOpenAICompatible: Bool
}

struct LLMAPIProviderConfig: Identifiable, Codable, Equatable, Sendable {
    let id: LLMAPIProviderID
    var baseURL: String
    var model: String
    var wireFormat: LLMAPIWireFormat
    var apiToken: String

    var descriptor: LLMAPIProviderDescriptor { id.descriptor }

    var isComplete: Bool {
        validatedBaseURL() != nil &&
        !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !apiToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init(
        id: LLMAPIProviderID,
        baseURL: String,
        model: String,
        wireFormat: LLMAPIWireFormat,
        apiToken: String = ""
    ) {
        self.id = id
        self.baseURL = baseURL
        self.model = model
        self.wireFormat = wireFormat
        self.apiToken = apiToken
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedID = try container.decode(LLMAPIProviderID.self, forKey: .id)
        id = decodedID
        baseURL = try container.decodeIfPresent(String.self, forKey: .baseURL)
            ?? decodedID.descriptor.defaultBaseURL
        model = try container.decodeIfPresent(String.self, forKey: .model)
            ?? decodedID.descriptor.defaultModel
        wireFormat = (try? container.decodeIfPresent(LLMAPIWireFormat.self, forKey: .wireFormat))
            ?? decodedID.descriptor.defaultWireFormat
        apiToken = ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(baseURL, forKey: .baseURL)
        try container.encode(model, forKey: .model)
        try container.encode(wireFormat, forKey: .wireFormat)
    }

    func validatedBaseURL() -> URL? {
        let trimmedBaseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
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

    private enum CodingKeys: String, CodingKey {
        case id
        case baseURL
        case model
        case wireFormat
    }
}

struct SummarizerConfig {
    var defaultEngine: DiaryEngine
    var claudeCLIPath: String
    var codexCLIPath: String
    var geminiCLIPath: String
    var openclawCLIPath: String
    var activeLLMAPIProviderID: LLMAPIProviderID
    var llmAPIProviderConfigs: [LLMAPIProviderConfig]

    init(
        defaultEngine: DiaryEngine,
        claudeCLIPath: String,
        codexCLIPath: String,
        geminiCLIPath: String,
        openclawCLIPath: String,
        activeLLMAPIProviderID: LLMAPIProviderID = .openAI,
        llmAPIProviderConfigs: [LLMAPIProviderConfig] = LLMAPIProviderID.allCases.map { $0.defaultConfig }
    ) {
        self.defaultEngine = defaultEngine
        self.claudeCLIPath = claudeCLIPath
        self.codexCLIPath = codexCLIPath
        self.geminiCLIPath = geminiCLIPath
        self.openclawCLIPath = openclawCLIPath
        self.activeLLMAPIProviderID = activeLLMAPIProviderID
        self.llmAPIProviderConfigs = Self.normalizedProviderConfigs(llmAPIProviderConfigs)
    }

    var type: DiaryEngine {
        get { defaultEngine }
        set { defaultEngine = newValue }
    }

    var apiBaseURL: String {
        get { activeLLMAPIProviderConfig.baseURL }
        set {
            updateActiveLLMAPIProviderConfig { providerConfig in
                providerConfig.baseURL = newValue
            }
        }
    }

    var apiModel: String {
        get { activeLLMAPIProviderConfig.model }
        set {
            updateActiveLLMAPIProviderConfig { providerConfig in
                providerConfig.model = newValue
            }
        }
    }

    var apiToken: String {
        get { activeLLMAPIProviderConfig.apiToken }
        set {
            updateActiveLLMAPIProviderConfig { providerConfig in
                providerConfig.apiToken = newValue
            }
        }
    }

    var openAIKey: String {
        get { apiToken }
        set { apiToken = newValue }
    }

    var apiConfigurationIsComplete: Bool {
        activeLLMAPIProviderConfig.isComplete
    }

    var activeLLMAPIProviderConfig: LLMAPIProviderConfig {
        llmAPIProviderConfig(for: activeLLMAPIProviderID) ?? activeLLMAPIProviderID.defaultConfig
    }

    static let `default` = SummarizerConfig(
        defaultEngine: .none,
        claudeCLIPath: "/usr/local/bin/claude",
        codexCLIPath: "/usr/local/bin/codex",
        geminiCLIPath: "/usr/local/bin/gemini",
        openclawCLIPath: "/usr/local/bin/openclaw"
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
        static let legacyGlobalDiaryPromptOverride = "summarizerGlobalDiaryPromptOverride"
        static let legacyOpenAIKey = "summarizerOpenAIKey"
        static let activeLLMAPIProviderID = "summarizerActiveLLMAPIProviderID"
        static let llmAPIProviderConfigs = "summarizerLLMAPIProviderConfigs"

        static func llmAPIToken(providerID: LLMAPIProviderID) -> String {
            "summarizerLLMAPIToken.\(providerID.rawValue)"
        }
    }

    func save(
        to defaults: UserDefaults = .standard,
        keychain: KeychainStoring = KeychainHelper.shared,
        keychainService: String = KeychainHelper.service
    ) {
        let providerConfigs = Self.normalizedProviderConfigs(llmAPIProviderConfigs)
        let activeProviderConfig = providerConfigs.first { $0.id == activeLLMAPIProviderID }
            ?? activeLLMAPIProviderID.defaultConfig

        defaults.set(defaultEngine.rawValue, forKey: Keys.defaultEngine)
        defaults.set(defaultEngine.rawValue, forKey: Keys.legacyType)
        defaults.set(claudeCLIPath, forKey: Keys.claudeCLIPath)
        defaults.set(codexCLIPath, forKey: Keys.codexCLIPath)
        defaults.set(geminiCLIPath, forKey: Keys.geminiCLIPath)
        defaults.set(openclawCLIPath, forKey: Keys.openclawCLIPath)
        defaults.set(activeLLMAPIProviderID.rawValue, forKey: Keys.activeLLMAPIProviderID)
        defaults.set(activeProviderConfig.baseURL, forKey: Keys.apiBaseURL)
        defaults.set(activeProviderConfig.model, forKey: Keys.apiModel)
        if let data = try? JSONEncoder().encode(providerConfigs) {
            defaults.set(data, forKey: Keys.llmAPIProviderConfigs)
        }
        defaults.removeObject(forKey: Keys.legacyGlobalDiaryPromptOverride)
        for providerConfig in providerConfigs {
            let tokenKey = Keys.llmAPIToken(providerID: providerConfig.id)
            if providerConfig.apiToken.isEmpty {
                keychain.delete(forKey: tokenKey, service: keychainService)
            } else {
                keychain.save(providerConfig.apiToken, forKey: tokenKey, service: keychainService)
            }
        }
        if activeProviderConfig.apiToken.isEmpty {
            keychain.delete(forKey: Keys.apiToken, service: keychainService)
            keychain.delete(forKey: Keys.legacyOpenAIKey, service: keychainService)
        } else {
            keychain.save(activeProviderConfig.apiToken, forKey: Keys.apiToken, service: keychainService)
            keychain.save(activeProviderConfig.apiToken, forKey: Keys.legacyOpenAIKey, service: keychainService)
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
        defaults.removeObject(forKey: Keys.legacyGlobalDiaryPromptOverride)

        let legacyBaseURL = defaults.string(forKey: Keys.apiBaseURL)
        let legacyModel = defaults.string(forKey: Keys.apiModel)
        let legacyToken = keychain.load(forKey: Keys.apiToken, service: keychainService)
            ?? keychain.load(forKey: Keys.legacyOpenAIKey, service: keychainService)
            ?? ""
        let persistedProviderConfigs = Self.loadPersistedProviderConfigs(from: defaults)
        let hasPersistedProviderConfigs = persistedProviderConfigs != nil
        var providerConfigs = persistedProviderConfigs ?? LLMAPIProviderID.allCases.map { $0.defaultConfig }
        var activeProviderID = defaults.string(forKey: Keys.activeLLMAPIProviderID)
            .flatMap(LLMAPIProviderID.init(rawValue:))
            ?? .openAI

        let hasLegacyAPIConfig = legacyBaseURL != nil || legacyModel != nil || !legacyToken.isEmpty
        if !hasPersistedProviderConfigs, hasLegacyAPIConfig {
            let migratedProviderID = LLMAPIProviderID.inferredProviderID(forLegacyBaseURL: legacyBaseURL)
            activeProviderID = migratedProviderID
            var migratedConfig = providerConfigs.first { $0.id == migratedProviderID } ?? migratedProviderID.defaultConfig
            if let legacyBaseURL, !legacyBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                migratedConfig.baseURL = legacyBaseURL
            }
            if let legacyModel, !legacyModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                migratedConfig.model = legacyModel
            }
            migratedConfig.apiToken = legacyToken
            Self.setProviderConfig(migratedConfig, in: &providerConfigs)
        }

        providerConfigs = providerConfigs.map { providerConfig in
            var providerConfig = providerConfig
            let providerToken = keychain.load(
                forKey: Keys.llmAPIToken(providerID: providerConfig.id),
                service: keychainService
            )
            let fallbackLegacyToken = (providerConfig.id == .openAI || providerConfig.id == activeProviderID)
                ? legacyToken
                : ""
            providerConfig.apiToken = providerToken ?? fallbackLegacyToken
            return providerConfig
        }

        return SummarizerConfig(
            defaultEngine: DiaryEngine.persistedEngine(rawValue: rawType) ?? .none,
            claudeCLIPath: defaults.string(forKey: Keys.claudeCLIPath) ?? SummarizerConfig.default.claudeCLIPath,
            codexCLIPath: defaults.string(forKey: Keys.codexCLIPath) ?? SummarizerConfig.default.codexCLIPath,
            geminiCLIPath: defaults.string(forKey: Keys.geminiCLIPath) ?? SummarizerConfig.default.geminiCLIPath,
            openclawCLIPath: defaults.string(forKey: Keys.openclawCLIPath) ?? SummarizerConfig.default.openclawCLIPath,
            activeLLMAPIProviderID: activeProviderID,
            llmAPIProviderConfigs: providerConfigs
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
        case .llmAPI:
            let providerConfig = activeLLMAPIProviderConfig
            let key = providerConfig.apiToken.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedModel = providerConfig.model.trimmingCharacters(in: .whitespacesAndNewlines)
            guard
                !key.isEmpty,
                !trimmedModel.isEmpty,
                providerConfig.validatedBaseURL() != nil
            else {
                return nil
            }
            return CloudSummarizer(providerConfig: providerConfig)
        case .codexAuth:
            let store = CodexAuthStore(environment: environment)
            let refresher = CodexOAuthRefresher()
            return CodexDirectSummarizer(
                credentialProvider: CodexCredentialProvider(store: store, refresher: refresher)
            )
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

    func llmAPIProviderConfig(for providerID: LLMAPIProviderID) -> LLMAPIProviderConfig? {
        llmAPIProviderConfigs.first { $0.id == providerID } ?? providerID.defaultConfig
    }

    mutating func setLLMAPIProviderConfig(_ providerConfig: LLMAPIProviderConfig) {
        Self.setProviderConfig(providerConfig, in: &llmAPIProviderConfigs)
        llmAPIProviderConfigs = Self.normalizedProviderConfigs(llmAPIProviderConfigs)
    }

    func validatedLLMAPIBaseURL(for providerID: LLMAPIProviderID) -> URL? {
        llmAPIProviderConfig(for: providerID)?.validatedBaseURL()
    }

    private mutating func updateActiveLLMAPIProviderConfig(_ update: (inout LLMAPIProviderConfig) -> Void) {
        var providerConfig = activeLLMAPIProviderConfig
        update(&providerConfig)
        setLLMAPIProviderConfig(providerConfig)
    }

    private static func loadPersistedProviderConfigs(from defaults: UserDefaults) -> [LLMAPIProviderConfig]? {
        guard
            let data = defaults.data(forKey: Keys.llmAPIProviderConfigs),
            let decodedConfigs = try? JSONDecoder().decode([LLMAPIProviderConfig].self, from: data)
        else {
            return nil
        }

        return normalizedProviderConfigs(decodedConfigs)
    }

    private static func normalizedProviderConfigs(
        _ providerConfigs: [LLMAPIProviderConfig]
    ) -> [LLMAPIProviderConfig] {
        var providersByID = Dictionary(
            uniqueKeysWithValues: LLMAPIProviderID.allCases.map { ($0, $0.defaultConfig) }
        )
        for providerConfig in providerConfigs {
            var normalizedConfig = providerConfig
            normalizedConfig.wireFormat = providerConfig.id.descriptor.defaultWireFormat
            providersByID[providerConfig.id] = normalizedConfig
        }
        return LLMAPIProviderID.allCases.compactMap { providersByID[$0] }
    }

    private static func setProviderConfig(
        _ providerConfig: LLMAPIProviderConfig,
        in providerConfigs: inout [LLMAPIProviderConfig]
    ) {
        providerConfigs.removeAll { $0.id == providerConfig.id }
        providerConfigs.append(providerConfig)
    }

    static func resolvedExecutablePath(
        configuredPath: String,
        commandName: String,
        environment: [String: String],
        fallbackSearchDirectories: [String] = []
    ) -> String? {
        for candidate in candidateExecutablePaths(
            configuredPath: configuredPath,
            commandName: commandName,
            environment: environment,
            fallbackSearchDirectories: fallbackSearchDirectories
        ) {
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }

        return nil
    }

    private static func candidateExecutablePaths(
        configuredPath: String,
        commandName: String,
        environment: [String: String],
        fallbackSearchDirectories: [String] = []
    ) -> [String] {
        var candidates: [String] = []
        var seen: Set<String> = []

        func append(_ path: String) {
            let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else {
                return
            }
            candidates.append(trimmed)
        }

        append(configuredPath)

        let pathEntries = (environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
            .filter { !$0.isEmpty }
        for entry in pathEntries {
            append(URL(fileURLWithPath: entry).appendingPathComponent(commandName).path)
        }

        for directory in commonExecutableDirectories(environment: environment) {
            append(URL(fileURLWithPath: directory).appendingPathComponent(commandName).path)
        }

        for directory in fallbackSearchDirectories {
            append(URL(fileURLWithPath: directory).appendingPathComponent(commandName).path)
        }

        for path in nvmExecutablePaths(commandName: commandName, environment: environment) {
            append(path)
        }

        return candidates
    }

    private static func commonExecutableDirectories(environment: [String: String]) -> [String] {
        let homeDirectory = resolvedHomeDirectory(environment: environment)

        return [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/opt/local/bin",
            URL(fileURLWithPath: homeDirectory).appendingPathComponent(".local/bin").path,
            URL(fileURLWithPath: homeDirectory).appendingPathComponent(".bun/bin").path
        ]
    }

    private static func nvmExecutablePaths(
        commandName: String,
        environment: [String: String]
    ) -> [String] {
        let homeDirectory = resolvedHomeDirectory(environment: environment)
        let nodeVersionsDirectory = URL(fileURLWithPath: homeDirectory)
            .appendingPathComponent(".nvm", isDirectory: true)
            .appendingPathComponent("versions", isDirectory: true)
            .appendingPathComponent("node", isDirectory: true)

        guard let versionDirectories = try? FileManager.default.contentsOfDirectory(
            at: nodeVersionsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return versionDirectories
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedDescending }
            .map { versionDirectory in
                versionDirectory
                    .appendingPathComponent("bin", isDirectory: true)
                    .appendingPathComponent(commandName)
                    .path
            }
    }

    private static func resolvedHomeDirectory(environment: [String: String]) -> String {
        let trimmedHome = environment["HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedHome.isEmpty {
            return trimmedHome
        }
        return FileManager.default.homeDirectoryForCurrentUser.path
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
