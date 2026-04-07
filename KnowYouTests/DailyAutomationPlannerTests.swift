import XCTest
@testable import KnowYou

final class DailyAutomationPlannerTests: XCTestCase {
    func testPendingDaysBackfillsGapAndIncludesToday() {
        let planner = DailyAutomationPlanner(
            backfillPlanner: BackfillPlanner(calendar: Calendar(identifier: .gregorian))
        )

        let pendingDays = planner.pendingDays(
            latestCompletedDay: "2026-04-05",
            existingNoteDays: ["2026-04-05"],
            today: "2026-04-07"
        )

        XCTAssertEqual(pendingDays, ["2026-04-06", "2026-04-07"])
    }

    func testPendingDaysReturnsTodayWhenNoHistoryExists() {
        let planner = DailyAutomationPlanner(
            backfillPlanner: BackfillPlanner(calendar: Calendar(identifier: .gregorian))
        )

        XCTAssertEqual(
            planner.pendingDays(latestCompletedDay: nil, existingNoteDays: [], today: "2026-04-07"),
            ["2026-04-07"]
        )
    }

    func testPendingDaysReturnsEmptyWhenTodayAlreadyExistsWithoutRuns() {
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
}
