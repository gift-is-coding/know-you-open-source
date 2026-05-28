import XCTest
@testable import KnowYou

final class MyWikiAgentContextProviderTests: XCTestCase {
    func testBuildsAgentBriefFromNativeLlmWikiCategories() {
        let snapshot = MyWikiDashboardSnapshot(
            sources: [
                MyWikiEntry(
                    id: "knowyou-diary-2026-05-12",
                    title: "Diary 2026-05-12",
                    category: .source,
                    summary: "当天记录了 My Wiki 的产品轻量化讨论。",
                    sourceNames: ["knowyou-diary-2026-05-12.md"]
                )
            ],
            entities: [
                MyWikiEntry(
                    id: "knowyou",
                    title: "KnowYou",
                    category: .entity,
                    summary: "从日记工具升级为 My Wiki。",
                    sourceNames: ["knowyou-diary-2026-05-12.md"]
                )
            ],
            concepts: [
                MyWikiEntry(
                    id: "lightweight-ui",
                    title: "轻量 UI",
                    category: .concept,
                    summary: "用户不希望看到复杂图谱。",
                    sourceNames: ["knowyou-diary-2026-05-12.md"]
                )
            ]
        )

        let brief = MyWikiAgentContextProvider().brief(from: snapshot, maxItemsPerCategory: 2)

        XCTAssertTrue(brief.contains("## Sources"))
        XCTAssertTrue(brief.contains("## Entities"))
        XCTAssertTrue(brief.contains("## Concepts"))
        XCTAssertTrue(brief.contains("KnowYou"))
        XCTAssertTrue(brief.contains("轻量 UI"))
        XCTAssertTrue(brief.contains("Sources: knowyou-diary-2026-05-12.md"))
        XCTAssertFalse(brief.contains("## People"))
        XCTAssertFalse(brief.contains("## Projects"))
        XCTAssertFalse(brief.contains("## Topics"))
        XCTAssertFalse(brief.contains("## Patterns"))
        XCTAssertFalse(brief.contains("## Follow-ups"))
    }
}
