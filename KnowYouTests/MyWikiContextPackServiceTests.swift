import XCTest
@testable import KnowYou

final class MyWikiContextPackServiceTests: XCTestCase {
    func testContextPackRanksCuratedWikiPageAboveRawDiaryAndIncludesCitations() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let project = root.appending(path: "KnowledgeOntology/KnowYouContext", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        try write(
            """
            ---
            type: concept
            title: Agent Context Strategy
            updated: 2026-05-20
            ---

            # Agent Context Strategy

            My Wiki should return cited context packs before third-party agents answer questions.
            The context pack should prefer compiled truth and include evidence references.
            """,
            to: project.appending(path: "wiki/concepts/agent-context-strategy.md")
        )
        try write(
            """
            ---
            type: knowyou-diary
            source: KnowYou
            day: 2026-05-20
            ---

            今天讨论了 agent context strategy，提到 raw diary 只能作为证据。
            """,
            to: project.appending(path: "raw/sources/knowyou-diary-2026-05-20.md")
        )

        let pack = MyWikiContextPackService().contextPack(
            for: MyWikiContextPackRequest(
                projectRoot: project,
                query: "agent context strategy",
                maxItems: 4,
                characterBudget: 2_000
            )
        )

        XCTAssertEqual(pack.query, "agent context strategy")
        XCTAssertEqual(pack.items.map(\.citation.relativePath), [
            "wiki/concepts/agent-context-strategy.md",
            "raw/sources/knowyou-diary-2026-05-20.md",
        ])
        XCTAssertEqual(pack.items.first?.title, "Agent Context Strategy")
        XCTAssertEqual(pack.items.first?.pageType, "concept")
        XCTAssertTrue(pack.items.first?.excerpt.contains("cited context packs") == true)
        XCTAssertEqual(pack.citations.map(\.relativePath), pack.items.map(\.citation.relativePath))
    }

    func testContextPackBuildsQueryPlanFromBackgroundParagraph() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let project = root.appending(path: "KnowledgeOntology/KnowYouContext", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        try write(
            """
            ---
            type: concept
            title: AIDC HVDC Liquid Cooling
            ---

            # AIDC HVDC Liquid Cooling

            AIDC power architecture connects HVDC distribution with liquid cooling capacity planning.
            This page is the compiled wiki truth for data center energy architecture.
            """,
            to: project.appending(path: "wiki/concepts/aidc-hvdc-liquid-cooling.md")
        )
        try write(
            """
            ---
            type: source
            title: Meeting Scratchpad
            ---

            # Meeting Scratchpad

            We mentioned AIDC and liquid cooling in passing during a meeting.
            """,
            to: project.appending(path: "raw/sources/meeting-scratchpad.md")
        )

        let pack = MyWikiContextPackService().contextPack(
            for: MyWikiContextPackRequest(
                projectRoot: project,
                query: "I am designing an agent answer about whether an AIDC project should prefer HVDC power distribution and liquid cooling. It needs context from the compiled My Wiki, not just raw meeting notes.",
                maxItems: 4,
                characterBudget: 2_000
            )
        )

        XCTAssertEqual(pack.items.first?.citation.relativePath, "wiki/concepts/aidc-hvdc-liquid-cooling.md")
        XCTAssertTrue(pack.queryPlan.terms.contains("aidc"))
        XCTAssertTrue(pack.queryPlan.terms.contains("hvdc"))
        XCTAssertTrue(pack.queryPlan.terms.contains("liquid"))
        XCTAssertTrue(pack.items.first?.matchedTerms.contains("hvdc") == true)
        XCTAssertTrue(pack.items.first?.matchedTerms.contains("liquid") == true)
    }

    func testContextPackMatchesUnspacedChineseBackground() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let project = root.appending(path: "KnowledgeOntology/KnowYouContext", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        try write(
            """
            ---
            type: concept
            title: 擎天与 Claw 需求判断
            ---

            # 擎天与 Claw 需求判断

            这页总结擎天和 Claw 的需求判断方式，重点包括场景边界、客户上下文和交付判断。
            """,
            to: project.appending(path: "wiki/concepts/qingtian-claw-demand.md")
        )

        let pack = MyWikiContextPackService().contextPack(
            for: MyWikiContextPackRequest(
                projectRoot: project,
                query: "帮我判断擎天和Claw需求判断应该怎么做，用户没有给关键词，只给了这段背景",
                maxItems: 3,
                characterBudget: 1_200
            )
        )

        XCTAssertEqual(pack.items.first?.citation.relativePath, "wiki/concepts/qingtian-claw-demand.md")
        XCTAssertTrue(pack.queryPlan.terms.contains("擎天"))
        XCTAssertTrue(pack.queryPlan.terms.contains("需求"))
        XCTAssertTrue(pack.queryPlan.terms.contains("判断"))
        XCTAssertTrue(pack.items.first?.matchedTerms.contains("擎天") == true)
    }

    func testContextPackRespectsItemAndCharacterBudgets() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let project = root.appending(path: "KnowledgeOntology/KnowYouContext", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        for index in 1...3 {
            try write(
                """
                ---
                type: source
                title: Context Note \(index)
                ---

                # Context Note \(index)

                agent context ranking evidence \(index) \(String(repeating: "detail ", count: 80))
                """,
                to: project.appending(path: "wiki/sources/context-note-\(index).md")
            )
        }

        let pack = MyWikiContextPackService().contextPack(
            for: MyWikiContextPackRequest(
                projectRoot: project,
                query: "agent context ranking",
                maxItems: 3,
                characterBudget: 260
            )
        )

        XCTAssertLessThanOrEqual(pack.items.count, 2)
        XCTAssertLessThanOrEqual(pack.items.reduce(0) { $0 + $1.excerpt.count }, 260)
    }

    func testMissingProjectReturnsEmptyContextPack() {
        let missing = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)

        let pack = MyWikiContextPackService().contextPack(
            for: MyWikiContextPackRequest(
                projectRoot: missing,
                query: "agent context",
                maxItems: 4,
                characterBudget: 1_000
            )
        )

        XCTAssertEqual(pack.query, "agent context")
        XCTAssertTrue(pack.queryPlan.terms.contains("agent"))
        XCTAssertTrue(pack.items.isEmpty)
        XCTAssertTrue(pack.citations.isEmpty)
    }

    private func write(_ contents: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }
}
