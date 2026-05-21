import XCTest
@testable import KnowYou

final class KnowledgeImportStoreTests: XCTestCase {
    func testSaveSnapshotWritesContentAndMetadata() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = KnowledgeImportStore(rootDirectory: root, fileManager: .default)
        let snapshot = makeSnapshot(markdown: "# Hello")

        let document = try store.save(snapshot, now: Date(timeIntervalSince1970: 1_778_000_100))

        XCTAssertEqual(try String(contentsOf: URL(fileURLWithPath: document.localContentPath), encoding: .utf8), "# Hello")
        let metadataDocument = try decodeDocument(atPath: document.localMetadataPath)
        XCTAssertEqual(metadataDocument, document)
        XCTAssertEqual(document.contentHash.count, 64)
    }

    func testSaveSnapshotPreservesFirstImportedAtAcrossResync() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = KnowledgeImportStore(rootDirectory: root, fileManager: .default)
        let firstImportedAt = Date(timeIntervalSince1970: 1_778_000_100)
        let secondSyncedAt = Date(timeIntervalSince1970: 1_778_000_200)

        _ = try store.save(makeSnapshot(markdown: "# Hello"), now: firstImportedAt)
        let secondDocument = try store.save(makeSnapshot(markdown: "# Updated"), now: secondSyncedAt)
        let metadataDocument = try decodeDocument(atPath: secondDocument.localMetadataPath)

        XCTAssertEqual(secondDocument.firstImportedAt, firstImportedAt)
        XCTAssertEqual(secondDocument.lastSyncedAt, secondSyncedAt)
        XCTAssertEqual(metadataDocument.firstImportedAt, firstImportedAt)
        XCTAssertEqual(metadataDocument.lastSyncedAt, secondSyncedAt)
        XCTAssertEqual(metadataDocument, secondDocument)
        XCTAssertEqual(
            try String(contentsOf: URL(fileURLWithPath: secondDocument.localContentPath), encoding: .utf8),
            "# Updated"
        )
    }

    func testDocumentIDIsCollisionSafeForColonSeparatedInputs() throws {
        let firstID = KnowledgeImportStore.documentID(connectorInstanceID: "a:b", remoteID: "c")
        let secondID = KnowledgeImportStore.documentID(connectorInstanceID: "a", remoteID: "b:c")

        XCTAssertNotEqual(firstID, secondID)

        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = KnowledgeImportStore(rootDirectory: root, fileManager: .default)
        let firstDocument = try store.save(makeSnapshot(connectorInstanceID: "a:b", remoteID: "c"))
        let secondDocument = try store.save(makeSnapshot(connectorInstanceID: "a", remoteID: "b:c"))
        let firstDirectory = URL(fileURLWithPath: firstDocument.localContentPath).deletingLastPathComponent()
        let secondDirectory = URL(fileURLWithPath: secondDocument.localContentPath).deletingLastPathComponent()

        XCTAssertNotEqual(firstDirectory, secondDirectory)
    }

    func testConnectorInstanceIDIsNotUsedAsRawPathComponent() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = KnowledgeImportStore(rootDirectory: root, fileManager: .default)
        let document = try store.save(makeSnapshot(connectorInstanceID: "local/main"))

        let relativePath = URL(fileURLWithPath: document.localContentPath).pathComponents.dropFirst(root.pathComponents.count)

        XCTAssertFalse(relativePath.contains("local"))
        XCTAssertFalse(relativePath.contains("main"))
        XCTAssertFalse(document.localContentPath.contains("/local/main/"))
    }

    private func makeSnapshot(
        connectorInstanceID: String = "local-main",
        remoteID: String = "docs/readme.md",
        markdown: String = "# Hello"
    ) -> KnowledgeImportSnapshot {
        KnowledgeImportSnapshot(
            connectorInstanceID: connectorInstanceID,
            connectorID: .localFolderImport,
            remoteID: remoteID,
            title: "Readme",
            sourcePath: "/Users/test/docs/readme.md",
            remoteURL: nil,
            mimeType: "text/markdown",
            markdown: markdown,
            remoteUpdatedAt: Date(timeIntervalSince1970: 1_778_000_000),
            originKind: "local-file"
        )
    }

    private func decodeDocument(atPath path: String) throws -> ImportedKnowledgeDocument {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ImportedKnowledgeDocument.self, from: data)
    }
}
