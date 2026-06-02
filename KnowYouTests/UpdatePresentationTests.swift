import XCTest
@testable import KnowYou

final class UpdatePresentationTests: XCTestCase {
    func testUpdateOfferPillTitleUsesStableCopyWhenPublishedTimeAvailable() {
        let offer = UpdateOffer(
            availableVersion: "1.1.0",
            releaseSummary: "Fake update for preview",
            publishedAt: Date(timeIntervalSince1970: 1_776_426_600),
            actionKind: .installInApp,
            storeURL: nil,
            downloadURL: URL(string: "https://knowyou.example.com/download")
        )

        XCTAssertEqual(offer.pillTitle, "Update 1.1.0")
        XCTAssertEqual(offer.primaryActionTitle, "Update Now")
    }

    func testUpdateOfferPillTitleUsesStableCopyWhenPublishedTimeMissing() {
        let offer = UpdateOffer(
            availableVersion: "1.1.0",
            releaseSummary: "Fake update for preview",
            publishedAt: nil,
            actionKind: .installInApp,
            storeURL: nil,
            downloadURL: URL(string: "https://knowyou.example.com/download")
        )

        XCTAssertEqual(offer.pillTitle, "Update 1.1.0")
        XCTAssertEqual(offer.primaryActionTitle, "Update Now")
    }
}
