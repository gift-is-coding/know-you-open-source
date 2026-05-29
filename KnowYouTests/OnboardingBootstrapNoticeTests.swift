import XCTest
@testable import KnowYou

final class OnboardingBootstrapNoticeTests: XCTestCase {
    func testPresentationUsesStableTitleAndRuntimeMessage() {
        let notice = OnboardingBootstrapNotice(
            message: "KnowYou is generating your first 7 days from this Mac. All local. No backend server.",
            progress: OnboardingBootstrapProgress(
                completedDayCount: 1,
                totalDayCount: 7,
                activeDayKey: "2026-04-10"
            )
        )

        let presentation = OnboardingBootstrapNoticePresentation(notice: notice)

        XCTAssertEqual(presentation.title, "First 7 days are generating")
        XCTAssertEqual(presentation.message, notice.message)
        XCTAssertEqual(presentation.progressText, "1/7 complete · Now writing 2026-04-10")
    }
}
