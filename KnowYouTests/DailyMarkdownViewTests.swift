import XCTest
@testable import KnowYou

final class DailyMarkdownViewTests: XCTestCase {
    func testPresentationShowsEmptyStateWhenStoryIsMissing() {
        let presentation = DailyMarkdownPresentation(story: nil)

        XCTAssertTrue(presentation.showsEmptyState)
    }

    func testPresentationShowsEmptyStateWhenStoryHasNoParagraphs() {
        let story = DailyStory(
            dayKey: "2026-04-08",
            generatedAt: Date(timeIntervalSince1970: 0),
            sections: [
                DailyStorySection(id: "summary", title: "Summary", paragraphs: [])
            ]
        )
        let presentation = DailyMarkdownPresentation(story: story)

        XCTAssertTrue(presentation.showsEmptyState)
    }

    func testPresentationUsesChineseStoryHeadingForChineseParagraphs() {
        let paragraph = DailyStoryParagraph(
            id: "daily-journal-0",
            text: "今天主要在处理发货和确认时间。",
            sourceEventIDs: [UUID()]
        )
        let story = DailyStory(
            dayKey: "2026-04-08",
            generatedAt: Date(timeIntervalSince1970: 0),
            sections: [
                DailyStorySection(id: "daily-journal", title: "", paragraphs: [paragraph])
            ]
        )

        let presentation = DailyMarkdownPresentation(story: story)

        XCTAssertEqual(presentation.storyHeading, "今日小记")
        XCTAssertFalse(presentation.showsEmptyState)
    }

    func testPresentationUsesEnglishStoryHeadingForEnglishParagraphs() {
        let first = DailyStoryParagraph(
            id: "daily-journal-0",
            text: "First paragraph",
            sourceEventIDs: [UUID()]
        )
        let second = DailyStoryParagraph(
            id: "daily-journal-1",
            text: "Second paragraph",
            sourceEventIDs: [UUID()]
        )
        let story = DailyStory(
            dayKey: "2026-04-08",
            generatedAt: Date(timeIntervalSince1970: 0),
            sections: [
                DailyStorySection(id: "summary", title: "Summary", paragraphs: [first, second])
            ]
        )
        let presentation = DailyMarkdownPresentation(story: story)

        XCTAssertEqual(presentation.storyHeading, "Story")
        XCTAssertEqual(presentation.paragraphs, [first, second])
    }

    func testMarkdownRendererUsesAttributedStringWhenParsingSucceeds() {
        let markdown = "A paragraph with **bold** and `code`."

        let content = DailyMarkdownRenderer.content(
            from: markdown,
            parser: { value in
                try AttributedString(
                    markdown: value,
                    options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .full)
                )
            }
        )

        switch content {
        case .attributed(let attributed):
            XCTAssertEqual(String(attributed.characters), "A paragraph with bold and code.")
        case .plainText:
            XCTFail("Expected attributed markdown content")
        }
    }

    func testMarkdownRendererFallsBackToPlainTextWhenParserThrows() {
        let markdown = "A paragraph with **bold** and `code`."

        let content = DailyMarkdownRenderer.content(
            from: markdown,
            parser: { _ in throw MarkdownRenderTestError.expectedFailure }
        )

        switch content {
        case .attributed:
            XCTFail("Expected plain text fallback")
        case .plainText(let value):
            XCTAssertEqual(value, markdown)
        }
    }
}

private enum MarkdownRenderTestError: Error {
    case expectedFailure
}
