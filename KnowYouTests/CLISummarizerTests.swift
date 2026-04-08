import XCTest
@testable import KnowYou

private final class StubProcessRunner: ProcessRunning, @unchecked Sendable {
    let output: String
    private(set) var lastExecutable: String?
    private(set) var lastArguments: [String]?

    init(output: String) { self.output = output }

    func run(executable: String, arguments: [String]) async throws -> String {
        lastExecutable = executable
        lastArguments = arguments
        return output
    }
}

final class CLISummarizerTests: XCTestCase {
    func testClaudeCodePassesPromptWithDashPFlag() async throws {
        let stub = StubProcessRunner(output: "A productive day.")
        let summarizer = CLISummarizer(tool: .claude, executablePath: "/usr/local/bin/claude", runner: stub)

        let result = try await summarizer.summarize(dayKey: "2026-04-07", markdown: "## Clipboard\n- note")

        XCTAssertEqual(result, "A productive day.")
        XCTAssertEqual(stub.lastExecutable, "/usr/local/bin/claude")
        XCTAssertEqual(stub.lastArguments?.first, "-p")
        XCTAssertTrue(stub.lastArguments?.last?.contains("2026-04-07") == true)
    }

    func testCodexPassesPromptAsFirstArgument() async throws {
        let stub = StubProcessRunner(output: "Focused on shipping.")
        let summarizer = CLISummarizer(tool: .codex, executablePath: "/usr/local/bin/codex", runner: stub)

        let result = try await summarizer.summarize(dayKey: "2026-04-07", markdown: "## Clipboard\n- note")

        XCTAssertEqual(result, "Focused on shipping.")
        XCTAssertEqual(stub.lastArguments?.count, 1)
        XCTAssertTrue(stub.lastArguments?.first?.contains("2026-04-07") == true)
    }

    func testGeminiPassesPromptWithDashPFlag() async throws {
        let stub = StubProcessRunner(output: "Day summary.")
        let summarizer = CLISummarizer(tool: .gemini, executablePath: "/usr/local/bin/gemini", runner: stub)

        _ = try await summarizer.summarize(dayKey: "2026-04-07", markdown: "## Clipboard\n- note")

        XCTAssertEqual(stub.lastArguments?.first, "-p")
    }

    func testEmptyOutputReturnsUnavailableMessage() async throws {
        let stub = StubProcessRunner(output: "   ")
        let summarizer = CLISummarizer(tool: .claude, executablePath: "/usr/local/bin/claude", runner: stub)

        let result = try await summarizer.summarize(dayKey: "2026-04-07", markdown: "")

        XCTAssertEqual(result, "Summary unavailable.")
    }

    func testContinuationGateOnlyResumesOnce() {
        let gate = ContinuationGate<String>()

        XCTAssertTrue(gate.resume(returning: "first"))
        XCTAssertFalse(gate.resume(returning: "second"))
    }
}
