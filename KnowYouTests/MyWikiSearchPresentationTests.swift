import XCTest
@testable import KnowYou

final class MyWikiSearchPresentationTests: XCTestCase {
    func testSearchActivationRequiresNonBlankQuery() {
        XCTAssertFalse(MyWikiSearchActivationPolicy.usesSearchResults(query: "   "))
        XCTAssertTrue(MyWikiSearchActivationPolicy.usesSearchResults(query: "啥玩意"))
    }

    func testSearchResultsPresentationShowsResultCountAndGroups() {
        let response = MyWikiSearchResponse(
            query: "啥玩意",
            results: [
                MyWikiSearchResult(
                    id: "raw/sources/My Diary/knowyou-diary-2026-04-24.md",
                    title: "2026-04-24",
                    relativePath: "raw/sources/My Diary/knowyou-diary-2026-04-24.md",
                    sourceKind: .rawSource,
                    groupTitle: "2026-04-24",
                    day: "2026-04-24",
                    snippet: "今天微信里出现了啥玩意这个表达。",
                    score: 42,
                    matchedTerms: ["啥玩意"],
                    matchCount: 1
                )
            ],
            groups: [
                MyWikiSearchGroup(
                    id: "2026-04-24",
                    title: "2026-04-24",
                    results: [
                        MyWikiSearchResult(
                            id: "raw/sources/My Diary/knowyou-diary-2026-04-24.md",
                            title: "2026-04-24",
                            relativePath: "raw/sources/My Diary/knowyou-diary-2026-04-24.md",
                            sourceKind: .rawSource,
                            groupTitle: "2026-04-24",
                            day: "2026-04-24",
                            snippet: "今天微信里出现了啥玩意这个表达。",
                            score: 42,
                            matchedTerms: ["啥玩意"],
                            matchCount: 1
                        )
                    ]
                )
            ]
        )

        let presentation = MyWikiSearchResultsPresentation(response: response)

        XCTAssertEqual(presentation.resultCountTitle, "1 result")
        XCTAssertEqual(presentation.groups.map(\.title), ["2026-04-24"])
        XCTAssertEqual(presentation.groups.first?.resultCountTitle, "1")
    }
}
