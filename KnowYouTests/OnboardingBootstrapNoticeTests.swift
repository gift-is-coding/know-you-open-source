import XCTest
@testable import KnowYou

final class OnboardingBootstrapNoticeTests: XCTestCase {
    func testPresentationUsesStableTitleAndRuntimeMessage() {
        let notice = OnboardingBootstrapNotice(
            message: "Generating today and yesterday now. Come back in about 2 minutes."
        )

        let presentation = OnboardingBootstrapNoticePresentation(notice: notice)

        XCTAssertEqual(presentation.title, "First entries are generating")
        XCTAssertEqual(presentation.message, notice.message)
    }
}
