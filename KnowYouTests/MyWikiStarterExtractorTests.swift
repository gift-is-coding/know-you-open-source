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
        黄山在会议里澄清了平台认证和硬件加速边界。

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
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appending(path: "wiki/people/codex.md").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appending(path: "wiki/themes/product-simplification.md").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appending(path: "wiki/preferences/prefer-lightweight-ux.md").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appending(path: "wiki/open-loops/recent-open-loops.md").path))

        let snapshot = try MyWikiMarkdownStore().loadDashboard(projectRoot: root)
        XCTAssertEqual(snapshot.summaries.first?.title, "Recent Journal Summary")
        XCTAssertTrue(snapshot.people.map(\.title).contains("Huang Shan"))
        XCTAssertFalse(snapshot.people.map(\.title).contains("Codex"))
        XCTAssertTrue(snapshot.projects.map(\.title).contains("KnowYou"))
        XCTAssertTrue(snapshot.themes.map(\.title).contains("Product Simplicity"))
        XCTAssertTrue(snapshot.preferences.map(\.title).contains("Prefer Lightweight UX"))
        XCTAssertEqual(snapshot.preferences.first { $0.id == "prefer-lightweight-ux" }?.sourceNames, ["knowyou-diary-2026-05-13.md"])
        XCTAssertTrue(snapshot.openLoops.first?.summary.contains("继续用 GUI 测试") == true)

        let huangShan = try String(contentsOf: root.appending(path: "wiki/people/huang-shan.md"), encoding: .utf8)
        XCTAssertTrue(huangShan.contains("黄山在会议里澄清了平台认证和硬件加速边界"))
        XCTAssertTrue(huangShan.contains("Keep this page separate from tools, projects, topics, patterns, and events"))
    }

    func testMaterializeKeepsOntologyTypesSeparate() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        let rawSources = root.appending(path: "raw/sources", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: rawSources, withIntermediateDirectories: true)
        try """
        # 2026-05-12

        Shuo Zhou asked whether I would set up a Project10 meeting so everyone could sync on BMS.
        Johnson proposed a 3:30 start, and Vivian Sun forwarded the BMS meeting.
        I asked Codex and Claude to help compare Cloud Code CLI slicing, but they are tools, not people.
        The 擎天5.0加速项目启动会 appeared in Outlook, and the team discussed project-management methods.
        - [ ] Follow up on the BMS meeting notes.
        """.write(
            to: rawSources.appending(path: "knowyou-diary-2026-05-12.md"),
            atomically: true,
            encoding: .utf8
        )

        try MyWikiStarterExtractor().materialize(projectRoot: root)

        let snapshot = try MyWikiMarkdownStore().loadDashboard(projectRoot: root)
        XCTAssertTrue(snapshot.people.map(\.title).contains("Shuo Zhou"))
        XCTAssertTrue(snapshot.people.map(\.title).contains("Johnson"))
        XCTAssertFalse(snapshot.people.map(\.title).contains("Codex"))
        XCTAssertFalse(snapshot.people.map(\.title).contains("Claude"))
        XCTAssertTrue(snapshot.projects.map(\.title).contains("Project10 BMS Coordination"))
        XCTAssertTrue(snapshot.events.map(\.title).contains("BMS Meeting"))
        XCTAssertTrue(snapshot.events.map(\.title).contains("Qingtian 5.0 Launch Meeting"))
    }

    func testMaterializeReadsLegacyWikiSourcesAsDiaryInputs() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        let rawSources = root.appending(path: "raw/sources", directoryHint: .isDirectory)
        let legacySources = root.appending(path: "wiki/sources", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: rawSources, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: legacySources, withIntermediateDirectories: true)

        try "# 2026-05-13\n\nKnowYou should keep the wiki readable.".write(
            to: rawSources.appending(path: "knowyou-diary-2026-05-13.md"),
            atomically: true,
            encoding: .utf8
        )
        try "# 2026-05-14\n\nThe BMS meeting should be captured as an event, not as a person or preference.".write(
            to: legacySources.appending(path: "knowyou-diary-2026-05-14.md"),
            atomically: true,
            encoding: .utf8
        )

        try MyWikiStarterExtractor().materialize(projectRoot: root)

        let snapshot = try MyWikiMarkdownStore().loadDashboard(projectRoot: root)
        XCTAssertTrue(snapshot.events.map(\.title).contains("BMS Meeting"))
        XCTAssertEqual(snapshot.summaries.first?.summary.contains("2 journal files"), true)
    }

    func testMaterializeRemovesStaleStarterGeneratedToolPages() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        let rawSources = root.appending(path: "raw/sources", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: rawSources, withIntermediateDirectories: true)
        try "# 2026-05-15\n\nKnowYou needs My Wiki to organize journals.".write(
            to: rawSources.appending(path: "knowyou-diary-2026-05-15.md"),
            atomically: true,
            encoding: .utf8
        )

        let people = root.appending(path: "wiki/people", directoryHint: .isDirectory)
        let projects = root.appending(path: "wiki/projects", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: people, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
        try staleStarterPage(type: "person", title: "Codex").write(
            to: people.appending(path: "codex.md"),
            atomically: true,
            encoding: .utf8
        )
        try staleStarterPage(type: "project", title: "Claude / Cowork").write(
            to: projects.appending(path: "claude-cowork.md"),
            atomically: true,
            encoding: .utf8
        )

        try MyWikiStarterExtractor().materialize(projectRoot: root)

        XCTAssertFalse(FileManager.default.fileExists(atPath: people.appending(path: "codex.md").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: projects.appending(path: "claude-cowork.md").path))
    }

    func testMaterializeNormalizesLegacyEntityConceptFrontmatterByFolder() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        let rawSources = root.appending(path: "raw/sources", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: rawSources, withIntermediateDirectories: true)
        try "# 2026-05-15\n\nKnowYou needs My Wiki.".write(
            to: rawSources.appending(path: "knowyou-diary-2026-05-15.md"),
            atomically: true,
            encoding: .utf8
        )

        let themes = root.appending(path: "wiki/themes", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: themes, withIntermediateDirectories: true)
        try """
        ---
        type: concept
        title: Demo Readiness
        ---

        # Demo Readiness
        """.write(to: themes.appending(path: "demo-readiness.md"), atomically: true, encoding: .utf8)

        try MyWikiStarterExtractor().materialize(projectRoot: root)

        let migrated = try String(contentsOf: themes.appending(path: "demo-readiness.md"), encoding: .utf8)
        XCTAssertTrue(migrated.contains("type: theme"))
        XCTAssertFalse(migrated.contains("type: concept"))
        XCTAssertTrue(migrated.contains("# Demo Readiness"))
    }

    private func staleStarterPage(type: String, title: String) -> String {
        """
        ---
        type: \(type)
        title: \(title)
        generated_by: KnowYou My Wiki starter extractor
        ---

        # \(title)
        """
    }
}
