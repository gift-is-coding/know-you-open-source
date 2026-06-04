import XCTest
@testable import KnowYou

private final class StubProcessRunner: ProcessRunning, @unchecked Sendable {
    enum Behavior {
        case success(ProcessExecutionResult)
        case failure(Error)
    }

    private let behaviors: [Behavior]
    private let onInvocation: ((String, [String], Int, Int) -> Void)?
    private var nextIndex = 0
    private(set) var invocations: [(executable: String, arguments: [String], timeoutSeconds: Int)] = []

    init(
        behaviors: [Behavior],
        onInvocation: ((String, [String], Int, Int) -> Void)? = nil
    ) {
        self.behaviors = behaviors
        self.onInvocation = onInvocation
    }

    convenience init(output: String) {
        self.init(
            behaviors: [
                .success(
                    ProcessExecutionResult(
                        stdout: output,
                        stderr: "",
                        terminationStatus: 0,
                        duration: 0
                    )
                )
            ]
        )
    }

    func run(executable: String, arguments: [String], timeoutSeconds: Int) async throws -> ProcessExecutionResult {
        let invocationIndex = nextIndex
        nextIndex += 1
        invocations.append((executable, arguments, timeoutSeconds))
        onInvocation?(executable, arguments, invocationIndex, timeoutSeconds)

        switch behaviors[min(invocationIndex, behaviors.count - 1)] {
        case .success(let result):
            return result
        case .failure(let error):
            throw error
        }
    }
}

final class CLISummarizerTests: XCTestCase {
    private func decodedJSONObject(from text: String) throws -> [String: Any] {
        let payload = try XCTUnwrap(text.data(using: .utf8))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: payload) as? [String: Any])
    }

    private func assertIncrementalSchema(
        _ contents: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(contents.contains("encouragementToReplace"), file: file, line: line)
        XCTAssertTrue(contents.contains("summaryBulletsToReplace"), file: file, line: line)
        XCTAssertTrue(contents.contains("detailBlocksToAppend"), file: file, line: line)
        XCTAssertTrue(contents.contains("todoItemsToReplace"), file: file, line: line)
    }

    private func schemaPath(from arguments: [String]) throws -> String {
        let schemaIndex = try XCTUnwrap(arguments.firstIndex(of: "--output-schema"))
        return try XCTUnwrap(arguments.indices.contains(schemaIndex + 1) ? arguments[schemaIndex + 1] : nil)
    }

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
        XCTAssertEqual(stub.invocations.first?.executable, "/usr/local/bin/claude")
        XCTAssertEqual(stub.invocations.first?.arguments.prefix(2).map { $0 }, ["-p", prompt])
        XCTAssertTrue(stub.invocations.first?.arguments.contains("--output-format") ?? false)
        XCTAssertTrue(stub.invocations.first?.arguments.contains("json") ?? false)
        XCTAssertTrue(stub.invocations.first?.arguments.contains("--json-schema") ?? false)
    }

    func testClaudeStructuredOutputEnvelopeTriggersRepairWhenFieldMissing() async {
        let raw = #"{"result":"plain text fallback"}"#
        let stub = StubProcessRunner(output: raw)
        let summarizer = CLISummarizer(tool: .claude, executablePath: "/usr/local/bin/claude", runner: stub)

        await XCTAssertThrowsErrorAsync(
            try await summarizer.summarize(dayKey: "2026-04-07", markdown: "prompt")
        )
    }

    func testCodexPassesPromptViaExecSubcommandAndReadsSchemaOutputFile() async throws {
        let outputURL = URL.temporaryDirectory.appending(path: UUID().uuidString)
        let schemaURL = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer {
            try? FileManager.default.removeItem(at: outputURL)
            try? FileManager.default.removeItem(at: schemaURL)
        }

        let json = #"{"sections":[{"id":"daily-journal","paragraphs":[{"text":"Focused on shipping.","sourceEventIDs":["A3F2C1D4-E5B6-7890-ABCD-EF1234567890"]}]}]}"#
        let stub = StubProcessRunner(
            behaviors: [
                .success(
                    ProcessExecutionResult(
                        stdout: "codex\n{\"ok\":\"ignored\"}",
                        stderr: "",
                        terminationStatus: 0,
                        duration: 0
                    )
                )
            ],
            onInvocation: { _, arguments, _, _ in
                if let outputIndex = arguments.firstIndex(of: "-o"), arguments.indices.contains(outputIndex + 1) {
                    let outputPath = arguments[outputIndex + 1]
                    try? json.write(toFile: outputPath, atomically: true, encoding: .utf8)
                }
            }
        )
        let summarizer = CLISummarizer(tool: .codex, executablePath: "/usr/local/bin/codex", runner: stub)
        let prompt = "Return strict JSON for the day journal."

        let result = try await summarizer.summarize(dayKey: "2026-04-07", markdown: prompt)

        let object = try decodedJSONObject(from: result)
        let sections = try XCTUnwrap(object["sections"] as? [[String: Any]])
        let firstSection = try XCTUnwrap(sections.first)
        let paragraphs = try XCTUnwrap(firstSection["paragraphs"] as? [[String: Any]])
        let firstParagraph = try XCTUnwrap(paragraphs.first)
        XCTAssertEqual(firstSection["id"] as? String, "daily-journal")
        XCTAssertEqual(firstParagraph["text"] as? String, "Focused on shipping.")
        XCTAssertEqual(firstParagraph["sourceEventIDs"] as? [String], ["A3F2C1D4-E5B6-7890-ABCD-EF1234567890"])
        let arguments = try XCTUnwrap(stub.invocations.first?.arguments)
        XCTAssertEqual(arguments.prefix(3).map { $0 }, ["exec", "--skip-git-repo-check", "--ephemeral"])
        XCTAssertFalse(arguments.contains("-m"))
        XCTAssertTrue(arguments.contains("--output-schema"))
        XCTAssertTrue(arguments.contains("-o"))
        XCTAssertEqual(arguments.last, prompt)
    }

    func testCodexMyWikiCompletionReturnsRawOutputWithoutSchemaOrRepair() async throws {
        let raw = """
        # Project Ontology

        - Relationship: Alice mentors Bob.
        - Follow-up: Ask Bob for source notes.
        """
        let stub = StubProcessRunner(
            behaviors: [
                .success(ProcessExecutionResult(stdout: "codex completed", stderr: "", terminationStatus: 0, duration: 0))
            ],
            onInvocation: { _, arguments, _, _ in
                if let outputIndex = arguments.firstIndex(of: "-o"), arguments.indices.contains(outputIndex + 1) {
                    try? raw.write(toFile: arguments[outputIndex + 1], atomically: true, encoding: .utf8)
                }
            }
        )
        let summarizer = CLISummarizer(tool: .codex, executablePath: "/usr/local/bin/codex", runner: stub)
        let messages = [
            MyWikiLLMMessage(role: "system", content: "Extract My Wiki ontology."),
            MyWikiLLMMessage(role: "user", content: "Alice helped Bob prepare the release notes.")
        ]

        let result = try await summarizer.complete(messages: messages, temperature: 0.2)

        XCTAssertEqual(result, raw)
        XCTAssertEqual(stub.invocations.count, 1)
        let arguments = try XCTUnwrap(stub.invocations.first?.arguments)
        XCTAssertFalse(arguments.contains("--output-schema"))
        XCTAssertTrue(arguments.contains("-o"))
        XCTAssertEqual(arguments.last, messages.myWikiFullTranscript)
    }

    func testCodexSummarizeIgnoresStderrNoiseWhenOutputFileContainsValidJSON() async throws {
        let json = #"{"sections":[{"id":"daily-journal","paragraphs":[{"text":"Focused on shipping.","sourceEventIDs":["A3F2C1D4-E5B6-7890-ABCD-EF1234567890"]}]}]}"#
        let stub = StubProcessRunner(
            behaviors: [
                .success(
                    ProcessExecutionResult(
                        stdout: "Reading additional input from stdin...",
                        stderr: "ERROR rmcp::transport::worker: invalid token",
                        terminationStatus: 0,
                        duration: 0
                    )
                )
            ],
            onInvocation: { _, arguments, _, _ in
                if let outputIndex = arguments.firstIndex(of: "-o"), arguments.indices.contains(outputIndex + 1) {
                    try? json.write(toFile: arguments[outputIndex + 1], atomically: true, encoding: .utf8)
                }
            }
        )
        let summarizer = CLISummarizer(tool: .codex, executablePath: "/usr/local/bin/codex", runner: stub)

        let result = try await summarizer.summarize(dayKey: "2026-04-07", markdown: "prompt")

        let object = try decodedJSONObject(from: result)
        let sections = try XCTUnwrap(object["sections"] as? [[String: Any]])
        let firstSection = try XCTUnwrap(sections.first)
        XCTAssertEqual(firstSection["id"] as? String, "daily-journal")
    }

    func testCodexNonZeroExitSuggestsCheckingCLIAndConfig() async {
        let stub = StubProcessRunner(
            behaviors: [
                .success(
                    ProcessExecutionResult(
                        stdout: "",
                        stderr: "error: unknown model gpt-5.5",
                        terminationStatus: 1,
                        duration: 0
                    )
                )
            ]
        )
        let summarizer = CLISummarizer(tool: .codex, executablePath: "/usr/local/bin/codex", runner: stub)

        await XCTAssertThrowsErrorAsync(
            try await summarizer.summarize(dayKey: "2026-04-07", markdown: "prompt")
        ) { error in
            let message = error.localizedDescription
            XCTAssertTrue(message.contains("unknown model gpt-5.5"), message)
            XCTAssertTrue(message.contains("upgrading Codex CLI"), message)
            XCTAssertTrue(message.contains("~/.codex/config.toml"), message)
        }
    }

    func testCodexSummarizeRepairsInvalidPrimaryOutput() async throws {
        let repaired = #"{"sections":[{"id":"daily-journal","paragraphs":[{"text":"Recovered story.","sourceEventIDs":["A3F2C1D4-E5B6-7890-ABCD-EF1234567890"]}]}]}"#
        let stub = StubProcessRunner(
            behaviors: [
                .success(ProcessExecutionResult(stdout: "", stderr: "", terminationStatus: 0, duration: 0)),
                .success(ProcessExecutionResult(stdout: "", stderr: "", terminationStatus: 0, duration: 0)),
            ],
            onInvocation: { _, arguments, invocationIndex, _ in
                guard let outputIndex = arguments.firstIndex(of: "-o"), arguments.indices.contains(outputIndex + 1) else {
                    return
                }
                let outputPath = arguments[outputIndex + 1]
                let contents = invocationIndex == 0 ? "Not JSON" : repaired
                try? contents.write(toFile: outputPath, atomically: true, encoding: .utf8)
            }
        )
        let summarizer = CLISummarizer(tool: .codex, executablePath: "/usr/local/bin/codex", runner: stub)

        let result = try await summarizer.summarize(dayKey: "2026-04-07", markdown: "prompt")

        let object = try decodedJSONObject(from: result)
        let sections = try XCTUnwrap(object["sections"] as? [[String: Any]])
        let firstSection = try XCTUnwrap(sections.first)
        let paragraphs = try XCTUnwrap(firstSection["paragraphs"] as? [[String: Any]])
        let firstParagraph = try XCTUnwrap(paragraphs.first)
        XCTAssertEqual(firstParagraph["text"] as? String, "Recovered story.")
        XCTAssertEqual(stub.invocations.count, 2)
    }

    func testCodexIncrementalRefreshReadsIncrementalSchemaOutputFile() async throws {
        let incremental = """
        {
          "encouragementToReplace": {
            "text": "Closed the day with steady follow-through.",
            "sourceEventIDs": ["A3F2C1D4-E5B6-7890-ABCD-EF1234567890"]
          },
          "summaryBulletsToReplace": [
            {
              "text": "Closed the follow-up loop",
              "sourceEventIDs": ["A3F2C1D4-E5B6-7890-ABCD-EF1234567890"]
            }
          ],
          "detailBlocksToAppend": [
            {
              "text": "## Follow-up\\n\\nHandled the customer response.",
              "sourceEventIDs": ["A3F2C1D4-E5B6-7890-ABCD-EF1234567890"]
            }
          ],
          "todoItemsToReplace": [
            {
              "text": "Send the handoff",
              "sourceEventIDs": ["A3F2C1D4-E5B6-7890-ABCD-EF1234567890"]
            }
          ]
        }
        """
        let stub = StubProcessRunner(
            behaviors: [
                .success(ProcessExecutionResult(stdout: "", stderr: "", terminationStatus: 0, duration: 0))
            ],
            onInvocation: { _, arguments, _, _ in
                XCTAssertTrue(arguments.contains("--output-schema"))
                guard
                    let outputIndex = arguments.firstIndex(of: "-o"),
                    arguments.indices.contains(outputIndex + 1),
                    let schemaPath = try? self.schemaPath(from: arguments),
                    let schemaContents = try? String(contentsOfFile: schemaPath, encoding: .utf8)
                else {
                    return
                }
                self.assertIncrementalSchema(schemaContents)
                try? incremental.write(toFile: arguments[outputIndex + 1], atomically: true, encoding: .utf8)
            }
        )
        let summarizer = CLISummarizer(tool: .codex, executablePath: "/usr/local/bin/codex", runner: stub)

        let result = try await summarizer.summarizeIncremental(
            dayKey: "2026-04-14",
            markdown: "Return the incremental refresh payload.",
            context: .defaultBehavior
        )

        let object = try decodedJSONObject(from: result)
        XCTAssertNotNil(object["encouragementToReplace"])
        XCTAssertNotNil(object["summaryBulletsToReplace"])
        XCTAssertNotNil(object["detailBlocksToAppend"])
        XCTAssertNotNil(object["todoItemsToReplace"])
    }

    func testCodexIncrementalRefreshRepairsInvalidPrimaryOutputUsingIncrementalSchema() async throws {
        let repaired = """
        {
          "encouragementToReplace": {
            "text": "Recovered encouragement.",
            "sourceEventIDs": ["A3F2C1D4-E5B6-7890-ABCD-EF1234567890"]
          },
          "summaryBulletsToReplace": [],
          "detailBlocksToAppend": [],
          "todoItemsToReplace": []
        }
        """
        let stub = StubProcessRunner(
            behaviors: [
                .success(ProcessExecutionResult(stdout: "", stderr: "", terminationStatus: 0, duration: 0)),
                .success(ProcessExecutionResult(stdout: "", stderr: "", terminationStatus: 0, duration: 0)),
            ],
            onInvocation: { _, arguments, invocationIndex, _ in
                XCTAssertTrue(arguments.contains("--output-schema"))
                guard
                    let outputIndex = arguments.firstIndex(of: "-o"),
                    arguments.indices.contains(outputIndex + 1),
                    let schemaPath = try? self.schemaPath(from: arguments),
                    let schemaContents = try? String(contentsOfFile: schemaPath, encoding: .utf8)
                else {
                    return
                }
                self.assertIncrementalSchema(schemaContents)
                let outputPath = arguments[outputIndex + 1]
                let contents = invocationIndex == 0 ? "not json" : repaired
                try? contents.write(toFile: outputPath, atomically: true, encoding: .utf8)
            }
        )
        let summarizer = CLISummarizer(tool: .codex, executablePath: "/usr/local/bin/codex", runner: stub)

        let result = try await summarizer.summarizeIncremental(
            dayKey: "2026-04-14",
            markdown: "Repair the incremental refresh payload.",
            context: .defaultBehavior
        )

        let object = try decodedJSONObject(from: result)
        XCTAssertNotNil(object["encouragementToReplace"])
        XCTAssertEqual(stub.invocations.count, 2)
    }

    func testCodexIncrementalRefreshRejectsOutputMissingARequiredField() async {
        let invalid = """
        {
          "summaryBulletsToReplace": [
            {
              "text": "Keep the review loop moving",
              "sourceEventIDs": ["A3F2C1D4-E5B6-7890-ABCD-EF1234567890"]
            }
          ],
          "detailBlocksToAppend": [
            {
              "text": "## Follow-up\\n\\nTracked the customer response.",
              "sourceEventIDs": ["A3F2C1D4-E5B6-7890-ABCD-EF1234567890"]
            }
          ],
          "todoItemsToReplace": [
            {
              "text": "Send the handoff",
              "sourceEventIDs": ["A3F2C1D4-E5B6-7890-ABCD-EF1234567890"]
            }
          ]
        }
        """
        let stub = StubProcessRunner(
            behaviors: [
                .success(ProcessExecutionResult(stdout: "", stderr: "", terminationStatus: 0, duration: 0))
            ],
            onInvocation: { _, arguments, _, _ in
                XCTAssertTrue(arguments.contains("--output-schema"))
                guard
                    let outputIndex = arguments.firstIndex(of: "-o"),
                    arguments.indices.contains(outputIndex + 1),
                    let schemaPath = try? self.schemaPath(from: arguments),
                    let schemaContents = try? String(contentsOfFile: schemaPath, encoding: .utf8)
                else {
                    return
                }
                self.assertIncrementalSchema(schemaContents)
                XCTAssertTrue(schemaContents.contains(#""required":["encouragementToReplace""#))
                try? invalid.write(toFile: arguments[outputIndex + 1], atomically: true, encoding: .utf8)
            }
        )
        let summarizer = CLISummarizer(tool: .codex, executablePath: "/usr/local/bin/codex", runner: stub)

        await XCTAssertThrowsErrorAsync(
            try await summarizer.summarizeIncremental(
                dayKey: "2026-04-14",
                markdown: "Reject the invalid incremental payload.",
                context: .defaultBehavior
            )
        )
    }

    func testCodexManualRefreshUsesLongerPrimaryAndRepairTimeouts() async throws {
        let repaired = #"{"sections":[{"id":"daily-journal","paragraphs":[{"text":"Recovered story.","sourceEventIDs":["A3F2C1D4-E5B6-7890-ABCD-EF1234567890"]}]}]}"#
        let stub = StubProcessRunner(
            behaviors: [
                .success(ProcessExecutionResult(stdout: "", stderr: "", terminationStatus: 0, duration: 0)),
                .success(ProcessExecutionResult(stdout: "", stderr: "", terminationStatus: 0, duration: 0)),
            ],
            onInvocation: { _, arguments, invocationIndex, _ in
                guard let outputIndex = arguments.firstIndex(of: "-o"), arguments.indices.contains(outputIndex + 1) else {
                    return
                }
                let outputPath = arguments[outputIndex + 1]
                let contents = invocationIndex == 0 ? "Not JSON" : repaired
                try? contents.write(toFile: outputPath, atomically: true, encoding: .utf8)
            }
        )
        let summarizer = CLISummarizer(tool: .codex, executablePath: "/usr/local/bin/codex", runner: stub)

        _ = try await summarizer.summarize(
            dayKey: "2026-04-07",
            markdown: "prompt",
            context: .manualRefresh
        )

        XCTAssertEqual(stub.invocations.map(\.timeoutSeconds), [600, 120])
    }

    func testCodexAutomationRefreshUsesShorterPrimaryAndRepairTimeouts() async throws {
        let repaired = #"{"sections":[{"id":"daily-journal","paragraphs":[{"text":"Recovered story.","sourceEventIDs":["A3F2C1D4-E5B6-7890-ABCD-EF1234567890"]}]}]}"#
        let stub = StubProcessRunner(
            behaviors: [
                .success(ProcessExecutionResult(stdout: "", stderr: "", terminationStatus: 0, duration: 0)),
                .success(ProcessExecutionResult(stdout: "", stderr: "", terminationStatus: 0, duration: 0)),
            ],
            onInvocation: { _, arguments, invocationIndex, _ in
                guard let outputIndex = arguments.firstIndex(of: "-o"), arguments.indices.contains(outputIndex + 1) else {
                    return
                }
                let outputPath = arguments[outputIndex + 1]
                let contents = invocationIndex == 0 ? "Not JSON" : repaired
                try? contents.write(toFile: outputPath, atomically: true, encoding: .utf8)
            }
        )
        let summarizer = CLISummarizer(tool: .codex, executablePath: "/usr/local/bin/codex", runner: stub)

        _ = try await summarizer.summarize(
            dayKey: "2026-04-07",
            markdown: "prompt",
            context: .automationRefresh
        )

        XCTAssertEqual(stub.invocations.map(\.timeoutSeconds), [300, 60])
    }

    func testCodexSummarizeThrowsRepairFailedWhenRepairStillInvalid() async {
        let stub = StubProcessRunner(
            behaviors: [
                .success(ProcessExecutionResult(stdout: "", stderr: "", terminationStatus: 0, duration: 0)),
                .success(ProcessExecutionResult(stdout: "", stderr: "", terminationStatus: 0, duration: 0)),
            ],
            onInvocation: { _, arguments, invocationIndex, _ in
                guard let outputIndex = arguments.firstIndex(of: "-o"), arguments.indices.contains(outputIndex + 1) else {
                    return
                }
                try? "still invalid".write(toFile: arguments[outputIndex + 1], atomically: true, encoding: .utf8)
            }
        )
        let summarizer = CLISummarizer(tool: .codex, executablePath: "/usr/local/bin/codex", runner: stub)

        await XCTAssertThrowsErrorAsync(
            try await summarizer.summarize(dayKey: "2026-04-07", markdown: "prompt")
        )
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
            stub.invocations.first?.arguments.prefix(2).map { $0 },
            ["-p", "Return a minimal valid JSON object that matches the daily story schema."]
        )
        XCTAssertTrue(stub.invocations.first?.arguments.contains("--output-format") ?? false)
        XCTAssertTrue(stub.invocations.first?.arguments.contains("--json-schema") ?? false)
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

    func testGeminiSmokeTestAcceptsAcknowledgementJSONEnvelope() async throws {
        let raw = #"{"response":"OK","stats":{"models":{}}}"#
        let stub = StubProcessRunner(output: raw)
        let summarizer = CLISummarizer(tool: .gemini, executablePath: "/usr/local/bin/gemini", runner: stub)

        let result = try await summarizer.smokeTest()

        XCTAssertEqual(result, "OK")
        XCTAssertEqual(stub.invocations.first?.arguments.prefix(2).map { $0 }, ["-p", "Reply with OK."])
        XCTAssertEqual(stub.invocations.first?.arguments.suffix(2).map { $0 }, ["--output-format", "json"])
    }

    func testCodexSmokeTestAcceptsAcknowledgementFromOutputFile() async throws {
        let stub = StubProcessRunner(
            behaviors: [
                .success(ProcessExecutionResult(stdout: "Welcome to Codex", stderr: "", terminationStatus: 0, duration: 0))
            ],
            onInvocation: { _, arguments, _, _ in
                guard let outputIndex = arguments.firstIndex(of: "-o"), arguments.indices.contains(outputIndex + 1) else {
                    return
                }
                try? #"{"ok":"OK"}"#.write(toFile: arguments[outputIndex + 1], atomically: true, encoding: .utf8)
            }
        )
        let summarizer = CLISummarizer(tool: .codex, executablePath: "/usr/local/bin/codex", runner: stub)

        let result = try await summarizer.smokeTest()

        XCTAssertEqual(result, "OK")
        let arguments = try XCTUnwrap(stub.invocations.first?.arguments)
        XCTAssertEqual(arguments.prefix(3).map { $0 }, ["exec", "--skip-git-repo-check", "--ephemeral"])
        XCTAssertTrue(arguments.contains("--output-schema"))
        XCTAssertTrue(arguments.contains("-o"))
        XCTAssertEqual(arguments.last, "Reply with OK.")
    }

    func testCodexSummarizeAcceptsStoryJSONWithFiveParagraphs() async throws {
        let raw = """
        {"sections":[{"id":"daily-journal","paragraphs":[
        {"text":"# You did a good job today\\n\\nStayed focused.","sourceEventIDs":["A3F2C1D4-E5B6-7890-ABCD-EF1234567890"]},
        {"text":"# Summary\\n\\n- Kept the reader coherent.","sourceEventIDs":["B3F2C1D4-E5B6-7890-ABCD-EF1234567890"]},
        {"text":"# Details\\n\\n## Demo polish\\nRefined the selection cues.","sourceEventIDs":["C3F2C1D4-E5B6-7890-ABCD-EF1234567890"]},
        {"text":"## Recording readiness\\nKept the evidence pane stable.","sourceEventIDs":["D3F2C1D4-E5B6-7890-ABCD-EF1234567890"]},
        {"text":"# To-do\\n\\n- [ ] Follow up tomorrow.","sourceEventIDs":["E3F2C1D4-E5B6-7890-ABCD-EF1234567890"]}
        ]}]}
        """
        let stub = StubProcessRunner(
            behaviors: [
                .success(ProcessExecutionResult(stdout: "Welcome to Codex", stderr: "", terminationStatus: 0, duration: 0))
            ],
            onInvocation: { _, arguments, _, _ in
                guard let outputIndex = arguments.firstIndex(of: "-o"), arguments.indices.contains(outputIndex + 1) else {
                    return
                }
                try? raw.write(toFile: arguments[outputIndex + 1], atomically: true, encoding: .utf8)
            }
        )
        let summarizer = CLISummarizer(tool: .codex, executablePath: "/usr/local/bin/codex", runner: stub)

        let result = try await summarizer.summarize(
            dayKey: "2026-04-07",
            markdown: "Return strict JSON for the day journal.",
            context: .defaultBehavior
        )

        let payload = try XCTUnwrap(result.data(using: .utf8))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: payload) as? [String: Any])
        let sections = try XCTUnwrap(object["sections"] as? [[String: Any]])
        let firstSection = try XCTUnwrap(sections.first)
        let paragraphs = try XCTUnwrap(firstSection["paragraphs"] as? [[String: Any]])
        XCTAssertEqual(firstSection["id"] as? String, "daily-journal")
        XCTAssertEqual(paragraphs.count, 5)
    }

    func testOpenclawPassesPromptViaAgentCommand() async throws {
        let raw = #"{"payloads":[{"text":"OK","mediaUrl":null}]}"#
        let stub = StubProcessRunner(output: raw)
        let summarizer = CLISummarizer(tool: .openclaw, executablePath: "/usr/local/bin/openclaw", runner: stub)
        let prompt = "Reply with OK."

        let result = try await summarizer.smokeTest(prompt: prompt)

        XCTAssertEqual(result, "OK")
        XCTAssertEqual(
            stub.invocations.first?.arguments,
            ["agent", "--agent", "main", "--message", prompt, "--local", "--json"]
        )
    }

    func testCodexSmokeTestRejectsUnrelatedNonEmptyOutput() async throws {
        let stub = StubProcessRunner(output: "Welcome to Codex.")
        let summarizer = CLISummarizer(tool: .codex, executablePath: "/usr/local/bin/codex", runner: stub)

        await XCTAssertThrowsErrorAsync(
            try await summarizer.smokeTest()
        )
    }

    func testCodexSmokeTestAcceptsTrailingAcknowledgementFromExecOutput() async throws {
        let stub = StubProcessRunner(output: """
        codex
        OK
        tokens used
        33,968
        OK
        """)
        let summarizer = CLISummarizer(tool: .codex, executablePath: "/usr/local/bin/codex", runner: stub)

        let result = try await summarizer.smokeTest()

        XCTAssertEqual(result, "OK")
        let arguments = try XCTUnwrap(stub.invocations.first?.arguments)
        XCTAssertEqual(arguments.prefix(3).map { $0 }, ["exec", "--skip-git-repo-check", "--ephemeral"])
        XCTAssertTrue(arguments.contains("--output-schema"))
        XCTAssertTrue(arguments.contains("-o"))
        XCTAssertEqual(arguments.last, "Reply with OK.")
    }

    func testClaudeSmokeTestRejectsMalformedStructuredOutput() async throws {
        let stub = StubProcessRunner(output: #"{"result":"plain text fallback"}"#)
        let summarizer = CLISummarizer(tool: .claude, executablePath: "/usr/local/bin/claude", runner: stub)

        await XCTAssertThrowsErrorAsync(
            try await summarizer.smokeTest(prompt: "Return a minimal valid JSON object that matches the daily story schema.")
        )
        XCTAssertEqual(stub.invocations.first?.arguments.prefix(2).map { $0 }, ["-p", "Return a minimal valid JSON object that matches the daily story schema."])
    }

    func testGeminiPassesPromptWithTextOutputFlag() async throws {
        let stub = StubProcessRunner(output: #"""
        Loaded cached credentials.
        {"response":"{\"sections\":[{\"id\":\"daily-journal\",\"paragraphs\":[{\"text\":\"Day summary.\",\"sourceEventIDs\":[\"A3F2C1D4-E5B6-7890-ABCD-EF1234567890\"]}]}]}","stats":{"models":{}}}
        """#)
        let summarizer = CLISummarizer(tool: .gemini, executablePath: "/usr/local/bin/gemini", runner: stub)
        let prompt = "Return strict JSON for the day journal."

        let result = try await summarizer.summarize(dayKey: "2026-04-07", markdown: prompt)

        let object = try decodedJSONObject(from: result)
        let sections = try XCTUnwrap(object["sections"] as? [[String: Any]])
        let firstSection = try XCTUnwrap(sections.first)
        let paragraphs = try XCTUnwrap(firstSection["paragraphs"] as? [[String: Any]])
        let firstParagraph = try XCTUnwrap(paragraphs.first)
        XCTAssertEqual(firstParagraph["text"] as? String, "Day summary.")
        XCTAssertEqual(stub.invocations.first?.arguments.prefix(2).map { $0 }, ["-p", prompt])
        XCTAssertEqual(stub.invocations.first?.arguments.suffix(2).map { $0 }, ["--output-format", "json"])
    }

    func testGeminiSmokeTestAcceptsAcknowledgementFromJSONEnvelope() async throws {
        let stub = StubProcessRunner(output: """
        Loaded cached credentials.
        {"response":"OK","stats":{"models":{}}}
        """)
        let summarizer = CLISummarizer(tool: .gemini, executablePath: "/usr/local/bin/gemini", runner: stub)

        let result = try await summarizer.smokeTest()

        XCTAssertEqual(result, "OK")
        XCTAssertEqual(stub.invocations.first?.arguments.prefix(2).map { $0 }, ["-p", "Reply with OK."])
    }

    func testOpenclawSummarizeExtractsPayloadTextFromJSONEnvelope() async throws {
        let raw = #"""
        [plugins] feishu_doc: Registered feishu_doc, feishu_app_scopes
        {"payloads":[{"text":"{\"sections\":[{\"id\":\"daily-journal\",\"paragraphs\":[{\"text\":\"Story output\",\"sourceEventIDs\":[\"A3F2C1D4-E5B6-7890-ABCD-EF1234567890\"]}]}]}","mediaUrl":null}],"meta":{"durationMs":10}}
        """#
        let stub = StubProcessRunner(output: raw)
        let summarizer = CLISummarizer(tool: .openclaw, executablePath: "/usr/local/bin/openclaw", runner: stub)

        let result = try await summarizer.summarize(dayKey: "2026-04-07", markdown: "prompt")

        let object = try decodedJSONObject(from: result)
        let sections = try XCTUnwrap(object["sections"] as? [[String: Any]])
        let firstSection = try XCTUnwrap(sections.first)
        let paragraphs = try XCTUnwrap(firstSection["paragraphs"] as? [[String: Any]])
        let firstParagraph = try XCTUnwrap(paragraphs.first)
        XCTAssertEqual(firstParagraph["text"] as? String, "Story output")
    }

    func testEmptyOutputThrowsStructuredError() async {
        let stub = StubProcessRunner(output: "   ")
        let summarizer = CLISummarizer(tool: .claude, executablePath: "/usr/local/bin/claude", runner: stub)

        await XCTAssertThrowsErrorAsync(
            try await summarizer.summarize(dayKey: "2026-04-07", markdown: "")
        ) { error in
            XCTAssertEqual(error as? CLISummarizerError, .emptyOutput)
        }
    }

    func testContinuationGateOnlyResumesOnce() {
        let gate = ContinuationGate<String>()

        XCTAssertTrue(gate.resume(returning: "first"))
        XCTAssertFalse(gate.resume(returning: "second"))
    }

    func testSystemProcessRunnerReturnsTerminationStatusAndStderrOnNonZeroExit() async throws {
        let runner = SystemProcessRunner()

        let result = try await runner.run(
            executable: "/bin/sh",
            arguments: ["-c", "echo auth failed 1>&2; exit 7"],
            timeoutSeconds: 5
        )

        XCTAssertEqual(result.terminationStatus, 7)
        XCTAssertEqual(result.stderr.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines), "auth failed")
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
    line: UInt = #line,
    _ errorHandler: (Error) -> Void = { _ in }
) async {
    do {
        _ = try await expression()
        XCTFail("Expected error to be thrown", file: file, line: line)
    } catch {
        errorHandler(error)
    }
}
