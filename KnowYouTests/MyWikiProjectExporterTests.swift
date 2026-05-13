import XCTest
@testable import KnowYou

final class MyWikiProjectExporterTests: XCTestCase {
    func testEnsureProjectCreatesMyWikiStructureAndReadableSchema() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        try MyWikiProjectExporter().ensureProject(at: root)

        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appending(path: "raw/sources").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appending(path: "wiki/people").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appending(path: "wiki/projects").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appending(path: "wiki/themes").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appending(path: "wiki/preferences").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appending(path: "wiki/open-loops").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appending(path: "wiki/summaries").path))

        let schema = try String(contentsOf: root.appending(path: "schema.md"), encoding: .utf8)
        XCTAssertTrue(schema.contains("# My Wiki Schema"))
        XCTAssertTrue(schema.contains("人物"))
        XCTAssertTrue(schema.contains("项目"))
        XCTAssertTrue(schema.contains("主题"))
        XCTAssertTrue(schema.contains("偏好"))
        XCTAssertTrue(schema.contains("待办"))
        XCTAssertFalse(schema.contains("知识本体"))
    }
}
