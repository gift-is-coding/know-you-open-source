import XCTest
@testable import KnowYou

private final class TodoStubProcessRunner: ProcessRunning, @unchecked Sendable {
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

private final class TodoSchemaCapture: @unchecked Sendable {
    var contents = ""
}

final class TodoReconcilerTests: XCTestCase {
    func testReconcilerPromotesOnlyHighConfidenceCreates() async throws {
        let high = DailyTodoCandidate(
            id: "candidate-high",
            title: "Send the investor recap",
            normalizedTitle: "send the investor recap",
            sourceDayKey: "2026-05-27",
            sourceEventIDs: [UUID()],
            paragraphID: "daily-journal-todo"
        )
        let low = DailyTodoCandidate(
            id: "candidate-low",
            title: "Keep thinking about launch",
            normalizedTitle: "keep thinking about launch",
            sourceDayKey: "2026-05-27",
            sourceEventIDs: [UUID()],
            paragraphID: "daily-journal-todo"
        )
        let summarizer = StaticTodoSummarizer(
            response: """
            {
              "decisions": [
                {
                  "candidateID": "candidate-high",
                  "action": "create",
                  "confidence": "high",
                  "targetTodoID": null,
                  "reason": "The source asks for a specific future action."
                },
                {
                  "candidateID": "candidate-low",
                  "action": "create",
                  "confidence": "low",
                  "targetTodoID": null,
                  "reason": "This is a vague suggestion."
                }
              ]
            }
            """
        )

        let result = try await TodoReconciler(summarizer: summarizer).reconcile(
            candidates: [high, low],
            existingTodos: [],
            dayKey: "2026-05-27"
        )

        XCTAssertFalse(result.isDegraded)
        XCTAssertEqual(result.highConfidenceCreates.map(\.candidateID), ["candidate-high"])
        XCTAssertEqual(result.decisions.count, 2)
    }

    func testReconcilerUsesTodoDecisionSchemaWithCLISummarizer() async throws {
        let candidate = DailyTodoCandidate(
            id: "candidate-high",
            title: "Send the investor recap",
            normalizedTitle: "send the investor recap",
            sourceDayKey: "2026-05-27",
            sourceEventIDs: [UUID()],
            paragraphID: "daily-journal-todo"
        )
        let response = """
        {
          "decisions": [
            {
              "candidateID": "candidate-high",
              "action": "create",
              "confidence": "high",
              "targetTodoID": null,
              "reason": "The source asks for a durable future action."
            }
          ]
        }
        """
        let schemaCapture = TodoSchemaCapture()
        let runner = TodoStubProcessRunner(
            behaviors: [
                .success(ProcessExecutionResult(stdout: "", stderr: "", terminationStatus: 0, duration: 0))
            ],
            onInvocation: { _, arguments, _, _ in
                if let schemaIndex = arguments.firstIndex(of: "--output-schema"), arguments.indices.contains(schemaIndex + 1) {
                    schemaCapture.contents = (try? String(contentsOfFile: arguments[schemaIndex + 1], encoding: .utf8)) ?? ""
                }
                if let outputIndex = arguments.firstIndex(of: "-o"), arguments.indices.contains(outputIndex + 1) {
                    try? response.write(toFile: arguments[outputIndex + 1], atomically: true, encoding: .utf8)
                }
            }
        )
        let summarizer = CLISummarizer(tool: .codex, executablePath: "/usr/local/bin/codex", runner: runner)

        let result = try await TodoReconciler(summarizer: summarizer).reconcile(
            candidates: [candidate],
            existingTodos: [],
            dayKey: "2026-05-27"
        )

        XCTAssertFalse(result.isDegraded)
        XCTAssertEqual(result.highConfidenceCreates.map(\.candidateID), ["candidate-high"])
        _ = try XCTUnwrap(runner.invocations.first?.arguments)
        let schema = schemaCapture.contents
        XCTAssertTrue(schema.contains(#""decisions""#), schema)
        XCTAssertFalse(schema.contains(#""sections""#), schema)
    }

    func testReconcilerDegradesWithoutSummarizerAndDoesNotAutoCreate() async throws {
        let candidate = DailyTodoCandidate(
            id: "candidate",
            title: "Send the investor recap",
            normalizedTitle: "send the investor recap",
            sourceDayKey: "2026-05-27",
            sourceEventIDs: [],
            paragraphID: "daily-journal-todo"
        )

        let result = try await TodoReconciler(summarizer: nil).reconcile(
            candidates: [candidate],
            existingTodos: [],
            dayKey: "2026-05-27"
        )

        XCTAssertTrue(result.isDegraded)
        XCTAssertTrue(result.decisions.isEmpty)
        XCTAssertTrue(result.highConfidenceCreates.isEmpty)
    }

    func testCompletionSweepMarksOnlyEvidenceBackedCompletions() async throws {
        let evidenceID = UUID()
        let todo = UnifiedTodoItem(
            id: "todo-1",
            title: "Send the investor recap",
            normalizedTitle: "send the investor recap",
            status: .open,
            sourceDayKey: "2026-05-27",
            sourceEventIDs: [],
            createdAt: Date(timeIntervalSince1970: 1_778_000_000),
            completedAt: nil,
            completionEvidenceEventIDs: [],
            promotionKind: .auto,
            completionKind: nil
        )
        let story = DailyStory(
            dayKey: "2026-05-27",
            generatedAt: Date(timeIntervalSince1970: 1_778_000_100),
            sections: [
                DailyStorySection(
                    id: "daily-journal",
                    title: "",
                    paragraphs: [
                        DailyStoryParagraph(
                            id: "daily-journal-details-0",
                            text: "The investor recap was sent and acknowledged.",
                            sourceEventIDs: [evidenceID]
                        )
                    ]
                )
            ]
        )
        let summarizer = StaticTodoSummarizer(
            response: """
            {
              "completed": [
                {
                  "todoID": "todo-1",
                  "confidence": "high",
                  "evidenceEventIDs": ["\(evidenceID.uuidString)"],
                  "reason": "The new evidence says the recap was sent."
                }
              ]
            }
            """
        )

        let result = try await TodoCompletionSweep(summarizer: summarizer).sweep(
            openTodos: [todo],
            story: story,
            dayKey: "2026-05-27"
        )

        XCTAssertFalse(result.isDegraded)
        XCTAssertEqual(result.completions.map(\.todoID), ["todo-1"])
        XCTAssertEqual(result.highConfidenceCompletions.map(\.todoID), ["todo-1"])
        XCTAssertTrue(result.reviewRecommendations.isEmpty)
        XCTAssertEqual(result.completions.first?.evidenceEventIDs, [evidenceID])
    }

    func testCompletionSweepKeepsMediumConfidenceCompletionsForReview() async throws {
        let evidenceID = UUID()
        let todo = UnifiedTodoItem(
            id: "todo-1",
            title: "Polish the Todo workbench",
            normalizedTitle: "polish the todo workbench",
            status: .open,
            sourceDayKey: "2026-05-27",
            sourceEventIDs: [],
            createdAt: Date(timeIntervalSince1970: 1_778_000_000),
            completedAt: nil,
            completionEvidenceEventIDs: [],
            promotionKind: .manual,
            completionKind: nil
        )
        let story = DailyStory(
            dayKey: "2026-05-27",
            generatedAt: Date(timeIntervalSince1970: 1_778_000_100),
            sections: [
                DailyStorySection(
                    id: "daily-journal",
                    title: "",
                    paragraphs: [
                        DailyStoryParagraph(
                            id: "daily-journal-details-0",
                            text: "The Todo workbench mockup was accepted, but implementation remains pending.",
                            sourceEventIDs: [evidenceID]
                        )
                    ]
                )
            ]
        )
        let summarizer = StaticTodoSummarizer(
            response: """
            {
              "completed": [
                {
                  "todoID": "todo-1",
                  "confidence": "medium",
                  "evidenceEventIDs": ["\(evidenceID.uuidString)"],
                  "reason": "The mockup appears accepted, but implementation remains pending."
                }
              ]
            }
            """
        )

        let result = try await TodoCompletionSweep(summarizer: summarizer).sweep(
            openTodos: [todo],
            story: story,
            dayKey: "2026-05-27"
        )

        XCTAssertFalse(result.isDegraded)
        XCTAssertTrue(result.highConfidenceCompletions.isEmpty)
        XCTAssertEqual(result.reviewRecommendations.map(\.todoID), ["todo-1"])
        XCTAssertEqual(result.reviewRecommendations.first?.confidence, .medium)
    }

    func testCompletionSweepUsesCompletionSchemaWithCLISummarizer() async throws {
        let evidenceID = UUID()
        let todo = UnifiedTodoItem(
            id: "todo-1",
            title: "Send the investor recap",
            normalizedTitle: "send the investor recap",
            status: .open,
            sourceDayKey: "2026-05-27",
            sourceEventIDs: [],
            createdAt: Date(timeIntervalSince1970: 1_778_000_000),
            completedAt: nil,
            completionEvidenceEventIDs: [],
            promotionKind: .manual,
            completionKind: nil
        )
        let story = DailyStory(
            dayKey: "2026-05-27",
            generatedAt: Date(timeIntervalSince1970: 1_778_000_100),
            sections: [
                DailyStorySection(
                    id: "daily-journal",
                    title: "",
                    paragraphs: [
                        DailyStoryParagraph(
                            id: "daily-journal-details-0",
                            text: "The investor recap was sent.",
                            sourceEventIDs: [evidenceID]
                        )
                    ]
                )
            ]
        )
        let response = """
        {
          "completed": [
            {
              "todoID": "todo-1",
              "confidence": "high",
              "evidenceEventIDs": ["\(evidenceID.uuidString)"],
              "reason": "The source says it was sent."
            }
          ]
        }
        """
        let schemaCapture = TodoSchemaCapture()
        let runner = TodoStubProcessRunner(
            behaviors: [
                .success(ProcessExecutionResult(stdout: "", stderr: "", terminationStatus: 0, duration: 0))
            ],
            onInvocation: { _, arguments, _, _ in
                if let schemaIndex = arguments.firstIndex(of: "--output-schema"), arguments.indices.contains(schemaIndex + 1) {
                    schemaCapture.contents = (try? String(contentsOfFile: arguments[schemaIndex + 1], encoding: .utf8)) ?? ""
                }
                if let outputIndex = arguments.firstIndex(of: "-o"), arguments.indices.contains(outputIndex + 1) {
                    try? response.write(toFile: arguments[outputIndex + 1], atomically: true, encoding: .utf8)
                }
            }
        )
        let summarizer = CLISummarizer(tool: .codex, executablePath: "/usr/local/bin/codex", runner: runner)

        let result = try await TodoCompletionSweep(summarizer: summarizer).sweep(
            openTodos: [todo],
            story: story,
            dayKey: "2026-05-27"
        )

        XCTAssertFalse(result.isDegraded)
        XCTAssertEqual(result.highConfidenceCompletions.map(\.todoID), ["todo-1"])
        _ = try XCTUnwrap(runner.invocations.first?.arguments)
        let schema = schemaCapture.contents
        XCTAssertTrue(schema.contains(#""completed""#), schema)
        XCTAssertFalse(schema.contains(#""sections""#), schema)
    }
}

private struct StaticTodoSummarizer: SummaryGenerating {
    let response: String

    func summarize(dayKey: String, markdown: String, context: SummaryInvocationContext) async throws -> String {
        response
    }
}
