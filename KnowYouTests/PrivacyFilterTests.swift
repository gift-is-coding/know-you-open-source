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

    func testDiaryShareBuilderCombinesStoryParagraphsInOrderForFullDiaryShare() {
        let first = DailyStoryParagraph(id: "p1", text: "First **moment**", sourceEventIDs: [])
        let second = DailyStoryParagraph(id: "p2", text: "Second moment", sourceEventIDs: [])
        let story = DailyStory(
            dayKey: "2026-06-12",
            generatedAt: makeDate(),
            sections: [
                DailyStorySection(id: "story", title: "Story", paragraphs: [first, second])
            ]
        )

        let payload = DiaryShareContentBuilder().payload(source: .fullStory(story), redacted: false)

        XCTAssertEqual(payload?.dayKey, "2026-06-12")
        XCTAssertEqual(payload?.sourceTitle, "Full diary")
        XCTAssertEqual(payload?.body, "First **moment**\n\nSecond moment")
        XCTAssertEqual(payload?.mode, .original)
    }

    func testDiaryShareBuilderUsesOnlyRequestedParagraphForParagraphShare() {
        let paragraph = DailyStoryParagraph(id: "p1", text: "Only this paragraph", sourceEventIDs: [])

        let payload = DiaryShareContentBuilder().payload(
            source: .paragraph(paragraph, dayKey: "2026-06-12"),
            redacted: false
        )

        XCTAssertEqual(payload?.dayKey, "2026-06-12")
        XCTAssertEqual(payload?.sourceTitle, "Diary excerpt")
        XCTAssertEqual(payload?.body, "Only this paragraph")
        XCTAssertEqual(payload?.mode, .original)
    }

    func testDiaryShareRedactorMasksEmailLongNumbersSecretsAndURLQueries() {
        let text = """
        Email me at founder@example.com.
        Card 4111111111111111.
        token: abc123secret
        Link https://giiift.site/know-you/download?token=private#invite
        """

        let redacted = DiaryShareRedactor().redact(text)

        XCTAssertFalse(redacted.contains("founder@example.com"), redacted)
        XCTAssertFalse(redacted.contains("4111111111111111"), redacted)
        XCTAssertFalse(redacted.contains("abc123secret"), redacted)
        XCTAssertFalse(redacted.contains("?token=private"), redacted)
        XCTAssertFalse(redacted.contains("#invite"), redacted)
        XCTAssertTrue(redacted.contains("[email]"), redacted)
        XCTAssertTrue(redacted.contains("[number]"), redacted)
        XCTAssertTrue(redacted.contains("token: [secret]"), redacted)
        XCTAssertTrue(redacted.contains("https://giiift.site/know-you/download"), redacted)
    }

    func testDiaryShareBuilderLeavesOriginalTextUnchangedWhenRedactionIsDisabled() {
        let paragraph = DailyStoryParagraph(
            id: "p1",
            text: "Email founder@example.com with card 4111111111111111",
            sourceEventIDs: []
        )

        let payload = DiaryShareContentBuilder().payload(
            source: .paragraph(paragraph, dayKey: "2026-06-12"),
            redacted: false
        )

        XCTAssertEqual(payload?.body, "Email founder@example.com with card 4111111111111111")
        XCTAssertEqual(payload?.mode, .original)
    }

    private func makeDate() -> Date {
        Date(timeIntervalSince1970: 1_781_222_400)
    }
}
