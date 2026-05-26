import XCTest
@testable import KnowYou

final class MyWikiProjectExporterTests: XCTestCase {
    func testEnsureProjectCreatesConfigDrivenMyWikiStructureAndReadableSchema() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        try MyWikiProjectExporter().ensureProject(at: root)

        let schemaConfig = try MyWikiSchemaConfig.defaultPersonalContext()
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appending(path: "raw/sources").path))
        for directory in schemaConfig.categories.map(\.directory) {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: root.appending(path: directory).path),
                "Missing \(directory)"
            )
        }

        let schemaJSON = try Data(contentsOf: root.appending(path: "mywiki.schema.json"))
        let decodedSchema = try JSONDecoder().decode(MyWikiSchemaConfig.self, from: schemaJSON)
        XCTAssertEqual(decodedSchema.categories.map(\.id), schemaConfig.categories.map(\.id))

        let schemaMarkdown = try String(contentsOf: root.appending(path: "schema.md"), encoding: .utf8)
        XCTAssertTrue(schemaMarkdown.contains("# My Wiki Schema"))
        XCTAssertTrue(schemaMarkdown.contains("Generated from `mywiki.schema.json`"))
        XCTAssertTrue(schemaMarkdown.contains("Sources"))
        XCTAssertTrue(schemaMarkdown.contains("Entities"))
        XCTAssertTrue(schemaMarkdown.contains("Concepts"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appending(path: "wiki/entities").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appending(path: "wiki/concepts").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appending(path: "wiki/people").path))
        XCTAssertFalse(schemaMarkdown.contains("KNOWYOU_MY_WIKI_OUTPUT_CONTRACT"))
        XCTAssertFalse(schemaMarkdown.contains("Do not write `wiki/entities/`"))
        XCTAssertFalse(schemaMarkdown.contains("知识本体"))

        let purposeMarkdown = try String(contentsOf: root.appending(path: "purpose.md"), encoding: .utf8)
        XCTAssertTrue(purposeMarkdown.contains("Sources"), purposeMarkdown)
        XCTAssertTrue(purposeMarkdown.contains("Entities"), purposeMarkdown)
        XCTAssertTrue(purposeMarkdown.contains("Concepts"), purposeMarkdown)
        XCTAssertFalse(purposeMarkdown.contains("人物、项目、事件、主题、偏好、待办"), purposeMarkdown)

        let overviewMarkdown = try String(contentsOf: root.appending(path: "wiki/overview.md"), encoding: .utf8)
        XCTAssertTrue(overviewMarkdown.contains("Sources"), overviewMarkdown)
        XCTAssertTrue(overviewMarkdown.contains("Entities"), overviewMarkdown)
        XCTAssertTrue(overviewMarkdown.contains("Concepts"), overviewMarkdown)
        XCTAssertFalse(overviewMarkdown.contains("人物、项目、事件、主题、偏好、待办"), overviewMarkdown)
    }

    func testEnsureProjectReplacesKnownLegacyPromptDocuments() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: root.appending(path: "wiki"), withIntermediateDirectories: true)
        try """
        # Project Purpose

        把 KnowYou 的每日上下文沉淀为可查询、可追溯、可被 agent 调用的个人知识本体。

        哪些人、项目、工具和主题反复出现在我的日记里？
        """.write(to: root.appending(path: "purpose.md"), atomically: true, encoding: .utf8)
        try """
        ---
        type: overview
        title: My Wiki Overview
        ---

        # Overview

        这里汇总 KnowYou 日记整理出的人物、项目、事件、主题、偏好、待办和总结。
        """.write(to: root.appending(path: "wiki/overview.md"), atomically: true, encoding: .utf8)

        try MyWikiProjectExporter().ensureProject(at: root)

        let purposeMarkdown = try String(contentsOf: root.appending(path: "purpose.md"), encoding: .utf8)
        let overviewMarkdown = try String(contentsOf: root.appending(path: "wiki/overview.md"), encoding: .utf8)
        XCTAssertTrue(purposeMarkdown.contains("Sources"), purposeMarkdown)
        XCTAssertTrue(overviewMarkdown.contains("Entities"), overviewMarkdown)
        XCTAssertFalse(purposeMarkdown.contains("个人知识本体"), purposeMarkdown)
        XCTAssertFalse(overviewMarkdown.contains("人物、项目、事件、主题、偏好、待办"), overviewMarkdown)
    }

    func testSyncDiariesExportsKnowYouSourceTags() throws {
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
        XCTAssertTrue(exported.contains("tags: [knowyou, diary]"), exported)
    }
}
