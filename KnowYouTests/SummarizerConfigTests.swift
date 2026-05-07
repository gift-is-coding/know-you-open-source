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
        config.type = .openAI
        config.openAIKey = "sk-test-abc"
        config.save(to: defaults, keychain: keychain, keychainService: "tests")

        let loaded = SummarizerConfig.load(from: defaults, keychain: keychain, keychainService: "tests")
        XCTAssertEqual(loaded.type, .openAI)
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
        config.defaultEngine = .openAI
        config.apiBaseURL = "https://example.com/v1/responses"
        config.apiModel = "gpt-4.1-mini"
        config.apiToken = "token-test-123"
        config.save(to: defaults, keychain: keychain, keychainService: "tests")

        let loaded = SummarizerConfig.load(from: defaults, keychain: keychain, keychainService: "tests")
        XCTAssertEqual(loaded.defaultEngine, .openAI)
        XCTAssertEqual(loaded.apiBaseURL, "https://example.com/v1/responses")
        XCTAssertEqual(loaded.apiModel, "gpt-4.1-mini")
        XCTAssertEqual(loaded.apiToken, "token-test-123")
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
        config.defaultEngine = .openAI
        config.apiBaseURL = "not-a-url"
        config.apiModel = "gpt-4.1-mini"
        config.apiToken = "token-test-123"

        XCTAssertFalse(config.apiConfigurationIsComplete)
        XCTAssertNil(config.makeSummarizer())
    }

    func testMakeSummarizerPlumbsCustomAPIBaseURLAndModelIntoCloudSummarizer() throws {
        var config = SummarizerConfig.load(from: defaults)
        config.defaultEngine = .openAI
        config.apiBaseURL = "https://example.com/v1/responses"
        config.apiModel = "gpt-4.1-mini"
        config.apiToken = "token-test-123"

        let summarizer = try XCTUnwrap(config.makeSummarizer() as? CloudSummarizer)
        XCTAssertEqual(summarizer.apiURL, URL(string: "https://example.com/v1/responses"))
        XCTAssertEqual(summarizer.model, "gpt-4.1-mini")
    }

    func testLoadReadsLegacyEngineAndOpenAIKeychainValues() {
        defaults.set("openAI", forKey: "summarizerType")
        keychain.save("sk-legacy-123", forKey: "summarizerOpenAIKey", service: "tests")

        let loaded = SummarizerConfig.load(from: defaults, keychain: keychain, keychainService: "tests")

        XCTAssertEqual(loaded.defaultEngine, .openAI)
        XCTAssertEqual(loaded.apiToken, "sk-legacy-123")
    }

    func testMakeSummarizerReturnsNilForIncompleteOpenAICompatibleAPISettings() {
        var config = SummarizerConfig.load(from: defaults)
        config.defaultEngine = .openAI
        config.apiBaseURL = ""
        config.apiModel = ""
        config.apiToken = ""

        XCTAssertFalse(config.apiConfigurationIsComplete)
        XCTAssertNil(config.makeSummarizer())
    }

    func testKeychainStorageIsScopedByService() {
        var config = SummarizerConfig.load(from: defaults, keychain: keychain, keychainService: "tests-a")
        config.type = .openAI
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
        config.type = .openAI
        config.openAIKey = "sk-test-xyz"
        XCTAssertNotNil(config.makeSummarizer())
    }

    func testMakeSummarizerReturnsNilForOpenAIWithEmptyKey() {
        var config = SummarizerConfig.load(from: defaults)
        config.type = .openAI
        config.openAIKey = ""
        XCTAssertNil(config.makeSummarizer())
    }

    func testMakeSummarizerReturnsCodexDirectSummarizerForCodexAuth() throws {
        var config = SummarizerConfig.load(from: defaults)
        config.type = .codexAuth

        XCTAssertNotNil(config.makeSummarizer() as? CodexDirectSummarizer)
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
