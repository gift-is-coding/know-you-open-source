import XCTest
@testable import KnowYou

final class KnowledgeOntologyPanelTests: XCTestCase {
    func testMyWikiCategoryLabelsAreUserFacing() {
        XCTAssertEqual(MyWikiCategory.person.displayTitle, "People")
        XCTAssertEqual(MyWikiCategory.project.displayTitle, "Projects")
        XCTAssertEqual(MyWikiCategory.theme.displayTitle, "Topics")
        XCTAssertEqual(MyWikiCategory.preference.displayTitle, "Preferences")
        XCTAssertEqual(MyWikiCategory.openLoop.displayTitle, "Follow-ups")
        XCTAssertEqual(MyWikiCategory.summary.displayTitle, "Summaries")
    }

    func testIndexSectionPresentationSupportsCollapsedAndViewAllStates() {
        let entries = (1...6).map { index in
            MyWikiEntry(
                id: "person-\(index)",
                title: "Person \(index)",
                category: .person,
                summary: "Summary \(index)",
                sourceNames: []
            )
        }

        let expanded = MyWikiIndexSectionPresentation(
            title: "People",
            entries: entries,
            isExpanded: true,
            previewLimit: 3
        )
        XCTAssertEqual(expanded.visibleEntries.map(\.title), ["Person 1", "Person 2", "Person 3"])
        XCTAssertTrue(expanded.canViewAll)

        let collapsed = MyWikiIndexSectionPresentation(
            title: "People",
            entries: entries,
            isExpanded: false,
            previewLimit: 3
        )
        XCTAssertTrue(collapsed.visibleEntries.isEmpty)
        XCTAssertTrue(collapsed.canViewAll)
    }

    func testIndexSectionsComeFromSchemaCategories() {
        let relationshipCategory = MyWikiCategoryDefinition(
            id: "relationships",
            displayName: "Relationships",
            singularName: "Relationship",
            directory: "wiki/relationships",
            frontmatterTypes: ["relationship"],
            extractionGuidance: "Relationships between entities.",
            detailSections: ["Summary"]
        )
        let schema = MyWikiSchemaConfig(
            id: "custom",
            displayName: "Custom",
            categories: [relationshipCategory],
            views: []
        )
        let entry = MyWikiEntry(
            id: "huang-shan-lenovo",
            title: "Huang Shan and Lenovo",
            category: MyWikiCategory(definition: relationshipCategory),
            summary: "Relationship summary",
            sourceNames: []
        )
        let snapshot = MyWikiDashboardSnapshot(
            schema: schema,
            entriesByCategoryID: ["relationships": [entry]]
        )

        let sections = MyWikiIndexSectionsBuilder().categorySections(
            snapshot: snapshot,
            query: "",
            expandedCategoryIDs: ["relationships"],
            previewLimit: 4
        )

        XCTAssertEqual(sections.map(\.category.id), ["relationships"])
        XCTAssertEqual(sections.first?.presentation.title, "Relationships")
        XCTAssertEqual(sections.first?.presentation.visibleEntries.map(\.title), ["Huang Shan and Lenovo"])
    }

    func testMyWikiPanelDoesNotRunPipelineOnAppear() {
        XCTAssertEqual(MyWikiPanelLifecyclePolicy.onAppearActions, [.loadDashboard])
        XCTAssertFalse(MyWikiPanelLifecyclePolicy.onAppearActions.contains(.syncDiaries))
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
