import XCTest
import GRDB
@testable import KnowYou

final class KnowledgeImportDatabaseTests: XCTestCase {
    func testUpsertImportedDocumentUpdatesSameRemoteIdentity() throws {
        let writer = try DatabaseWriter.inMemory()
        let first = makeDocument(remoteID: "remote-1", contentHash: "hash-a", title: "Original")
        let second = makeDocument(
            id: "replacement-id",
            remoteID: "remote-1",
            contentHash: "hash-b",
            title: "Updated",
            firstImportedAt: Date(timeIntervalSince1970: 1_778_000_100)
        )

        try writer.upsertImportedKnowledgeDocument(first)
        try writer.upsertImportedKnowledgeDocument(second)

        let documents = try writer.fetchImportedKnowledgeDocuments(connectorInstanceID: "local-main")
        XCTAssertEqual(documents.count, 1)
        XCTAssertEqual(documents[0].id, first.id)
        XCTAssertEqual(documents[0].title, "Updated")
        XCTAssertEqual(documents[0].contentHash, "hash-b")
        XCTAssertEqual(documents[0].firstImportedAt, first.firstImportedAt)
    }

    func testBatchUpsertImportedDocumentsRollsBackWhenAnyDocumentFails() throws {
        let writer = try DatabaseWriter.inMemory()
        let first = makeDocument(remoteID: "remote-batch-1", contentHash: "hash-a", title: "First")
        let duplicatePrimaryKey = makeDocument(
            id: first.id,
            remoteID: "remote-batch-2",
            contentHash: "hash-b",
            title: "Second"
        )

        XCTAssertThrowsError(try writer.upsertImportedKnowledgeDocuments([first, duplicatePrimaryKey]))

        let documents = try writer.fetchImportedKnowledgeDocuments(connectorInstanceID: "local-main")
        XCTAssertTrue(documents.isEmpty)
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

        let visibleDocuments = try writer.fetchImportedKnowledgeDocuments(connectorInstanceID: "local-main")
        XCTAssertEqual(visibleDocuments.count, 0)

        let deletedDocuments = try writer.fetchImportedKnowledgeDocuments(
            connectorInstanceID: "local-main",
            includeDeleted: true
        )
        XCTAssertEqual(deletedDocuments.count, 1)
        XCTAssertEqual(deletedDocuments[0].deletedAt, deletedAt)
    }

    func testMigrationRepairsLegacyReplacingUniqueKeyWithoutLosingRows() throws {
        let databaseURL = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: databaseURL) }

        let first = makeDocument(remoteID: "remote-3", contentHash: "hash-d", title: "Legacy")
        let replacement = makeDocument(
            id: "replacement-id",
            remoteID: "remote-3",
            contentHash: "hash-e",
            title: "Replacement",
            firstImportedAt: Date(timeIntervalSince1970: 1_778_000_100)
        )
        let legacyQueue = try DatabaseQueue(path: databaseURL.path)
        try legacyQueue.write { db in
            try db.execute(sql: """
                CREATE TABLE knowledge_import_documents (
                    id TEXT PRIMARY KEY,
                    connectorInstanceID TEXT NOT NULL,
                    connectorID TEXT NOT NULL,
                    remoteID TEXT NOT NULL,
                    title TEXT NOT NULL,
                    sourcePath TEXT,
                    remoteURL TEXT,
                    mimeType TEXT NOT NULL,
                    contentHash TEXT NOT NULL,
                    remoteUpdatedAt DATETIME,
                    firstImportedAt DATETIME NOT NULL,
                    lastSyncedAt DATETIME NOT NULL,
                    deletedAt DATETIME,
                    localContentPath TEXT NOT NULL,
                    localMetadataPath TEXT NOT NULL,
                    normalizationVersion INTEGER NOT NULL,
                    originKind TEXT NOT NULL,
                    UNIQUE (connectorInstanceID, remoteID) ON CONFLICT REPLACE
                )
                """)
            try Self.insertImportedKnowledgeDocument(first, into: db)
        }

        let writer = try DatabaseWriter(path: databaseURL.path)
        let repairedQueue = try DatabaseQueue(path: databaseURL.path)
        try repairedQueue.write { db in
            XCTAssertThrowsError(try Self.insertImportedKnowledgeDocument(replacement, into: db))
        }

        let documents = try writer.fetchImportedKnowledgeDocuments(connectorInstanceID: "local-main")
        XCTAssertEqual(documents.count, 1)
        XCTAssertEqual(documents[0].id, first.id)
        XCTAssertEqual(documents[0].firstImportedAt, first.firstImportedAt)
        XCTAssertEqual(documents[0].title, first.title)
    }

    private func makeDocument(
        id: String? = nil,
        remoteID: String,
        contentHash: String,
        title: String,
        firstImportedAt: Date = Date(timeIntervalSince1970: 1_778_000_001)
    ) -> ImportedKnowledgeDocument {
        ImportedKnowledgeDocument(
            id: id ?? "local-main:\(remoteID)",
            connectorInstanceID: "local-main",
            connectorID: .localFolderImport,
            remoteID: remoteID,
            title: title,
            sourcePath: "/tmp/\(remoteID).md",
            remoteURL: nil,
            mimeType: "text/markdown",
            contentHash: contentHash,
            remoteUpdatedAt: Date(timeIntervalSince1970: 1_778_000_000),
            firstImportedAt: firstImportedAt,
            lastSyncedAt: Date(timeIntervalSince1970: 1_778_000_002),
            deletedAt: nil,
            localContentPath: "/cache/\(remoteID)/content.md",
            localMetadataPath: "/cache/\(remoteID)/metadata.json",
            normalizationVersion: 1,
            originKind: "local-file"
        )
    }

    private static func insertImportedKnowledgeDocument(_ document: ImportedKnowledgeDocument, into db: Database) throws {
        try db.execute(
            sql: """
            INSERT INTO knowledge_import_documents
            (id, connectorInstanceID, connectorID, remoteID, title, sourcePath, remoteURL, mimeType, contentHash,
             remoteUpdatedAt, firstImportedAt, lastSyncedAt, deletedAt, localContentPath, localMetadataPath,
             normalizationVersion, originKind)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            arguments: [
                document.id,
                document.connectorInstanceID,
                document.connectorID.rawValue,
                document.remoteID,
                document.title,
                document.sourcePath,
                document.remoteURL,
                document.mimeType,
                document.contentHash,
                document.remoteUpdatedAt,
                document.firstImportedAt,
                document.lastSyncedAt,
                document.deletedAt,
                document.localContentPath,
                document.localMetadataPath,
                document.normalizationVersion,
                document.originKind,
            ]
        )
    }
}
