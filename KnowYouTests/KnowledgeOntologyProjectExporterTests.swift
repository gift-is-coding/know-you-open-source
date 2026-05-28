import XCTest
@testable import KnowYou

final class KnowledgeOntologyProjectExporterTests: XCTestCase {
    func testSyncCreatesMyWikiProjectAndExportsDiarySources() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let vault = root.appending(path: "Vault", directoryHint: .isDirectory)
        let project = root.appending(path: "MyWiki/KnowYouContext", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        try "# 今日总结\n\n- 设计 My Wiki".write(
            to: vault.appending(path: "2026-05-09.md"),
            atomically: true,
            encoding: .utf8
        )
        try "# 今日总结\n\n- 梳理原始资料".write(
            to: vault.appending(path: "2026-05-08.md"),
            atomically: true,
            encoding: .utf8
        )

        let result = try KnowledgeOntologyProjectExporter().syncDiaries(
            sourceVault: vault,
            projectRoot: project
        )

        XCTAssertEqual(result.projectRoot, project)
        XCTAssertEqual(result.exportedFileNames, [
            "knowyou-diary-2026-05-09.md",
            "knowyou-diary-2026-05-08.md"
        ])
        XCTAssertFalse(FileManager.default.fileExists(atPath: project.appending(path: "schema.md").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: project.appending(path: "purpose.md").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: project.appending(path: "mywiki.schema.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: project.appending(path: "wiki/sources").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: project.appending(path: "wiki/entities").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: project.appending(path: "wiki/concepts").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: project.appending(path: "wiki/people").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: project.appending(path: "wiki/projects").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: project.appending(path: "raw/sources").path))

        let exported = try String(
            contentsOf: project.appending(path: "raw/sources/knowyou-diary-2026-05-09.md"),
            encoding: .utf8
        )
        XCTAssertFalse(exported.contains("type: knowyou-diary"))
        XCTAssertFalse(exported.contains("source: KnowYou"))
        XCTAssertFalse(exported.contains("day: 2026-05-09"))
        XCTAssertFalse(exported.contains("tags: [knowyou, diary]"))
        XCTAssertTrue(exported.contains("- 设计 My Wiki"))
    }

    func testSyncOverwritesStableDiarySourceNames() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let vault = root.appending(path: "Vault", directoryHint: .isDirectory)
        let project = root.appending(path: "MyWiki/KnowYouContext", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        let diary = vault.appending(path: "2026-05-09.md")
        try "first".write(to: diary, atomically: true, encoding: .utf8)

        let exporter = KnowledgeOntologyProjectExporter()
        _ = try exporter.syncDiaries(sourceVault: vault, projectRoot: project)
        try "second".write(to: diary, atomically: true, encoding: .utf8)
        _ = try exporter.syncDiaries(sourceVault: vault, projectRoot: project)

        let rawSources = project.appending(path: "raw/sources", directoryHint: .isDirectory)
        let files = try FileManager.default.contentsOfDirectory(
            at: rawSources,
            includingPropertiesForKeys: nil
        )
        XCTAssertEqual(files.map(\.lastPathComponent), ["knowyou-diary-2026-05-09.md"])

        let exported = try String(
            contentsOf: rawSources.appending(path: "knowyou-diary-2026-05-09.md"),
            encoding: .utf8
        )
        XCTAssertTrue(exported.contains("second"))
        XCTAssertFalse(exported.contains("first"))
    }
}
