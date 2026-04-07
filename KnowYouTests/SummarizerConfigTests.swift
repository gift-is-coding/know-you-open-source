import XCTest
@testable import KnowYou

final class SummarizerConfigTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
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
        var config = SummarizerConfig.load(from: defaults)
        config.type = .openAI
        config.openAIKey = "sk-test-abc"
        config.save(to: defaults)

        let loaded = SummarizerConfig.load(from: defaults)
        XCTAssertEqual(loaded.type, .openAI)
        XCTAssertEqual(loaded.openAIKey, "sk-test-abc")
    }

    func testSaveAndLoadRoundTripsCLIPath() {
        var config = SummarizerConfig.load(from: defaults)
        config.type = .claudeCLI
        config.claudeCLIPath = "/opt/homebrew/bin/claude"
        config.save(to: defaults)

        let loaded = SummarizerConfig.load(from: defaults)
        XCTAssertEqual(loaded.type, .claudeCLI)
        XCTAssertEqual(loaded.claudeCLIPath, "/opt/homebrew/bin/claude")
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
        var config = SummarizerConfig.load(from: defaults)
        config.type = .claudeCLI
        config.claudeCLIPath = "/usr/local/bin/claude"
        XCTAssertNotNil(config.makeSummarizer())
    }
}
