import XCTest
@testable import KnowYou

final class PrivacyFilterTests: XCTestCase {
    func testPasswordLikeContentIsDropped() {
        let filter = PrivacyFilter()

        let result = filter.classify("Password: hunter2")

        XCTAssertEqual(result.action, .drop)
        XCTAssertNil(result.persistedText)
        XCTAssertEqual(result.auditText, "Sensitive content skipped")
    }

    func testBankAccountContentIsRedacted() {
        let filter = PrivacyFilter()

        let result = filter.classify("Wire to account 6222021234567890")

        XCTAssertEqual(result.action, .redact)
        XCTAssertEqual(result.persistedText, "Wire to account ************7890")
    }
}
