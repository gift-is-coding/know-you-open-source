import XCTest
@testable import KnowYou

final class KnowledgeImportDatabaseTests: XCTestCase {
    func testUpsertImportedDocumentUpdatesSameRemoteIdentity() throws {
        let writer = try DatabaseWriter.inMemory()
        let first = makeDocument(remoteID: "remote-1", contentHash: "hash-a", title: "Original")
        let second = makeDocument(remoteID: "remote-1", contentHash: "hash-b", title: "Updated")

        try writer.upsertImportedKnowledgeDocument(first)
        try writer.upsertImportedKnowledgeDocument(second)

        let documents = try writer.fetchImportedKnowledgeDocuments(connectorInstanceID: "local-main")
        XCTAssertEqual(documents.count, 1)
        XCTAssertEqual(documents[0].title, "Updated")
        XCTAssertEqual(documents[0].contentHash, "hash-b")
    }

    func testMarkDeletedRecordsTombstoneWithoutRemovingRow() throws {
        let writer = try DatabaseWriter.inMemory()
        let document = makeDocument(remoteID: "remote-2", contentHash: "hash-c", title: "Deleted")
        try writer.upsertImportedKnowledgeDocument(document)

        let deletedAt = Date(timeIntervalSince1970: 1_779_000_000)
        try writer.markImportedKnowledgeDocumentDeleted(
            connectorInstanceID: "local-main",
            remoteID: "remote-2",
            deletedAt: deletedAt
        )

        let documents = try writer.fetchImportedKnowledgeDocuments(connectorInstanceID: "local-main", includeDeleted: true)
        XCTAssertEqual(documents.count, 1)
        XCTAssertEqual(documents[0].deletedAt, deletedAt)
    }

    private func makeDocument(remoteID: String, contentHash: String, title: String) -> ImportedKnowledgeDocument {
        ImportedKnowledgeDocument(
            id: "local-main:\(remoteID)",
            connectorInstanceID: "local-main",
            connectorID: .localFolderImport,
            remoteID: remoteID,
            title: title,
            sourcePath: "/tmp/\(remoteID).md",
            remoteURL: nil,
            mimeType: "text/markdown",
            contentHash: contentHash,
            remoteUpdatedAt: Date(timeIntervalSince1970: 1_778_000_000),
            firstImportedAt: Date(timeIntervalSince1970: 1_778_000_001),
            lastSyncedAt: Date(timeIntervalSince1970: 1_778_000_002),
            deletedAt: nil,
            localContentPath: "/cache/\(remoteID)/content.md",
            localMetadataPath: "/cache/\(remoteID)/metadata.json",
            normalizationVersion: 1,
            originKind: "local-file"
        )
    }
}
