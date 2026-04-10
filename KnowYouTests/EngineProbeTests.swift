import Foundation
import XCTest
@testable import KnowYou

private final class StubProcessRunner: ProcessRunning, @unchecked Sendable {
    enum Behavior {
        case success(String)
        case failure(Error)
    }

    private let behavior: Behavior
    private(set) var invocations: [(executable: String, arguments: [String])] = []

    init(behavior: Behavior) {
        self.behavior = behavior
    }

    func run(executable: String, arguments: [String]) async throws -> String {
        invocations.append((executable, arguments))
        switch behavior {
        case .success(let output):
            return output
        case .failure(let error):
            throw error
        }
    }
}

private final class StubURLProtocol: URLProtocol {
    enum Behavior {
        case success(statusCode: Int, body: Data)
        case failure(Error)
    }

    nonisolated(unsafe) static var behavior: Behavior?
    nonisolated(unsafe) static var requestCount = 0
    nonisolated(unsafe) static var lastRequest: URLRequest?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.requestCount += 1
        Self.lastRequest = request

        guard let behavior = Self.behavior else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        switch behavior {
        case .success(let statusCode, let body):
            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://example.com")!,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        case .failure(let error):
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    static func reset() {
        behavior = nil
        requestCount = 0
        lastRequest = nil
    }
}

final class EngineProbeTests: XCTestCase {
    override func tearDown() {
        StubURLProtocol.reset()
        super.tearDown()
    }

    func testCLIProbeReturnsGrayWhenExecutableIsMissing() async {
        let runner = StubProcessRunner(behavior: .success("unused"))
        let probe = EngineProbe(session: StubURLProtocol.makeSession(), processRunner: runner)
        var config = SummarizerConfig.default
        config.defaultEngine = .claudeCLI
        config.claudeCLIPath = "/definitely/missing/claude"

        let result = await probe.probe(engine: .claudeCLI, config: config, environment: [:])

        XCTAssertEqual(result.state, .gray)
        XCTAssertEqual(runner.invocations.count, 0)
    }

    func testCLIProbeFallsBackToPATHWhenConfiguredPathIsInvalid() async throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let executableURL = temporaryDirectory.appendingPathComponent("codex")
        try "#!/bin/sh\nprintf '%s' '{\"sections\":[{\"id\":\"daily-journal\",\"paragraphs\":[{\"text\":\"A productive day.\",\"sourceEventIDs\":[\"A3F2C1D4-E5B6-7890-ABCD-EF1234567890\"]}]}]}'\n".write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)

        let runner = StubProcessRunner(behavior: .success(#"{"sections":[{"id":"daily-journal","paragraphs":[{"text":"A productive day.","sourceEventIDs":["A3F2C1D4-E5B6-7890-ABCD-EF1234567890"]}]}]}"#))
        let probe = EngineProbe(session: StubURLProtocol.makeSession(), processRunner: runner)
        var config = SummarizerConfig.default
        config.defaultEngine = .codexCLI
        config.codexCLIPath = "/definitely/not/on/path/codex"

        let result = await probe.probe(engine: .codexCLI, config: config, environment: ["PATH": temporaryDirectory.path])

        XCTAssertEqual(result.state, .green)
        XCTAssertEqual(runner.invocations.count, 1)
        XCTAssertEqual(runner.invocations.first?.executable, executableURL.path)
        XCTAssertEqual(
            runner.invocations.first?.arguments,
            ["Return a minimal valid JSON object that matches the daily story schema."]
        )
    }

    func testCLIProbeReturnsYellowWhenClaudeSmokeTestOutputIsMalformedEnvelope() async throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let executableURL = temporaryDirectory.appendingPathComponent("claude")
        try "#!/bin/sh\nprintf '%s' '{\"structured_output\":{\"foo\":\"bar\"}}'\n".write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)

        let runner = StubProcessRunner(behavior: .success(#"{"structured_output":{"foo":"bar"}}"#))
        let probe = EngineProbe(session: StubURLProtocol.makeSession(), processRunner: runner)
        var config = SummarizerConfig.default
        config.defaultEngine = .claudeCLI
        config.claudeCLIPath = executableURL.path

        let result = await probe.probe(engine: .claudeCLI, config: config, environment: [:])

        XCTAssertEqual(result.state, .yellow)
        XCTAssertEqual(runner.invocations.count, 1)
        XCTAssertEqual(runner.invocations.first?.executable, executableURL.path)
        XCTAssertEqual(
            runner.invocations.first?.arguments.prefix(2).map { $0 },
            ["-p", "Return a minimal valid JSON object that matches the daily story schema."]
        )
        XCTAssertTrue(runner.invocations.first?.arguments.contains("--output-format") ?? false)
        XCTAssertTrue(runner.invocations.first?.arguments.contains("--json-schema") ?? false)
    }

    func testCLIProbeReturnsGreenWhenClaudeSmokeTestOutputIsRawSchemaJSON() async throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let executableURL = temporaryDirectory.appendingPathComponent("claude")
        try "#!/bin/sh\nprintf '%s' '{\"sections\":[{\"id\":\"daily-journal\",\"paragraphs\":[{\"text\":\"A productive day.\",\"sourceEventIDs\":[\"A3F2C1D4-E5B6-7890-ABCD-EF1234567890\"]}]}]}'\n".write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)

        let runner = StubProcessRunner(behavior: .success(#"{"sections":[{"id":"daily-journal","paragraphs":[{"text":"A productive day.","sourceEventIDs":["A3F2C1D4-E5B6-7890-ABCD-EF1234567890"]}]}]}"#))
        let probe = EngineProbe(session: StubURLProtocol.makeSession(), processRunner: runner)
        var config = SummarizerConfig.default
        config.defaultEngine = .claudeCLI
        config.claudeCLIPath = executableURL.path

        let result = await probe.probe(engine: .claudeCLI, config: config, environment: [:])

        XCTAssertEqual(result.state, .green)
        XCTAssertEqual(runner.invocations.count, 1)
        XCTAssertEqual(
            runner.invocations.first?.arguments.prefix(2).map { $0 },
            ["-p", "Return a minimal valid JSON object that matches the daily story schema."]
        )
    }

    func testCLIProbeReturnsGreenWhenTextSmokeTestOutputIsRawStoryJSON() async throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let executableURL = temporaryDirectory.appendingPathComponent("openclaw")
        try "#!/bin/sh\nprintf '%s' '{\"sections\":[{\"id\":\"daily-journal\",\"paragraphs\":[{\"text\":\"A productive day.\",\"sourceEventIDs\":[\"A3F2C1D4-E5B6-7890-ABCD-EF1234567890\"]}]}]}'\n".write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)

        let runner = StubProcessRunner(behavior: .success(#"{"sections":[{"id":"daily-journal","paragraphs":[{"text":"A productive day.","sourceEventIDs":["A3F2C1D4-E5B6-7890-ABCD-EF1234567890"]}]}]}"#))
        let probe = EngineProbe(session: StubURLProtocol.makeSession(), processRunner: runner)
        var config = SummarizerConfig.default
        config.defaultEngine = .openclawCLI
        config.openclawCLIPath = executableURL.path

        let result = await probe.probe(engine: .openclawCLI, config: config, environment: [:])

        XCTAssertEqual(result.state, .green)
        XCTAssertEqual(runner.invocations.count, 1)
        XCTAssertEqual(
            runner.invocations.first?.arguments,
            ["Return a minimal valid JSON object that matches the daily story schema."]
        )
    }

    func testCLIProbeReturnsYellowWhenTextSmokeTestOutputIsUnrelated() async throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let executableURL = temporaryDirectory.appendingPathComponent("codex")
        try "#!/bin/sh\nprintf 'Welcome to Codex.'\n".write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)

        let runner = StubProcessRunner(behavior: .success("Welcome to Codex."))
        let probe = EngineProbe(session: StubURLProtocol.makeSession(), processRunner: runner)
        var config = SummarizerConfig.default
        config.defaultEngine = .codexCLI
        config.codexCLIPath = executableURL.path

        let result = await probe.probe(engine: .codexCLI, config: config, environment: [:])

        XCTAssertEqual(result.state, .yellow)
        XCTAssertEqual(runner.invocations.count, 1)
        XCTAssertEqual(
            runner.invocations.first?.arguments,
            ["Return a minimal valid JSON object that matches the daily story schema."]
        )
    }

    func testAPIProbeReturnsGrayWhenConfigurationIsIncomplete() async {
        let runner = StubProcessRunner(behavior: .success("unused"))
        let probe = EngineProbe(session: StubURLProtocol.makeSession(), processRunner: runner)
        var config = SummarizerConfig.default
        config.defaultEngine = .openAI
        config.apiBaseURL = ""
        config.apiModel = ""
        config.apiToken = ""

        let result = await probe.probe(engine: .openAI, config: config, environment: [:])

        XCTAssertEqual(result.state, .gray)
        XCTAssertEqual(StubURLProtocol.requestCount, 0)
    }

    func testAPIProbeReturnsYellowWhenHTTPRequestFails() async {
        StubURLProtocol.behavior = .failure(URLError(.timedOut))
        let probe = EngineProbe(session: StubURLProtocol.makeSession(), processRunner: StubProcessRunner(behavior: .success("unused")))
        var config = SummarizerConfig.default
        config.defaultEngine = .openAI
        config.apiBaseURL = "https://example.com/v1/responses"
        config.apiModel = "gpt-4.1-mini"
        config.apiToken = "token-test-123"

        let result = await probe.probe(engine: .openAI, config: config, environment: [:])

        XCTAssertEqual(result.state, .yellow)
        XCTAssertEqual(StubURLProtocol.requestCount, 1)
    }

    func testAPIProbeReturnsGreenWhenResponseContainsAcknowledgementText() async {
        StubURLProtocol.behavior = .success(statusCode: 200, body: Data(#"{"output_text":"Okay"}"#.utf8))
        let probe = EngineProbe(session: StubURLProtocol.makeSession(), processRunner: StubProcessRunner(behavior: .success("unused")))
        var config = SummarizerConfig.default
        config.defaultEngine = .openAI
        config.apiBaseURL = "https://example.com/v1/responses"
        config.apiModel = "gpt-4.1-mini"
        config.apiToken = "token-test-123"

        let result = await probe.probe(engine: .openAI, config: config, environment: [:])

        XCTAssertEqual(result.state, .green)
        XCTAssertEqual(StubURLProtocol.requestCount, 1)
    }

    func testAPIProbeReturnsYellowWhenResponseContainsUnrelatedText() async {
        StubURLProtocol.behavior = .success(statusCode: 200, body: Data(#"{"output_text":"I cannot help with that."}"#.utf8))
        let probe = EngineProbe(session: StubURLProtocol.makeSession(), processRunner: StubProcessRunner(behavior: .success("unused")))
        var config = SummarizerConfig.default
        config.defaultEngine = .openAI
        config.apiBaseURL = "https://example.com/v1/responses"
        config.apiModel = "gpt-4.1-mini"
        config.apiToken = "token-test-123"

        let result = await probe.probe(engine: .openAI, config: config, environment: [:])

        XCTAssertEqual(result.state, .yellow)
        XCTAssertEqual(StubURLProtocol.requestCount, 1)
    }
}
