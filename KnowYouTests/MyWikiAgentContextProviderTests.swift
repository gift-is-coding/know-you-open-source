import XCTest
@testable import KnowYou

final class MyWikiAgentContextProviderTests: XCTestCase {
    func testBuildsAgentBriefFromProjectsThemesAndPreferences() {
        let snapshot = MyWikiDashboardSnapshot(
            summaries: [],
            people: [],
            projects: [
                MyWikiEntry(
                    id: "knowyou",
                    title: "KnowYou",
                    category: .project,
                    summary: "从日记工具升级为 My Wiki。",
                    sourceNames: ["knowyou-diary-2026-05-12.md"]
                )
            ],
            themes: [
                MyWikiEntry(
                    id: "lightweight-ui",
                    title: "轻量 UI",
                    category: .theme,
                    summary: "用户不希望看到复杂图谱。",
                    sourceNames: ["knowyou-diary-2026-05-12.md"]
                )
            ],
            preferences: [
                MyWikiEntry(
                    id: "plain-language",
                    title: "普通语言",
                    category: .preference,
                    summary: "前端不要暴露 entity/concept。",
                    sourceNames: ["knowyou-diary-2026-05-12.md"]
                )
            ],
            openLoops: []
        )

        let brief = MyWikiAgentContextProvider().brief(from: snapshot, maxItemsPerCategory: 2)

        XCTAssertTrue(brief.contains("KnowYou"))
        XCTAssertTrue(brief.contains("轻量 UI"))
        XCTAssertTrue(brief.contains("普通语言"))
        XCTAssertTrue(brief.contains("Sources: knowyou-diary-2026-05-12.md"))
        XCTAssertFalse(brief.contains("entity"))
        XCTAssertFalse(brief.contains("concept"))
    }

    func testBuildsAgentBriefFromSchemaConfiguredCategories() {
        let relationshipCategory = MyWikiCategoryDefinition(
            id: "relationships",
            displayName: "Relationships",
            singularName: "Relationship",
            directory: "wiki/relationships",
            frontmatterTypes: ["relationship"],
            extractionGuidance: "Extract important relationships between people, organizations, projects, and topics.",
            detailSections: ["Summary"]
        )
        let entry = MyWikiEntry(
            id: "huang-shan-lenovo",
            title: "Huang Shan and Lenovo",
            category: MyWikiCategory(definition: relationshipCategory),
            summary: "Huang Shan is connected to Lenovo platform ownership.",
            sourceNames: ["knowyou-diary-2026-05-14.md"]
        )
        let snapshot = MyWikiDashboardSnapshot(
            schema: MyWikiSchemaConfig(
                id: "custom",
                displayName: "Custom",
                categories: [relationshipCategory],
                views: []
            ),
            entriesByCategoryID: ["relationships": [entry]]
        )

        let brief = MyWikiAgentContextProvider().brief(from: snapshot)

        XCTAssertTrue(brief.contains("## Relationships"))
        XCTAssertTrue(brief.contains("Huang Shan and Lenovo"))
        XCTAssertTrue(brief.contains("knowyou-diary-2026-05-14.md"))
    }
}
