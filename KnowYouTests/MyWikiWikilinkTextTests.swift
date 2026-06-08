import XCTest
@testable import KnowYou

final class MyWikiWikilinkTextTests: XCTestCase {
    func testWikilinkAttributedStringReplacesDoubleBracketsWithClickableLinks() throws {
        let markdown = "最紧急的事项是 [[supabase]] 发来的安全提醒。通知显示项目 [[homeskill]] 存在 Critical issue，因此应在 [[supabase-security-vulnerability-response]] 中标记为待确认的开放风险。"

        let attributed = MyWikiWikilinkText.attributedString(from: markdown)
        let links = linkRuns(in: attributed)

        XCTAssertEqual(
            String(attributed.characters),
            "最紧急的事项是 supabase 发来的安全提醒。通知显示项目 homeskill 存在 Critical issue，因此应在 supabase-security-vulnerability-response 中标记为待确认的开放风险。"
        )
        XCTAssertEqual(links.map(\.text), [
            "supabase",
            "homeskill",
            "supabase-security-vulnerability-response"
        ])
        XCTAssertEqual(links.compactMap { MyWikiWikilinkText.reference(from: $0.url) }, [
            "supabase",
            "homeskill",
            "supabase-security-vulnerability-response"
        ])
    }

    func testWikilinkAttributedStringUsesAliasDisplayText() throws {
        let attributed = MyWikiWikilinkText.attributedString(
            from: "Follow [[supabase-security-vulnerability-response|安全响应]]."
        )
        let links = linkRuns(in: attributed)

        XCTAssertEqual(String(attributed.characters), "Follow 安全响应.")
        XCTAssertEqual(links.map(\.text), ["安全响应"])
        XCTAssertEqual(
            links.compactMap { MyWikiWikilinkText.reference(from: $0.url) },
            ["supabase-security-vulnerability-response"]
        )
    }

    func testSummaryAttributedStringMakesReferencesClickable() throws {
        let attributed = MyWikiWikilinkText.summaryAttributedString(
            from: "a16z Speedrun 和 [[knowyou]]、[[y-combinator|YC]] 一起构成候选机构列表。"
        )
        let links = linkRuns(in: attributed)

        XCTAssertEqual(
            String(attributed.characters),
            "a16z Speedrun 和 knowyou、YC 一起构成候选机构列表。"
        )
        XCTAssertEqual(links.map(\.text), ["knowyou", "YC"])
        XCTAssertEqual(
            links.compactMap { MyWikiWikilinkText.reference(from: $0.url) },
            ["knowyou", "y-combinator"]
        )
    }

    private func linkRuns(in attributed: AttributedString) -> [(text: String, url: URL)] {
        attributed.runs.compactMap { run in
            guard let url = run.link else { return nil }
            return (String(attributed[run.range].characters), url)
        }
    }
}
