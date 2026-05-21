import XCTest
@testable import KnowYou

final class KnowledgeImportStoreTests: XCTestCase {
    func testSaveSnapshotWritesContentAndMetadata() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = KnowledgeImportStore(rootDirectory: root, fileManager: .default)
        let snapshot = KnowledgeImportSnapshot(
            connectorInstanceID: "local-main",
            connectorID: .localFolderImport,
            remoteID: "docs/readme.md",
            title: "Readme",
            sourcePath: "/Users/test/docs/readme.md",
            remoteURL: nil,
            mimeType: "text/markdown",
            markdown: "# Hello",
            remoteUpdatedAt: Date(timeIntervalSince1970: 1_778_000_000),
            originKind: "local-file"
        )

        let document = try store.save(snapshot, now: Date(timeIntervalSince1970: 1_778_000_100))

        XCTAssertEqual(try String(contentsOf: URL(fileURLWithPath: document.localContentPath), encoding: .utf8), "# Hello")
        XCTAssertTrue(FileManager.default.fileExists(atPath: document.localMetadataPath))
        XCTAssertEqual(document.contentHash.count, 64)
    }
}
