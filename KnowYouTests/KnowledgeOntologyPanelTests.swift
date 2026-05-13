import XCTest
@testable import KnowYou

final class KnowledgeOntologyPanelTests: XCTestCase {
    func testMyWikiCategoryLabelsAreUserFacing() {
        XCTAssertEqual(MyWikiCategory.person.displayTitle, "People")
        XCTAssertEqual(MyWikiCategory.project.displayTitle, "Projects")
        XCTAssertEqual(MyWikiCategory.theme.displayTitle, "Topics")
        XCTAssertEqual(MyWikiCategory.preference.displayTitle, "Preferences")
        XCTAssertEqual(MyWikiCategory.openLoop.displayTitle, "Follow-ups")
        XCTAssertEqual(MyWikiCategory.summary.displayTitle, "Summary")
    }

    func testRecentExportPresentationLimitsVisibleFilesAndSummarizesHiddenCount() {
        let fileNames = (1...28).map { "knowyou-diary-2026-04-\(String(format: "%02d", $0)).md" }

        let presentation = KnowledgeOntologyRecentExportPresentation(
            exportedFileNames: fileNames,
            maxVisibleCount: 8
        )

        XCTAssertEqual(presentation.visibleFileNames, Array(fileNames.prefix(8)))
        XCTAssertEqual(presentation.hiddenCount, 20)
        XCTAssertEqual(presentation.summaryText, "20 more files were synced. You can review them in My Wiki sources.")
    }

    func testRecentExportSummaryUsesMyWikiLanguage() {
        let names = (1...28).map { "knowyou-diary-2026-05-\(String(format: "%02d", $0)).md" }

        let presentation = KnowledgeOntologyRecentExportPresentation(exportedFileNames: names)

        XCTAssertEqual(presentation.visibleFileNames.count, 8)
        XCTAssertEqual(presentation.hiddenCount, 20)
        XCTAssertEqual(presentation.summaryText, "20 more files were synced. You can review them in My Wiki sources.")
    }

    func testRecentExportPresentationShowsAllFilesWhenWithinLimit() {
        let fileNames = [
            "knowyou-diary-2026-05-07.md",
            "knowyou-diary-2026-05-06.md",
            "knowyou-diary-2026-04-29.md",
        ]

        let presentation = KnowledgeOntologyRecentExportPresentation(
            exportedFileNames: fileNames,
            maxVisibleCount: 8
        )

        XCTAssertEqual(presentation.visibleFileNames, fileNames)
        XCTAssertEqual(presentation.hiddenCount, 0)
        XCTAssertNil(presentation.summaryText)
    }
}
