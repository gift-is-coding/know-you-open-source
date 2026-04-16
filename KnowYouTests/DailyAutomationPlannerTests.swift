import XCTest
@testable import KnowYou

final class DailyAutomationPlannerTests: XCTestCase {
    func testTodayRefreshActionUsesFullRecoveryWhenNoModelStoryExists() {
        let planner = DailyAutomationPlanner(
            backfillPlanner: BackfillPlanner(calendar: Calendar(identifier: .gregorian))
        )

        XCTAssertEqual(planner.todayRefreshAction(todayStory: nil, hasVerifiedSummarizer: true), .fullRecovery)
    }

    func testPendingDaysNeverSchedulesHistoricalBackfill() {
        let planner = DailyAutomationPlanner(
            backfillPlanner: BackfillPlanner(calendar: Calendar(identifier: .gregorian))
        )

        let pendingDays = planner.pendingDays(
            latestCompletedDay: "2026-04-05",
            existingNoteDays: ["2026-04-05", "2026-04-07"],
            today: "2026-04-07"
        )

        XCTAssertEqual(pendingDays, [])
    }

    func testPendingDaysDoesNotAutoCreateTodayWithoutHistory() {
        let planner = DailyAutomationPlanner(
            backfillPlanner: BackfillPlanner(calendar: Calendar(identifier: .gregorian))
        )

        XCTAssertEqual(
            planner.pendingDays(latestCompletedDay: nil, existingNoteDays: [], today: "2026-04-07"),
            []
        )
    }

    func testPendingDaysSkipsTodayWhenTodayAlreadyExistsWithoutRuns() {
        let planner = DailyAutomationPlanner(
            backfillPlanner: BackfillPlanner(calendar: Calendar(identifier: .gregorian))
        )

        XCTAssertEqual(
            planner.pendingDays(
                latestCompletedDay: nil,
                existingNoteDays: ["2026-04-07"],
                today: "2026-04-07"
            ),
            []
        )
    }

    func testPendingDaysSkipsTodayWhenTodayWasAlreadyCompleted() {
        let planner = DailyAutomationPlanner(
            backfillPlanner: BackfillPlanner(calendar: Calendar(identifier: .gregorian))
        )

        XCTAssertEqual(
            planner.pendingDays(
                latestCompletedDay: "2026-04-07",
                existingNoteDays: ["2026-04-07"],
                today: "2026-04-07"
            ),
            []
        )
    }

    func testTodayRefreshActionRequiresVerifiedSummarizerAndUsesIncrementalForModelStories() {
        let planner = DailyAutomationPlanner(
            backfillPlanner: BackfillPlanner(calendar: Calendar(identifier: .gregorian))
        )
        let story = DailyStory(
            dayKey: "2026-04-07",
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            sections: [
                DailyStorySection(
                    id: "daily-journal",
                    title: "",
                    paragraphs: [
                        DailyStoryParagraph(id: "daily-journal-0", text: "test", sourceEventIDs: [])
                    ]
                )
            ],
            provenance: StoryProvenance(
                generationMode: .model,
                engineKind: "codexCLI",
                engineLabel: "Codex (CLI)",
                model: nil,
                pipelineVersion: "diary-story-v1",
                curatedEventCount: 1
            )
        )

        XCTAssertEqual(planner.todayRefreshAction(todayStory: story, hasVerifiedSummarizer: true), .incremental)
        XCTAssertNil(planner.todayRefreshAction(todayStory: story, hasVerifiedSummarizer: false))
        XCTAssertEqual(planner.todayRefreshAction(todayStory: nil, hasVerifiedSummarizer: true), .fullRecovery)
    }
}
