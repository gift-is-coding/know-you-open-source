import XCTest
@testable import KnowYou

final class MyWikiSearchServiceTests: XCTestCase {
    func testSearchFindsDiaryRawSourceAndImportedSourceWithSnippets() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let project = root.appending(path: "KnowledgeOntology/KnowYouContext", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        try write(
            """
            ---
            type: knowyou-diary
            day: 2026-04-24
            title: 2026-04-24
            ---

            今天微信里出现了啥玩意这个表达，后面还有案例分析环节。
            """,
            to: project.appending(path: "raw/sources/My Diary/knowyou-diary-2026-04-24.md")
        )
        try write(
            """
            # Meeting Notes

            The imported meeting notes also mention 啥玩意 while discussing project ownership.
            """,
            to: project.appending(path: "raw/sources/Local Folder/local-main/Projects/meeting-notes.md")
        )

        let response = MyWikiSearchService().search(
            MyWikiSearchRequest(projectRoot: project, query: "啥玩意", maxResults: 10)
        )

        XCTAssertEqual(response.query, "啥玩意")
        XCTAssertEqual(response.totalResultCount, 2)
        XCTAssertEqual(response.groups.map(\.title), ["2026-04-24", "Local Folder"])
        XCTAssertTrue(response.results.map(\.relativePath).contains("raw/sources/My Diary/knowyou-diary-2026-04-24.md"))
        XCTAssertTrue(response.results.map(\.relativePath).contains("raw/sources/Local Folder/local-main/Projects/meeting-notes.md"))
        XCTAssertTrue(response.results.allSatisfy { $0.snippet.contains("啥玩意") })
    }

    func testSearchRanksCuratedWikiPageBeforeRawDiary() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let project = root.appending(path: "KnowledgeOntology/KnowYouContext", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        try write(
            """
            ---
            type: concept
            title: Agent Context Strategy
            ---

            # Agent Context Strategy

            Agent context search should prefer compiled My Wiki truth before raw diary evidence.
            """,
            to: project.appending(path: "wiki/concepts/agent-context-strategy.md")
        )
        try write(
            """
            ---
            type: knowyou-diary
            day: 2026-05-20
            ---

            agent context search was mentioned in a raw diary note.
            """,
            to: project.appending(path: "raw/sources/My Diary/knowyou-diary-2026-05-20.md")
        )

        let response = MyWikiSearchService().search(
            MyWikiSearchRequest(projectRoot: project, query: "agent context search", maxResults: 10)
        )

        XCTAssertEqual(response.results.map(\.relativePath), [
            "wiki/concepts/agent-context-strategy.md",
            "raw/sources/My Diary/knowyou-diary-2026-05-20.md",
        ])
        XCTAssertEqual(response.results.first?.sourceKind, .wiki)
    }

    func testSearchReturnsEmptyForBlankQueryOrMissingProject() {
        let missing = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)

        let blank = MyWikiSearchService().search(
            MyWikiSearchRequest(projectRoot: missing, query: "   ", maxResults: 10)
        )
        let missingProject = MyWikiSearchService().search(
            MyWikiSearchRequest(projectRoot: missing, query: "agent", maxResults: 10)
        )

        XCTAssertTrue(blank.results.isEmpty)
        XCTAssertTrue(blank.groups.isEmpty)
        XCTAssertTrue(missingProject.results.isEmpty)
        XCTAssertTrue(missingProject.groups.isEmpty)
    }

    private func write(_ contents: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }
}
