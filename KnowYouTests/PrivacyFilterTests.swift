import XCTest
@testable import KnowYou

final class PrivacyFilterTests: XCTestCase {
    func testOrdinaryTextIsKept() {
        let filter = PrivacyFilter()

        let result = filter.classify("Buy oat milk on the way home")

        XCTAssertEqual(result.action, .keep)
        XCTAssertEqual(result.persistedText, "Buy oat milk on the way home")
        XCTAssertNil(result.auditText)
    }

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
        XCTAssertEqual(result.auditText, "Sensitive content redacted")
    }

    func testMultipleSensitiveNumericRunsAreAllRedacted() {
        let filter = PrivacyFilter()

        let result = filter.classify("Accounts: 6222021234567890 and 4111111111111111")

        XCTAssertEqual(result.action, .redact)
        XCTAssertEqual(result.persistedText, "Accounts: ************7890 and ************1111")
        XCTAssertEqual(result.auditText, "Sensitive content redacted")
    }

    func testBearerTokenIsDropped() {
        let filter = PrivacyFilter()
        let result = filter.classify("Authorization: Bearer eyJhbGciOiJSUzI1NiJ9.foo.bar")
        XCTAssertEqual(result.action, .drop)
    }

    func testLongNumericRunIsRedactedWithoutLeakingTrailingDigits() {
        let filter = PrivacyFilter()

        let result = filter.classify("Transfer reference 12345678901234567890")

        XCTAssertEqual(result.action, .redact)
        XCTAssertEqual(result.persistedText, "Transfer reference ****************7890")
        XCTAssertEqual(result.auditText, "Sensitive content redacted")
    }
}
