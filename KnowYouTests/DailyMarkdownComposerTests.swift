import XCTest
@testable import KnowYou

final class DailyMarkdownComposerTests: XCTestCase {
    func testComposerProducesStoryFirstSections() {
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
        let story = composer.fallbackStory(dayKey: "2026-04-07", events: events)

        let markdown = composer.compose(dayKey: "2026-04-07", events: events, story: story)

        XCTAssertTrue(markdown.contains("## Story"), markdown)
        XCTAssertTrue(markdown.contains("## Source Notes"), markdown)
        XCTAssertFalse(markdown.contains("### Main Thread"), markdown)
        XCTAssertFalse(markdown.contains("### Key Progress"), markdown)
    }

    func testFallbackStoryCreatesSourceLinkedParagraphs() {
        let composer = DailyMarkdownComposer()
        let eventID = UUID()
        let events = [
            EventRecord(
                id: eventID,
                sourceType: .clipboard,
                sourceApp: "Drafts",
                capturedAt: Date(timeIntervalSince1970: 1_775_000_000),
                dayKey: "2026-04-07",
                text: "Wrote investor update",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "a"
            ),
        ]

        let story = composer.fallbackStory(dayKey: "2026-04-07", events: events)
        let linkedIDs = story.sections.flatMap(\.paragraphs).flatMap(\.sourceEventIDs)

        XCTAssertTrue(linkedIDs.contains(eventID))
        XCTAssertFalse(story.sections.flatMap(\.paragraphs).isEmpty)
    }

    func testStoryPromptRequestsSingleJournalNarrative() {
        let composer = DailyMarkdownComposer()
        let events = [
            EventRecord(
                id: UUID(),
                sourceType: .clipboard,
                sourceApp: "Ghostty",
                capturedAt: Date(timeIntervalSince1970: 1_775_000_000),
                dayKey: "2026-04-08",
                text: "Implemented the daily story reader",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "prompt-check"
            )
        ]

        let prompt = composer.storyPrompt(dayKey: "2026-04-08", events: events)

        XCTAssertTrue(prompt.contains("\"id\": \"daily-journal\""), prompt)
        XCTAssertTrue(prompt.localizedCaseInsensitiveContains("diary"), prompt)
        XCTAssertFalse(prompt.contains("\"main-thread\""), prompt)
    }

    func testFallbackStoryCompressesNoisyDaysIntoFewDiaryParagraphs() {
        let composer = DailyMarkdownComposer()
        let baseDate = Date(timeIntervalSince1970: 1_775_000_000)
        let events: [EventRecord] = [
            makeEvent(app: "Ghostty", offset: 0, text: "Implemented story-first reader"),
            makeEvent(app: "Ghostty", offset: 60, text: "Refined paragraph selection behavior"),
            makeEvent(app: "Google Chrome", offset: 120, text: "https://github.com/gift-is-coding/know-you/pull/1"),
            makeEvent(app: "Google Chrome", offset: 180, text: "https://github.com/steipete/CodexBar?tab=readme-ov-file"),
            makeEvent(app: "WeChat", offset: 240, text: "你看看去哪呀？"),
            makeEvent(app: "Feishu", offset: 300, text: "仓库\t快递单号\t货物概述"),
            makeEvent(app: "Ghostty", offset: 360, text: "KnowYou clipboard sentinel: knowyou-verify-20260408T132014"),
            makeEvent(app: "Ghostty", offset: 420, text: "KnowYou clipboard sentinel: knowyou-verify-20260408T132021"),
            makeEvent(app: "Finder", offset: 480, text: "/Users/wutianfu/Code/know-you"),
            makeEvent(app: "Google Chrome", offset: 540, text: "Av. Paulista, 2537 - Bela Vista"),
        ].enumerated().map { index, event in
            EventRecord(
                id: UUID(),
                sourceType: .clipboard,
                sourceApp: event.sourceApp,
                capturedAt: baseDate.addingTimeInterval(TimeInterval(index * 60)),
                dayKey: "2026-04-08",
                text: event.text,
                auditText: nil,
                privacyAction: .keep,
                contentHash: "hash-\(index)"
            )
        }

        let story = composer.fallbackStory(dayKey: "2026-04-08", events: events)
        let journal = story.sections.first(where: { $0.id == "daily-journal" })

        XCTAssertNotNil(journal)
        XCTAssertLessThanOrEqual(journal?.paragraphs.count ?? .max, 4)
        XCTAssertTrue(
            journal?.paragraphs.contains(where: { $0.text.localizedCaseInsensitiveContains("verification") }) ?? false,
            "Expected noisy verification sentinels to be summarized into the diary narrative"
        )
        XCTAssertTrue(
            journal?.paragraphs.contains(where: { $0.text.localizedCaseInsensitiveContains("reference") || $0.text.localizedCaseInsensitiveContains("materials") }) ?? false,
            "Expected loose links to be summarized into the diary narrative"
        )
    }

    private func makeEvent(app: String, offset: Int, text: String) -> EventRecord {
        EventRecord(
            id: UUID(),
            sourceType: .clipboard,
            sourceApp: app,
            capturedAt: Date(timeIntervalSince1970: 1_775_000_000 + TimeInterval(offset)),
            dayKey: "2026-04-08",
            text: text,
            auditText: nil,
            privacyAction: .keep,
            contentHash: UUID().uuidString
        )
    }
}
