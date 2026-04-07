import XCTest
@testable import KnowYou

final class BackfillPlannerTests: XCTestCase {
    func testMissingDatesBetweenLastCompletedAndTodayAreReturned() {
        let planner = BackfillPlanner(calendar: Calendar(identifier: .gregorian))
        let missing = planner.missingDates(
            lastCompletedDay: "2026-04-04",
            today: "2026-04-07"
        )

        XCTAssertEqual(missing, ["2026-04-05", "2026-04-06", "2026-04-07"])
    }
}
