import XCTest
@testable import KnowYou

final class KnowledgeOntologyPanelTests: XCTestCase {
    func testMyWikiCategoryLabelsAreUserFacing() {
        XCTAssertEqual(MyWikiCategory.person.displayTitle, "人物")
        XCTAssertEqual(MyWikiCategory.project.displayTitle, "项目")
        XCTAssertEqual(MyWikiCategory.theme.displayTitle, "主题")
        XCTAssertEqual(MyWikiCategory.preference.displayTitle, "偏好")
        XCTAssertEqual(MyWikiCategory.openLoop.displayTitle, "待办")
        XCTAssertEqual(MyWikiCategory.summary.displayTitle, "总结")
    }

    func testRecentExportPresentationLimitsVisibleFilesAndSummarizesHiddenCount() {
        let fileNames = (1...28).map { "knowyou-diary-2026-04-\(String(format: "%02d", $0)).md" }

        let presentation = KnowledgeOntologyRecentExportPresentation(
            exportedFileNames: fileNames,
            maxVisibleCount: 8
        )

        XCTAssertEqual(presentation.visibleFileNames, Array(fileNames.prefix(8)))
        XCTAssertEqual(presentation.hiddenCount, 20)
        XCTAssertEqual(presentation.summaryText, "还有 20 个文件已同步，可在 My Wiki 的原始资料中查看。")
    }

    func testRecentExportSummaryUsesMyWikiLanguage() {
        let names = (1...28).map { "knowyou-diary-2026-05-\(String(format: "%02d", $0)).md" }

        let presentation = KnowledgeOntologyRecentExportPresentation(exportedFileNames: names)

        XCTAssertEqual(presentation.visibleFileNames.count, 8)
        XCTAssertEqual(presentation.hiddenCount, 20)
        XCTAssertEqual(presentation.summaryText, "还有 20 个文件已同步，可在 My Wiki 的原始资料中查看。")
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
