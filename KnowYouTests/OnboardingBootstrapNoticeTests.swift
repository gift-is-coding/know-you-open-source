import XCTest
@testable import KnowYou

final class OnboardingBootstrapNoticeTests: XCTestCase {
    func testPresentationUsesStableTitleAndRuntimeMessage() {
        let notice = OnboardingBootstrapNotice(
            message: "KnowYou is generating your first 3 days from available local history. All local. No backend server.",
            progress: OnboardingBootstrapProgress(
                completedDayCount: 1,
                totalDayCount: 3,
                activeDayKey: "2026-04-10"
            )
        )

        let presentation = OnboardingBootstrapNoticePresentation(notice: notice)

        XCTAssertEqual(presentation.title, "First 3 days are generating")
        XCTAssertEqual(presentation.message, notice.message)
        XCTAssertEqual(presentation.progressText, "1/3 complete · Now writing 2026-04-10")
    }
}
