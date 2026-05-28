import XCTest
@testable import KnowYou

final class MyWikiProjectExporterTests: XCTestCase {
    func testEnsureProjectCreatesNativeLlmWikiStructureWithoutPromptContext() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        try MyWikiProjectExporter().ensureProject(at: root)

        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appending(path: "raw/sources").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appending(path: "wiki/sources").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appending(path: "wiki/entities").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appending(path: "wiki/concepts").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appending(path: "wiki/people").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appending(path: "wiki/projects").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appending(path: "wiki/topics").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appending(path: "mywiki.schema.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appending(path: "schema.md").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appending(path: "purpose.md").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appending(path: "wiki/overview.md").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appending(path: "wiki/index.md").path))
    }

    func testEnsureProjectRemovesLegacyPromptContextDocuments() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: root.appending(path: "wiki"), withIntermediateDirectories: true)
        try "{}".write(to: root.appending(path: "mywiki.schema.json"), atomically: true, encoding: .utf8)
        try "# My Wiki Schema".write(to: root.appending(path: "schema.md"), atomically: true, encoding: .utf8)
        try """
        # Project Purpose

        把 KnowYou 的每日上下文沉淀为可查询、可追溯、可被 agent 调用的个人知识本体。

        哪些人、项目、工具和主题反复出现在我的日记里？
        """.write(to: root.appending(path: "purpose.md"), atomically: true, encoding: .utf8)
        try "# Native overview from llm_wiki\n".write(to: root.appending(path: "wiki/overview.md"), atomically: true, encoding: .utf8)

        try MyWikiProjectExporter().ensureProject(at: root)

        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appending(path: "mywiki.schema.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appending(path: "schema.md").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appending(path: "purpose.md").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appending(path: "wiki/overview.md").path))
    }

    func testSyncDiariesExportsRawDiaryMarkdownWithoutKnowYouPromptMetadata() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let sourceVault = root.appending(path: "vault", directoryHint: .isDirectory)
        let projectRoot = root.appending(path: "project", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: sourceVault, withIntermediateDirectories: true)
        try """
        # 2026-05-18

        Native llm_wiki schema should keep KnowYou source tags.
        """.write(to: sourceVault.appending(path: "2026-05-18.md"), atomically: true, encoding: .utf8)

        let result = try MyWikiProjectExporter().syncDiaries(sourceVault: sourceVault, projectRoot: projectRoot)

        XCTAssertEqual(result.exportedFileNames, ["knowyou-diary-2026-05-18.md"])
        let exported = try String(
            contentsOf: projectRoot.appending(path: "raw/sources/knowyou-diary-2026-05-18.md"),
            encoding: .utf8
        )
        XCTAssertTrue(exported.contains("# 2026-05-18"), exported)
        XCTAssertTrue(exported.contains("Native llm_wiki schema should keep KnowYou source tags."), exported)
        XCTAssertFalse(exported.contains("type: knowyou-diary"), exported)
        XCTAssertFalse(exported.contains("source: KnowYou"), exported)
        XCTAssertFalse(exported.contains("tags: [knowyou, diary]"), exported)
    }
}
