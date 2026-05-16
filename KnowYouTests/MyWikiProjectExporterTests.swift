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
        for directory in schemaConfig.categories.flatMap(\.directoryCandidates) {
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
        XCTAssertTrue(schemaMarkdown.contains("People"))
        XCTAssertTrue(schemaMarkdown.contains("Organizations"))
        XCTAssertTrue(schemaMarkdown.contains("Decisions"))
        XCTAssertTrue(schemaMarkdown.contains("Follow-ups"))
        XCTAssertFalse(schemaMarkdown.contains("知识本体"))
    }
}
