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

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        keychain = InMemoryKeychainStore()
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: defaults.description)
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
        XCTAssertNil(config.makeSummarizer())
    }
}
