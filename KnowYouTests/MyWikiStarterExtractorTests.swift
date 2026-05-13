import XCTest
@testable import KnowYou

final class MyWikiStarterExtractorTests: XCTestCase {
    func testMaterializeCreatesReadableMyWikiPagesFromDiarySources() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        let rawSources = root.appending(path: "raw/sources", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: rawSources, withIntermediateDirectories: true)
        try """
        ---
        type: knowyou-diary
        day: 2026-05-13
        ---

        # 2026-05-13

        我觉得现在 My Wiki 方案太重，应该更轻量，让用户先看到总结、搜索和核心概念。

        KnowYou 需要继续把日记整理成项目、主题、偏好和待办，方便 Codex 和 Claude agent 调用。

        - [ ] 继续用 GUI 测试 My Wiki 页面
        """.write(
            to: rawSources.appending(path: "knowyou-diary-2026-05-13.md"),
            atomically: true,
            encoding: .utf8
        )

        let written = try MyWikiStarterExtractor().materialize(projectRoot: root)

        XCTAssertGreaterThanOrEqual(written, 5)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appending(path: "wiki/summaries/recent-diary-summary.md").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appending(path: "wiki/projects/knowyou.md").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appending(path: "wiki/themes/product-simplification.md").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appending(path: "wiki/preferences/recent-preferences.md").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appending(path: "wiki/open-loops/recent-open-loops.md").path))

        let snapshot = try MyWikiMarkdownStore().loadDashboard(projectRoot: root)
        XCTAssertEqual(snapshot.summaries.first?.title, "最近日记总结")
        XCTAssertTrue(snapshot.projects.map(\.title).contains("KnowYou"))
        XCTAssertTrue(snapshot.themes.map(\.title).contains("产品轻量化"))
        XCTAssertEqual(snapshot.preferences.first?.sourceNames, ["knowyou-diary-2026-05-13.md"])
        XCTAssertTrue(snapshot.openLoops.first?.summary.contains("继续用 GUI 测试") == true)
    }
}
