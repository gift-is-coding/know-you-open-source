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
    func testClaudeCodePassesPromptWithStructuredOutputFlags() async throws {
        let stub = StubProcessRunner(output: """
        {"structured_output":{"sections":[{"id":"daily-journal","paragraphs":[{"text":"A productive day.","sourceEventIDs":["A3F2C1D4-E5B6-7890-ABCD-EF1234567890"]}]}]}}
        """)
        let summarizer = CLISummarizer(tool: .claude, executablePath: "/usr/local/bin/claude", runner: stub)
        let prompt = "Return strict JSON for the day journal."

        let result = try await summarizer.summarize(dayKey: "2026-04-07", markdown: prompt)

        let payload = try XCTUnwrap(result.data(using: .utf8))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: payload) as? [String: Any])
        let sections = try XCTUnwrap(object["sections"] as? [[String: Any]])
        let firstSection = try XCTUnwrap(sections.first)
        let paragraphs = try XCTUnwrap(firstSection["paragraphs"] as? [[String: Any]])
        let firstParagraph = try XCTUnwrap(paragraphs.first)
        XCTAssertEqual(firstSection["id"] as? String, "daily-journal")
        XCTAssertEqual(firstParagraph["text"] as? String, "A productive day.")
        XCTAssertEqual(firstParagraph["sourceEventIDs"] as? [String], ["A3F2C1D4-E5B6-7890-ABCD-EF1234567890"])
        XCTAssertEqual(stub.lastExecutable, "/usr/local/bin/claude")
        XCTAssertEqual(stub.lastArguments?.prefix(2).map { $0 }, ["-p", prompt])
        XCTAssertTrue(stub.lastArguments?.contains("--output-format") ?? false)
        XCTAssertTrue(stub.lastArguments?.contains("json") ?? false)
        XCTAssertTrue(stub.lastArguments?.contains("--json-schema") ?? false)
    }

    func testClaudeStructuredOutputEnvelopeFallsBackToRawOutputWhenFieldMissing() async throws {
        let raw = #"{"result":"plain text fallback"}"#
        let stub = StubProcessRunner(output: raw)
        let summarizer = CLISummarizer(tool: .claude, executablePath: "/usr/local/bin/claude", runner: stub)

        let result = try await summarizer.summarize(dayKey: "2026-04-07", markdown: "prompt")

        XCTAssertEqual(result, raw)
    }

    func testCodexPassesPromptAsFirstArgument() async throws {
        let stub = StubProcessRunner(output: "Focused on shipping.")
        let summarizer = CLISummarizer(tool: .codex, executablePath: "/usr/local/bin/codex", runner: stub)
        let prompt = "Return strict JSON for the day journal."

        let result = try await summarizer.summarize(dayKey: "2026-04-07", markdown: prompt)

        XCTAssertEqual(result, "Focused on shipping.")
        XCTAssertEqual(stub.lastArguments?.count, 1)
        XCTAssertEqual(stub.lastArguments?.first, prompt)
    }

    func testClaudeSmokeTestAcceptsStructuredOutputPayload() async throws {
        let stub = StubProcessRunner(output: """
        {"structured_output":{"sections":[{"id":"daily-journal","paragraphs":[{"text":"A productive day.","sourceEventIDs":["A3F2C1D4-E5B6-7890-ABCD-EF1234567890"]}]}]}}
        """)
        let summarizer = CLISummarizer(tool: .claude, executablePath: "/usr/local/bin/claude", runner: stub)

        let result = try await summarizer.smokeTest()

        let payload = try XCTUnwrap(result.data(using: .utf8))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: payload) as? [String: Any])
        let sections = try XCTUnwrap(object["sections"] as? [[String: Any]])
        let firstSection = try XCTUnwrap(sections.first)
        let paragraphs = try XCTUnwrap(firstSection["paragraphs"] as? [[String: Any]])
        let firstParagraph = try XCTUnwrap(paragraphs.first)
        XCTAssertEqual(firstSection["id"] as? String, "daily-journal")
        XCTAssertEqual(firstParagraph["text"] as? String, "A productive day.")
        XCTAssertEqual(firstParagraph["sourceEventIDs"] as? [String], ["A3F2C1D4-E5B6-7890-ABCD-EF1234567890"])
        XCTAssertEqual(
            stub.lastArguments?.prefix(2).map { $0 },
            ["-p", "Return a minimal valid JSON object that matches the daily story schema."]
        )
        XCTAssertTrue(stub.lastArguments?.contains("--output-format") ?? false)
        XCTAssertTrue(stub.lastArguments?.contains("--json-schema") ?? false)
    }

    func testClaudeSmokeTestAcceptsRawSchemaJSON() async throws {
        let raw = #"{"sections":[{"id":"daily-journal","paragraphs":[{"text":"A productive day.","sourceEventIDs":["A3F2C1D4-E5B6-7890-ABCD-EF1234567890"]}]}]}"#
        let stub = StubProcessRunner(output: raw)
        let summarizer = CLISummarizer(tool: .claude, executablePath: "/usr/local/bin/claude", runner: stub)

        let result = try await summarizer.smokeTest()

        let payload = try XCTUnwrap(result.data(using: .utf8))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: payload) as? [String: Any])
        let sections = try XCTUnwrap(object["sections"] as? [[String: Any]])
        let firstSection = try XCTUnwrap(sections.first)
        let paragraphs = try XCTUnwrap(firstSection["paragraphs"] as? [[String: Any]])
        let firstParagraph = try XCTUnwrap(paragraphs.first)
        XCTAssertEqual(firstSection["id"] as? String, "daily-journal")
        XCTAssertEqual(firstParagraph["text"] as? String, "A productive day.")
        XCTAssertEqual(firstParagraph["sourceEventIDs"] as? [String], ["A3F2C1D4-E5B6-7890-ABCD-EF1234567890"])
    }

    func testClaudeSmokeTestRejectsMalformedStructuredOutputEnvelope() async throws {
        let stub = StubProcessRunner(output: #"{"structured_output":{"foo":"bar"}}"#)
        let summarizer = CLISummarizer(tool: .claude, executablePath: "/usr/local/bin/claude", runner: stub)

        await XCTAssertThrowsErrorAsync(
            try await summarizer.smokeTest()
        )
    }

    func testTextSmokeTestAcceptsRawValidStoryJSON() async throws {
        let raw = #"{"sections":[{"id":"daily-journal","paragraphs":[{"text":"A productive day.","sourceEventIDs":["A3F2C1D4-E5B6-7890-ABCD-EF1234567890"]}]}]}"#

        for tool in [CLISummarizer.Tool.codex, .gemini, .openclaw] {
            let stub = StubProcessRunner(output: raw)
            let summarizer = CLISummarizer(tool: tool, executablePath: "/usr/local/bin/\(tool.rawValue)", runner: stub)

            let result = try await summarizer.smokeTest()

            let payload = try XCTUnwrap(result.data(using: .utf8))
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: payload) as? [String: Any])
            let sections = try XCTUnwrap(object["sections"] as? [[String: Any]])
            let firstSection = try XCTUnwrap(sections.first)
            let paragraphs = try XCTUnwrap(firstSection["paragraphs"] as? [[String: Any]])
            let firstParagraph = try XCTUnwrap(paragraphs.first)
            XCTAssertEqual(firstSection["id"] as? String, "daily-journal")
            XCTAssertEqual(firstParagraph["text"] as? String, "A productive day.")
            XCTAssertEqual(firstParagraph["sourceEventIDs"] as? [String], ["A3F2C1D4-E5B6-7890-ABCD-EF1234567890"])
            switch tool {
            case .gemini:
                XCTAssertEqual(stub.lastArguments?.prefix(2).map { $0 }, ["-p", "Return a minimal valid JSON object that matches the daily story schema."])
                XCTAssertEqual(stub.lastArguments?.suffix(2).map { $0 }, ["--output-format", "text"])
            case .codex, .openclaw:
                XCTAssertEqual(stub.lastArguments, ["Return a minimal valid JSON object that matches the daily story schema."])
            case .claude:
                XCTFail("Claude is covered by dedicated smoke-test cases")
            }
        }
    }

    func testTextSmokeTestAcceptsFencedStoryJSON() async throws {
        let fenced = """
        ```json
        {"sections":[{"id":"daily-journal","paragraphs":[{"text":"A productive day.","sourceEventIDs":["A3F2C1D4-E5B6-7890-ABCD-EF1234567890"]}]}]}
        ```
        """
        let stub = StubProcessRunner(output: fenced)
        let summarizer = CLISummarizer(tool: .codex, executablePath: "/usr/local/bin/codex", runner: stub)

        let result = try await summarizer.smokeTest()

        let payload = try XCTUnwrap(result.data(using: .utf8))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: payload) as? [String: Any])
        let sections = try XCTUnwrap(object["sections"] as? [[String: Any]])
        let firstSection = try XCTUnwrap(sections.first)
        XCTAssertEqual(firstSection["id"] as? String, "daily-journal")
        XCTAssertEqual(stub.lastArguments, ["Return a minimal valid JSON object that matches the daily story schema."])
    }

    func testOpenclawPassesPromptAsFirstArgument() async throws {
        let raw = #"{"sections":[{"id":"daily-journal","paragraphs":[{"text":"A productive day.","sourceEventIDs":["A3F2C1D4-E5B6-7890-ABCD-EF1234567890"]}]}]}"#
        let stub = StubProcessRunner(output: raw)
        let summarizer = CLISummarizer(tool: .openclaw, executablePath: "/usr/local/bin/openclaw", runner: stub)
        let prompt = "Return a minimal valid JSON object that matches the daily story schema."

        let result = try await summarizer.smokeTest(prompt: prompt)

        let payload = try XCTUnwrap(result.data(using: .utf8))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: payload) as? [String: Any])
        let sections = try XCTUnwrap(object["sections"] as? [[String: Any]])
        let firstSection = try XCTUnwrap(sections.first)
        XCTAssertEqual(firstSection["id"] as? String, "daily-journal")
        XCTAssertEqual(stub.lastArguments, [prompt])
    }

    func testCodexSmokeTestRejectsUnrelatedNonEmptyOutput() async throws {
        let stub = StubProcessRunner(output: "Welcome to Codex.")
        let summarizer = CLISummarizer(tool: .codex, executablePath: "/usr/local/bin/codex", runner: stub)

        await XCTAssertThrowsErrorAsync(
            try await summarizer.smokeTest(prompt: "Return a minimal valid JSON object that matches the daily story schema.")
        )
    }

    func testClaudeSmokeTestRejectsMalformedStructuredOutput() async throws {
        let stub = StubProcessRunner(output: #"{"result":"plain text fallback"}"#)
        let summarizer = CLISummarizer(tool: .claude, executablePath: "/usr/local/bin/claude", runner: stub)

        await XCTAssertThrowsErrorAsync(
            try await summarizer.smokeTest(prompt: "Return a minimal valid JSON object that matches the daily story schema.")
        )
        XCTAssertEqual(stub.lastArguments?.prefix(2).map { $0 }, ["-p", "Return a minimal valid JSON object that matches the daily story schema."])
    }

    func testGeminiPassesPromptWithTextOutputFlag() async throws {
        let stub = StubProcessRunner(output: "Day summary.")
        let summarizer = CLISummarizer(tool: .gemini, executablePath: "/usr/local/bin/gemini", runner: stub)
        let prompt = "Return strict JSON for the day journal."

        _ = try await summarizer.summarize(dayKey: "2026-04-07", markdown: prompt)

        XCTAssertEqual(stub.lastArguments?.prefix(2).map { $0 }, ["-p", prompt])
        XCTAssertEqual(stub.lastArguments?.suffix(2).map { $0 }, ["--output-format", "text"])
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

    func testSystemProcessRunnerThrowsOnNonZeroExit() async {
        let runner = SystemProcessRunner()

        await XCTAssertThrowsErrorAsync(
            try await runner.run(
                executable: "/bin/sh",
                arguments: ["-c", "echo auth failed 1>&2; exit 7"]
            )
        )
    }

    func testSystemProcessRunnerPrependsExecutableDirectoryToPATH() {
        let runner = SystemProcessRunner(environment: ["PATH": "/usr/bin"])

        let environment = runner.processEnvironment(for: "/Users/wutianfu/.nvm/versions/node/v22.22.0/bin/claude")

        XCTAssertEqual(
            environment["PATH"],
            "/Users/wutianfu/.nvm/versions/node/v22.22.0/bin:/usr/bin"
        )
    }
}

private func XCTAssertThrowsErrorAsync(
    _ expression: @autoclosure () async throws -> String,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected error to be thrown", file: file, line: line)
    } catch {
    }
}
