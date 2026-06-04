import XCTest
@testable import KnowYou

final class MyWikiIngestProgressStoreTests: XCTestCase {
    func testLoadsPreviewProgressFromStoppedStatusAndRawSourceCount() throws {
        let root = try makeProjectRoot()
        try writeSources(root: root, names: ["a.md", "b.md", "c.md"])
        try writeStatus(
            root: root,
            """
            {
              "status": "failed",
              "message": "Stopped for preview after ingesting 2/3 source file(s). Existing generated pages are kept.",
              "updatedAt": "2026-05-16T13:56:50.593Z",
              "sourcesProcessed": 2,
              "filesWritten": []
            }
            """
        )

        let progress = try XCTUnwrap(MyWikiIngestProgressStore().load(projectRoot: root))

        XCTAssertEqual(progress.title, "Preview generated")
        XCTAssertEqual(progress.detail, "2/3 sources")
        XCTAssertEqual(progress.fraction, 2.0 / 3.0, accuracy: 0.001)
    }

    func testSucceededStatusWithoutProcessedCountUsesTotalSources() throws {
        let root = try makeProjectRoot()
        try writeSources(root: root, names: ["a.md", "b.md"])
        try writeStatus(
            root: root,
            """
            {
              "status": "succeeded",
              "message": "My Wiki pipeline completed.",
              "updatedAt": "2026-05-16T13:56:50.593Z"
            }
            """
        )

        let progress = try XCTUnwrap(MyWikiIngestProgressStore().load(projectRoot: root))

        XCTAssertEqual(progress.title, "Updated")
        XCTAssertEqual(progress.detail, "2/2 sources")
        XCTAssertEqual(progress.fraction, 1)
    }

    func testStatusTotalOverridesRawSourceCountForPreviewRuns() throws {
        let root = try makeProjectRoot()
        try writeSources(root: root, names: ["a.md", "b.md", "c.md"])
        try writeStatus(
            root: root,
            """
            {
              "status": "running",
              "message": "Ingested 1/2 source file(s).",
              "updatedAt": "2026-05-16T13:56:50.593Z",
              "sourcesProcessed": 1,
              "sourcesTotal": 2,
              "filesWritten": []
            }
            """
        )

        let progress = try XCTUnwrap(MyWikiIngestProgressStore().load(projectRoot: root))

        XCTAssertEqual(progress.title, "Processing sources")
        XCTAssertEqual(progress.detail, "1/2 sources")
        XCTAssertEqual(progress.fraction, 0.5, accuracy: 0.001)
    }

    func testRunningProgressWithoutCountsShowsImmediateGeneratingFeedback() {
        let progress = MyWikiIngestProgress(
            state: .running,
            message: "Starting My Wiki update...",
            updatedAt: nil,
            sourcesProcessed: 0,
            totalSources: 0
        )

        XCTAssertEqual(progress.title, "Generating My Wiki")
        XCTAssertEqual(progress.detail, "Starting My Wiki update...")
        XCTAssertEqual(progress.fraction, 0)
    }

    func testMissingStatusReturnsNil() throws {
        let root = try makeProjectRoot()

        XCTAssertNil(try MyWikiIngestProgressStore().load(projectRoot: root))
    }

    private func makeProjectRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func writeSources(root: URL, names: [String]) throws {
        let sourceRoot = root.appending(path: "raw/sources", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        for name in names {
            try "# \(name)".write(to: sourceRoot.appending(path: name), atomically: true, encoding: .utf8)
        }
    }

    private func writeStatus(root: URL, _ contents: String) throws {
        let statusRoot = root.appending(path: ".llm-wiki", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: statusRoot, withIntermediateDirectories: true)
        try contents.write(to: statusRoot.appending(path: "last-ingest-status.json"), atomically: true, encoding: .utf8)
    }
}
