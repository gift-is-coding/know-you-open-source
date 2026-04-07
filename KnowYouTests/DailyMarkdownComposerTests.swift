import XCTest
@testable import KnowYou

final class DailyMarkdownComposerTests: XCTestCase {
    func testComposerProducesExpectedSections() {
        let composer = DailyMarkdownComposer()
        let events = [
            EventRecord(
                id: UUID(),
                sourceType: .clipboard,
                sourceApp: "Drafts",
                capturedAt: Date(timeIntervalSince1970: 1_775_000_000),
                dayKey: "2026-04-07",
                text: "Wrote investor update",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "a"
            ),
            EventRecord(
                id: UUID(),
                sourceType: .notification,
                sourceApp: "Calendar",
                capturedAt: Date(timeIntervalSince1970: 1_775_000_100),
                dayKey: "2026-04-07",
                text: "Meeting in 10 minutes",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "b"
            ),
        ]

        let markdown = composer.compose(dayKey: "2026-04-07", events: events, summary: "Busy day")

        XCTAssertTrue(markdown.contains("## Summary"))
        XCTAssertTrue(markdown.contains("## Timeline"))
        XCTAssertTrue(markdown.contains("## Clipboard"))
        XCTAssertTrue(markdown.contains("## Notifications"))
    }
}
