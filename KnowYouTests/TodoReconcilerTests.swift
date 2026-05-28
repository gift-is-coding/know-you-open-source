import XCTest
@testable import KnowYou

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
}

private struct StaticTodoSummarizer: SummaryGenerating {
    let response: String

    func summarize(dayKey: String, markdown: String, context: SummaryInvocationContext) async throws -> String {
        response
    }
}
