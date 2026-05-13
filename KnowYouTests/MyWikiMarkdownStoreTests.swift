import XCTest
@testable import KnowYou

final class MyWikiMarkdownStoreTests: XCTestCase {
    func testLoadsDashboardSnapshotFromMarkdownFolders() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: root.appending(path: "wiki/people"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appending(path: "wiki/projects"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appending(path: "wiki/themes"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appending(path: "wiki/summaries"), withIntermediateDirectories: true)

        try """
        ---
        type: person
        title: Alex
        sources: ["knowyou-diary-2026-05-12.md"]
        ---

        # Alex

        最近一起讨论 My Wiki 的产品轻量化。
        """.write(to: root.appending(path: "wiki/people/alex.md"), atomically: true, encoding: .utf8)

        try """
        ---
        type: project
        title: KnowYou
        sources: ["knowyou-diary-2026-05-12.md"]
        ---

        # KnowYou

        从日记工具升级为个人 My Wiki。
        """.write(to: root.appending(path: "wiki/projects/knowyou.md"), atomically: true, encoding: .utf8)

        let snapshot = try MyWikiMarkdownStore(fileManager: .default).loadDashboard(projectRoot: root)

        XCTAssertEqual(snapshot.people.map(\.title), ["Alex"])
        XCTAssertEqual(snapshot.projects.map(\.title), ["KnowYou"])
        XCTAssertTrue(snapshot.people[0].summary.contains("产品轻量化"))
        XCTAssertEqual(snapshot.people[0].sourceNames, ["knowyou-diary-2026-05-12.md"])
    }
}
