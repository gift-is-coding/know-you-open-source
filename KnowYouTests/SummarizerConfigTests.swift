import XCTest
@testable import KnowYou

private final class InMemoryKeychainStore: KeychainStoring, @unchecked Sendable {
    private var values: [String: String] = [:]

    func save(_ value: String, forKey key: String, service: String) {
        values["\(service):\(key)"] = value
    }

    func load(forKey key: String, service: String) -> String? {
        values["\(service):\(key)"]
    }

    func delete(forKey key: String, service: String) {
        values.removeValue(forKey: "\(service):\(key)")
    }
}

final class SummarizerConfigTests: XCTestCase {
    private var defaults: UserDefaults!
    private var keychain: InMemoryKeychainStore!
    private var temporaryDirectoryURL: URL!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        keychain = InMemoryKeychainStore()
        temporaryDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: temporaryDirectoryURL, withIntermediateDirectories: true)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: defaults.description)
        try? FileManager.default.removeItem(at: temporaryDirectoryURL)
        super.tearDown()
    }

    func testDefaultConfigTypeIsNone() {
        let config = SummarizerConfig.load(from: defaults)
        XCTAssertEqual(config.type, .none)
    }

    func testSaveAndLoadRoundTripsOpenAIConfig() {
        var config = SummarizerConfig.load(from: defaults, keychain: keychain, keychainService: "tests")
        config.type = .llmAPI
        config.openAIKey = "sk-test-abc"
        config.save(to: defaults, keychain: keychain, keychainService: "tests")

        let loaded = SummarizerConfig.load(from: defaults, keychain: keychain, keychainService: "tests")
        XCTAssertEqual(loaded.type, .llmAPI)
        XCTAssertEqual(loaded.activeLLMAPIProviderID, .openAI)
        XCTAssertEqual(loaded.openAIKey, "sk-test-abc")
    }

    func testSaveAndLoadRoundTripsCLIPath() {
        var config = SummarizerConfig.load(from: defaults, keychain: keychain, keychainService: "tests")
        config.type = .claudeCLI
        config.claudeCLIPath = "/opt/homebrew/bin/claude"
        config.save(to: defaults, keychain: keychain, keychainService: "tests")

        let loaded = SummarizerConfig.load(from: defaults, keychain: keychain, keychainService: "tests")
        XCTAssertEqual(loaded.type, .claudeCLI)
        XCTAssertEqual(loaded.claudeCLIPath, "/opt/homebrew/bin/claude")
    }

    func testSaveAndLoadRoundTripsOpenclawCLIPath() {
        var config = SummarizerConfig.load(from: defaults, keychain: keychain, keychainService: "tests")
        config.defaultEngine = .openclawCLI
        config.openclawCLIPath = "/opt/homebrew/bin/openclaw"
        config.save(to: defaults, keychain: keychain, keychainService: "tests")

        let loaded = SummarizerConfig.load(from: defaults, keychain: keychain, keychainService: "tests")
        XCTAssertEqual(loaded.defaultEngine, .openclawCLI)
        XCTAssertEqual(loaded.openclawCLIPath, "/opt/homebrew/bin/openclaw")
    }

    func testSaveAndLoadRoundTripsOpenAICompatibleAPISettings() {
        var config = SummarizerConfig.load(from: defaults, keychain: keychain, keychainService: "tests")
        config.defaultEngine = .llmAPI
        config.activeLLMAPIProviderID = .openRouter
        config.apiBaseURL = "https://openrouter.ai/api/v1"
        config.apiModel = "openai/gpt-5"
        config.apiToken = "token-router-123"
        config.save(to: defaults, keychain: keychain, keychainService: "tests")

        let loaded = SummarizerConfig.load(from: defaults, keychain: keychain, keychainService: "tests")
        XCTAssertEqual(loaded.defaultEngine, .llmAPI)
        XCTAssertEqual(loaded.activeLLMAPIProviderID, .openRouter)
        XCTAssertEqual(loaded.apiBaseURL, "https://openrouter.ai/api/v1")
        XCTAssertEqual(loaded.apiModel, "openai/gpt-5")
        XCTAssertEqual(loaded.apiToken, "token-router-123")
    }

    func testSaveAndLoadRoundTripsMultipleLLMAPIProvidersAndActiveProvider() throws {
        var config = SummarizerConfig.load(from: defaults, keychain: keychain, keychainService: "tests")
        config.defaultEngine = .llmAPI
        config.setLLMAPIProviderConfig(
            LLMAPIProviderConfig(
                id: .anthropic,
                baseURL: "https://api.anthropic.com/v1/messages",
                model: "claude-sonnet-4-5",
                wireFormat: .anthropicMessages,
                apiToken: "sk-ant-test"
            )
        )
        config.setLLMAPIProviderConfig(
            LLMAPIProviderConfig(
                id: .deepSeek,
                baseURL: "https://api.deepseek.com",
                model: "deepseek-v4-pro",
                wireFormat: .openAIChat,
                apiToken: "sk-deepseek-test"
            )
        )
        config.activeLLMAPIProviderID = .deepSeek

        config.save(to: defaults, keychain: keychain, keychainService: "tests")

        let loaded = SummarizerConfig.load(from: defaults, keychain: keychain, keychainService: "tests")
        XCTAssertEqual(loaded.defaultEngine, .llmAPI)
        XCTAssertEqual(loaded.activeLLMAPIProviderID, .deepSeek)
        XCTAssertEqual(loaded.llmAPIProviderConfig(for: .anthropic)?.apiToken, "sk-ant-test")
        XCTAssertEqual(loaded.llmAPIProviderConfig(for: .deepSeek)?.apiToken, "sk-deepseek-test")
        XCTAssertEqual(loaded.llmAPIProviderConfig(for: .anthropic)?.wireFormat, .anthropicMessages)
        XCTAssertEqual(loaded.llmAPIProviderConfig(for: .deepSeek)?.wireFormat, .openAIChat)

        let persistedBlob = try XCTUnwrap(defaults.data(forKey: "summarizerLLMAPIProviderConfigs"))
        let persistedString = String(decoding: persistedBlob, as: UTF8.self)
        XCTAssertFalse(persistedString.contains("sk-ant-test"))
        XCTAssertFalse(persistedString.contains("sk-deepseek-test"))
    }

    func testProviderWireFormatIsNormalizedToDescriptorDefault() throws {
        var config = SummarizerConfig.load(from: defaults, keychain: keychain, keychainService: "tests")
        config.defaultEngine = .llmAPI
        config.setLLMAPIProviderConfig(
            LLMAPIProviderConfig(
                id: .anthropic,
                baseURL: "https://api.anthropic.com/v1/messages",
                model: "claude-sonnet-4-5",
                wireFormat: .openAIChat,
                apiToken: "sk-ant-test"
            )
        )
        config.activeLLMAPIProviderID = .anthropic

        config.save(to: defaults, keychain: keychain, keychainService: "tests")

        let loaded = SummarizerConfig.load(from: defaults, keychain: keychain, keychainService: "tests")
        XCTAssertEqual(loaded.llmAPIProviderConfig(for: .anthropic)?.wireFormat, .anthropicMessages)
    }

    func testLoadDefaultsMissingProviderWireFormat() throws {
        defaults.set("llmAPI", forKey: "summarizerDefaultEngine")
        defaults.set("anthropic", forKey: "summarizerActiveLLMAPIProviderID")
        defaults.set(
            Data(#"[{"id":"anthropic","baseURL":"https://api.anthropic.com/v1/messages","model":"claude-sonnet-4-5"}]"#.utf8),
            forKey: "summarizerLLMAPIProviderConfigs"
        )

        let loaded = SummarizerConfig.load(from: defaults, keychain: keychain, keychainService: "tests")

        XCTAssertEqual(loaded.activeLLMAPIProviderID, .anthropic)
        XCTAssertEqual(loaded.llmAPIProviderConfig(for: .anthropic)?.wireFormat, .anthropicMessages)
        XCTAssertEqual(loaded.llmAPIProviderConfig(for: .anthropic)?.baseURL, "https://api.anthropic.com/v1/messages")
    }

    func testLoadIgnoresAndClearsLegacyGlobalDiaryPromptOverride() {
        defaults.set("Use a reflective, concise diary voice.", forKey: "summarizerGlobalDiaryPromptOverride")

        _ = SummarizerConfig.load(from: defaults, keychain: keychain, keychainService: "tests")

        XCTAssertNil(defaults.string(forKey: "summarizerGlobalDiaryPromptOverride"))
    }

    func testSaveClearsLegacyGlobalDiaryPromptOverrideKey() {
        defaults.set("Use a reflective, concise diary voice.", forKey: "summarizerGlobalDiaryPromptOverride")
        let config = SummarizerConfig.load(from: defaults, keychain: keychain, keychainService: "tests")

        config.save(to: defaults, keychain: keychain, keychainService: "tests")

        XCTAssertNil(defaults.string(forKey: "summarizerGlobalDiaryPromptOverride"))
    }

    func testMakeSummarizerRejectsMalformedAPIBaseURL() {
        var config = SummarizerConfig.load(from: defaults)
        config.defaultEngine = .llmAPI
        config.apiBaseURL = "not-a-url"
        config.apiModel = "gpt-4.1-mini"
        config.apiToken = "token-test-123"

        XCTAssertFalse(config.apiConfigurationIsComplete)
        XCTAssertNil(config.makeSummarizer())
    }

    func testMakeSummarizerPlumbsCustomAPIBaseURLAndModelIntoCloudSummarizer() throws {
        var config = SummarizerConfig.load(from: defaults)
        config.defaultEngine = .llmAPI
        config.activeLLMAPIProviderID = .customOpenAICompatible
        config.apiBaseURL = "https://example.com/v1"
        config.apiModel = "openai/gpt-5"
        config.apiToken = "token-test-123"

        let summarizer = try XCTUnwrap(config.makeSummarizer() as? CloudSummarizer)
        XCTAssertEqual(summarizer.apiURL, URL(string: "https://example.com/v1"))
        XCTAssertEqual(summarizer.model, "openai/gpt-5")
        XCTAssertEqual(summarizer.providerConfig.id, .customOpenAICompatible)
    }

    func testLoadReadsLegacyEngineAndOpenAIKeychainValues() {
        defaults.set("openAI", forKey: "summarizerType")
        keychain.save("sk-legacy-123", forKey: "summarizerOpenAIKey", service: "tests")

        let loaded = SummarizerConfig.load(from: defaults, keychain: keychain, keychainService: "tests")

        XCTAssertEqual(loaded.defaultEngine, .llmAPI)
        XCTAssertEqual(loaded.activeLLMAPIProviderID, .openAI)
        XCTAssertEqual(loaded.apiToken, "sk-legacy-123")
    }

    func testLoadMigratesLegacyOpenAICompatibleURLToMatchingProvider() {
        defaults.set("openAI", forKey: "summarizerDefaultEngine")
        defaults.set("https://dashscope.aliyuncs.com/compatible-mode/v1", forKey: "summarizerAPIBaseURL")
        defaults.set("qwen-max", forKey: "summarizerAPIModel")
        keychain.save("sk-legacy-qwen", forKey: "summarizerAPIToken", service: "tests")

        let loaded = SummarizerConfig.load(from: defaults, keychain: keychain, keychainService: "tests")

        XCTAssertEqual(loaded.defaultEngine, .llmAPI)
        XCTAssertEqual(loaded.activeLLMAPIProviderID, .qwen)
        XCTAssertEqual(loaded.llmAPIProviderConfig(for: .qwen)?.baseURL, "https://dashscope.aliyuncs.com/compatible-mode/v1")
        XCTAssertEqual(loaded.llmAPIProviderConfig(for: .qwen)?.model, "qwen-max")
        XCTAssertEqual(loaded.llmAPIProviderConfig(for: .qwen)?.apiToken, "sk-legacy-qwen")
    }

    func testLoadMigratesUnknownLegacyURLToCustomProvider() {
        defaults.set("openAI", forKey: "summarizerDefaultEngine")
        defaults.set("https://llm.example.com/v1", forKey: "summarizerAPIBaseURL")
        defaults.set("custom-model", forKey: "summarizerAPIModel")
        keychain.save("sk-legacy-custom", forKey: "summarizerAPIToken", service: "tests")

        let loaded = SummarizerConfig.load(from: defaults, keychain: keychain, keychainService: "tests")

        XCTAssertEqual(loaded.activeLLMAPIProviderID, .customOpenAICompatible)
        XCTAssertEqual(loaded.llmAPIProviderConfig(for: .customOpenAICompatible)?.baseURL, "https://llm.example.com/v1")
        XCTAssertEqual(loaded.llmAPIProviderConfig(for: .customOpenAICompatible)?.model, "custom-model")
        XCTAssertEqual(loaded.llmAPIProviderConfig(for: .customOpenAICompatible)?.wireFormat, .openAIChat)
        XCTAssertEqual(loaded.llmAPIProviderConfig(for: .customOpenAICompatible)?.apiToken, "sk-legacy-custom")
    }

    func testMakeSummarizerReturnsNilForIncompleteOpenAICompatibleAPISettings() {
        var config = SummarizerConfig.load(from: defaults)
        config.defaultEngine = .llmAPI
        config.apiBaseURL = ""
        config.apiModel = ""
        config.apiToken = ""

        XCTAssertFalse(config.apiConfigurationIsComplete)
        XCTAssertNil(config.makeSummarizer())
    }

    func testKeychainStorageIsScopedByService() {
        var config = SummarizerConfig.load(from: defaults, keychain: keychain, keychainService: "tests-a")
        config.type = .llmAPI
        config.openAIKey = "sk-test-a"
        config.save(to: defaults, keychain: keychain, keychainService: "tests-a")

        XCTAssertEqual(
            SummarizerConfig.load(from: defaults, keychain: keychain, keychainService: "tests-a").openAIKey,
            "sk-test-a"
        )
        XCTAssertEqual(
            SummarizerConfig.load(from: defaults, keychain: keychain, keychainService: "tests-b").openAIKey,
            ""
        )
    }

    func testMakeSummarizerReturnsNilForNoneType() {
        var config = SummarizerConfig.load(from: defaults)
        config.type = .none
        XCTAssertNil(config.makeSummarizer())
    }

    func testMakeSummarizerReturnsNonNilForOpenAIWithKey() {
        var config = SummarizerConfig.load(from: defaults)
        config.type = .llmAPI
        config.openAIKey = "sk-test-xyz"
        XCTAssertNotNil(config.makeSummarizer())
    }

    func testMakeSummarizerReturnsNilForOpenAIWithEmptyKey() {
        var config = SummarizerConfig.load(from: defaults)
        config.type = .llmAPI
        config.openAIKey = ""
        XCTAssertNil(config.makeSummarizer())
    }

    func testMakeSummarizerReturnsCodexDirectSummarizerForCodexAuth() throws {
        var config = SummarizerConfig.load(from: defaults)
        config.type = .codexAuth

        XCTAssertNotNil(config.makeSummarizer() as? CodexDirectSummarizer)
    }

    func testCodexAuthSummarizerCanPowerMyWikiLLMBridge() throws {
        var config = SummarizerConfig.load(from: defaults)
        config.type = .codexAuth

        let summarizer = try XCTUnwrap(config.makeSummarizer())

        XCTAssertNotNil(summarizer as? any MyWikiLLMCompleting)
    }

    func testMakeSummarizerReturnsCLISummarizerForClaudeCLI() {
        // Use the test binary itself as a stand-in executable that is guaranteed to exist
        var config = SummarizerConfig.load(from: defaults)
        config.type = .claudeCLI
        config.claudeCLIPath = "/bin/sh"
        XCTAssertNotNil(config.makeSummarizer())
    }

    func testMakeSummarizerReturnsNilForCLIWithInvalidPath() {
        var config = SummarizerConfig.load(from: defaults)
        config.type = .claudeCLI
        config.claudeCLIPath = "/nonexistent/path/claude"
        let isolatedHomeURL = temporaryDirectoryURL.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: isolatedHomeURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: isolatedHomeURL) }
        XCTAssertNil(
            config.makeSummarizer(
                environment: [
                    "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
                    "HOME": isolatedHomeURL.path,
                ]
            )
        )
    }

    func testMakeSummarizerFallsBackToExecutableDiscoveredOnPATH() throws {
        let executableURL = temporaryDirectoryURL.appendingPathComponent("gemini")
        let script = "#!/bin/sh\nprintf '{}'\n"
        try script.write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)

        var config = SummarizerConfig.load(from: defaults)
        config.type = .geminiCLI
        config.geminiCLIPath = "/usr/local/bin/gemini"

        let summarizer = try XCTUnwrap(config.makeSummarizer(environment: ["PATH": temporaryDirectoryURL.path]) as? CLISummarizer)

        XCTAssertEqual(summarizer.executablePath, executableURL.path)
    }

    func testResolvedExecutablePathFallsBackToCommonInstallDirectories() throws {
        let executableURL = temporaryDirectoryURL.appendingPathComponent("codex")
        let script = "#!/bin/sh\nprintf '{}'\n"
        try script.write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)

        let resolvedPath = SummarizerConfig.resolvedExecutablePath(
            configuredPath: "/missing/codex",
            commandName: "codex",
            environment: ["PATH": ""],
            fallbackSearchDirectories: [temporaryDirectoryURL.path]
        )

        XCTAssertEqual(resolvedPath, executableURL.path)
    }

    func testMakeSummarizerFallsBackToNVMExecutableWhenPATHIsRestricted() throws {
        let homeURL = temporaryDirectoryURL.appendingPathComponent("home", isDirectory: true)
        let nvmBinURL = homeURL
            .appendingPathComponent(".nvm", isDirectory: true)
            .appendingPathComponent("versions", isDirectory: true)
            .appendingPathComponent("node", isDirectory: true)
            .appendingPathComponent("v99.0.0", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: nvmBinURL, withIntermediateDirectories: true)

        let executableURL = nvmBinURL.appendingPathComponent("codex")
        let script = "#!/bin/sh\nprintf '{}'\n"
        try script.write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)

        var config = SummarizerConfig.load(from: defaults)
        config.type = .codexCLI
        config.codexCLIPath = "/usr/local/bin/codex"

        let summarizer = try XCTUnwrap(
            config.makeSummarizer(
                environment: [
                    "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
                    "HOME": homeURL.path
                ]
            ) as? CLISummarizer
        )

        XCTAssertEqual(
            URL(fileURLWithPath: summarizer.executablePath).standardizedFileURL.path,
            executableURL.standardizedFileURL.path
        )
    }
}
