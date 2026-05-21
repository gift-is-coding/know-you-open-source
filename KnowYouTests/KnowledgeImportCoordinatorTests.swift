import XCTest
@testable import KnowYou

final class KnowledgeImportCoordinatorTests: XCTestCase {
    func testSyncContinuesWhenOneConnectorFailsAndPersistsSuccessfulDocuments() async throws {
        let fixture = try makeFixture(now: Date(timeIntervalSince1970: 1_778_100_000))
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let goodSnapshot = Self.makeSnapshot(
            connectorInstanceID: "local-main",
            connectorID: .localFolderImport,
            remoteID: "docs/good.md",
            title: "Good",
            contentMarkdown: "# Good"
        )
        let goodConnector = StubKnowledgeImportConnector(
            connectorInstanceID: "local-main",
            connectorID: .localFolderImport,
            snapshots: [goodSnapshot]
        )
        let failingConnector = StubKnowledgeImportConnector(
            connectorInstanceID: "notion-main",
            connectorID: .notionImport,
            error: KnowledgeImportConnectorError.unavailable("Notion is unavailable")
        )

        let result = await fixture.coordinator.sync(connectors: [failingConnector, goodConnector])

        XCTAssertEqual(result.succeededConnectorInstanceIDs, ["local-main"])
        XCTAssertEqual(result.failedConnectorInstanceIDs, ["notion-main"])
        XCTAssertEqual(result.changedDocumentCount, 1)
        XCTAssertEqual(result.connectorResults.first { $0.connectorInstanceID == "local-main" }?.changedDocumentCount, 1)
        XCTAssertEqual(
            result.connectorResults.first { $0.connectorInstanceID == "notion-main" }?.errorMessage,
            "Connector unavailable: Notion is unavailable"
        )

        let documents = try fixture.databaseWriter.fetchImportedKnowledgeDocuments(connectorInstanceID: "local-main")
        XCTAssertEqual(documents.map(\.remoteID), ["docs/good.md"])
        XCTAssertEqual(try String(contentsOf: URL(fileURLWithPath: try XCTUnwrap(documents.first).localContentPath), encoding: .utf8), "# Good")
    }

    func testSyncPassesExistingDocumentIntoStoreAndPreservesDatabaseIdentity() async throws {
        let fixture = try makeFixture(now: Date(timeIntervalSince1970: 1_778_100_300))
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let firstImportedAt = Date(timeIntervalSince1970: 1_777_900_000)
        let existingDocument = Self.makeDocument(
            id: "db-row-id",
            connectorInstanceID: "local-main",
            connectorID: .localFolderImport,
            remoteID: "docs/resync.md",
            title: "Old",
            contentHash: "old-hash",
            firstImportedAt: firstImportedAt
        )
        try fixture.databaseWriter.upsertImportedKnowledgeDocument(existingDocument)
        let snapshot = Self.makeSnapshot(
            connectorInstanceID: "local-main",
            connectorID: .localFolderImport,
            remoteID: "docs/resync.md",
            title: "Resynced",
            contentMarkdown: "# Resynced",
            remoteUpdatedAt: Date(timeIntervalSince1970: 1_778_100_250)
        )
        let connector = StubKnowledgeImportConnector(
            connectorInstanceID: "local-main",
            connectorID: .localFolderImport,
            snapshots: [snapshot]
        )

        let result = await fixture.coordinator.sync(connectors: [connector])

        XCTAssertEqual(result.succeededConnectorInstanceIDs, ["local-main"])
        XCTAssertEqual(result.failedConnectorInstanceIDs, [])
        XCTAssertEqual(result.changedDocumentCount, 1)

        let document = try XCTUnwrap(fixture.databaseWriter.fetchImportedKnowledgeDocuments(connectorInstanceID: "local-main").first)
        XCTAssertEqual(document.id, "db-row-id")
        XCTAssertEqual(document.firstImportedAt, firstImportedAt)
        XCTAssertEqual(document.title, "Resynced")
        let metadataDocument = try decodeDocument(atPath: document.localMetadataPath)
        XCTAssertEqual(metadataDocument.id, "db-row-id")
        XCTAssertEqual(metadataDocument.firstImportedAt, firstImportedAt)
        XCTAssertEqual(try String(contentsOf: URL(fileURLWithPath: document.localContentPath), encoding: .utf8), "# Resynced")
    }

    func testSyncRejectsSnapshotWhoseIdentityDoesNotMatchConnector() async throws {
        let fixture = try makeFixture(now: Date(timeIntervalSince1970: 1_778_100_400))
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let mismatchedSnapshot = Self.makeSnapshot(
            connectorInstanceID: "other-local",
            connectorID: .localFolderImport,
            remoteID: "docs/wrong.md",
            title: "Wrong",
            contentMarkdown: "# Wrong"
        )
        let connector = StubKnowledgeImportConnector(
            connectorInstanceID: "local-main",
            connectorID: .localFolderImport,
            snapshots: [mismatchedSnapshot]
        )

        let result = await fixture.coordinator.sync(connectors: [connector])

        XCTAssertEqual(result.succeededConnectorInstanceIDs, [])
        XCTAssertEqual(result.failedConnectorInstanceIDs, ["local-main"])
        XCTAssertEqual(result.changedDocumentCount, 0)
        XCTAssertTrue(try fixture.databaseWriter.fetchImportedKnowledgeDocuments(connectorInstanceID: "local-main").isEmpty)
    }

    func testSyncDoesNotPartiallyUpsertDocumentsWhenLaterStoreSaveFails() async throws {
        let fixture = try makeFixture(now: Date(timeIntervalSince1970: 1_778_100_450))
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let firstSnapshot = Self.makeSnapshot(
            connectorInstanceID: "local-main",
            connectorID: .localFolderImport,
            remoteID: "docs/first.md",
            title: "First",
            contentMarkdown: "# First"
        )
        let failingSnapshot = Self.makeSnapshot(
            connectorInstanceID: "local-main",
            connectorID: .localFolderImport,
            remoteID: "docs/failing.md",
            title: "Failing",
            contentMarkdown: "# Failing"
        )
        let corruptDocument = try fixture.store.save(
            failingSnapshot,
            now: Date(timeIntervalSince1970: 1_778_100_440)
        )
        try Data("{not-json".utf8).write(
            to: URL(fileURLWithPath: corruptDocument.localMetadataPath),
            options: .atomic
        )
        let connector = StubKnowledgeImportConnector(
            connectorInstanceID: "local-main",
            connectorID: .localFolderImport,
            snapshots: [firstSnapshot, failingSnapshot]
        )

        let result = await fixture.coordinator.sync(connectors: [connector])

        XCTAssertEqual(result.succeededConnectorInstanceIDs, [])
        XCTAssertEqual(result.failedConnectorInstanceIDs, ["local-main"])
        XCTAssertEqual(result.changedDocumentCount, 0)
        XCTAssertTrue(try fixture.databaseWriter.fetchImportedKnowledgeDocuments(connectorInstanceID: "local-main").isEmpty)
    }

    func testSyncUsesNewestSnapshotWhenConnectorEmitsDuplicateRemoteIDs() async throws {
        let fixture = try makeFixture(now: Date(timeIntervalSince1970: 1_778_100_500))
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let newerSnapshot = Self.makeSnapshot(
            connectorInstanceID: "local-main",
            connectorID: .localFolderImport,
            remoteID: "docs/duplicate.md",
            title: "Newer",
            contentMarkdown: "# Newer",
            remoteUpdatedAt: Date(timeIntervalSince1970: 1_778_100_450)
        )
        let olderSnapshot = Self.makeSnapshot(
            connectorInstanceID: "local-main",
            connectorID: .localFolderImport,
            remoteID: "docs/duplicate.md",
            title: "Older",
            contentMarkdown: "# Older",
            remoteUpdatedAt: Date(timeIntervalSince1970: 1_778_100_300)
        )
        let connector = StubKnowledgeImportConnector(
            connectorInstanceID: "local-main",
            connectorID: .localFolderImport,
            snapshots: [olderSnapshot, newerSnapshot]
        )

        let result = await fixture.coordinator.sync(connectors: [connector])

        XCTAssertEqual(result.succeededConnectorInstanceIDs, ["local-main"])
        XCTAssertEqual(result.failedConnectorInstanceIDs, [])
        XCTAssertEqual(result.changedDocumentCount, 1)

        let document = try XCTUnwrap(fixture.databaseWriter.fetchImportedKnowledgeDocuments(connectorInstanceID: "local-main").first)
        XCTAssertEqual(document.remoteID, "docs/duplicate.md")
        XCTAssertEqual(document.title, "Newer")
        XCTAssertEqual(document.remoteUpdatedAt, newerSnapshot.remoteUpdatedAt)
        XCTAssertEqual(try String(contentsOf: URL(fileURLWithPath: document.localContentPath), encoding: .utf8), "# Newer")
    }

    func testSyncUsesLastDuplicateWhenRemoteUpdatedAtTiesOrIsNil() async throws {
        let fixture = try makeFixture(now: Date(timeIntervalSince1970: 1_778_100_550))
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let equalRemoteUpdatedAt = Date(timeIntervalSince1970: 1_778_100_500)
        let firstEqualSnapshot = Self.makeSnapshot(
            connectorInstanceID: "local-main",
            connectorID: .localFolderImport,
            remoteID: "docs/equal.md",
            title: "First Equal",
            contentMarkdown: "# First Equal",
            remoteUpdatedAt: equalRemoteUpdatedAt
        )
        let secondEqualSnapshot = Self.makeSnapshot(
            connectorInstanceID: "local-main",
            connectorID: .localFolderImport,
            remoteID: "docs/equal.md",
            title: "Second Equal",
            contentMarkdown: "# Second Equal",
            remoteUpdatedAt: equalRemoteUpdatedAt
        )
        let firstNilSnapshot = Self.makeSnapshot(
            connectorInstanceID: "local-main",
            connectorID: .localFolderImport,
            remoteID: "docs/nil.md",
            title: "First Nil",
            contentMarkdown: "# First Nil",
            remoteUpdatedAt: nil
        )
        let secondNilSnapshot = Self.makeSnapshot(
            connectorInstanceID: "local-main",
            connectorID: .localFolderImport,
            remoteID: "docs/nil.md",
            title: "Second Nil",
            contentMarkdown: "# Second Nil",
            remoteUpdatedAt: nil
        )
        let connector = StubKnowledgeImportConnector(
            connectorInstanceID: "local-main",
            connectorID: .localFolderImport,
            snapshots: [firstEqualSnapshot, secondEqualSnapshot, firstNilSnapshot, secondNilSnapshot]
        )

        let result = await fixture.coordinator.sync(connectors: [connector])

        XCTAssertEqual(result.succeededConnectorInstanceIDs, ["local-main"])
        XCTAssertEqual(result.failedConnectorInstanceIDs, [])
        XCTAssertEqual(result.changedDocumentCount, 2)

        let documents = try fixture.databaseWriter.fetchImportedKnowledgeDocuments(connectorInstanceID: "local-main")
        let documentsByRemoteID = Dictionary(uniqueKeysWithValues: documents.map { ($0.remoteID, $0) })
        let equalDocument = try XCTUnwrap(documentsByRemoteID["docs/equal.md"])
        let nilDocument = try XCTUnwrap(documentsByRemoteID["docs/nil.md"])
        XCTAssertEqual(equalDocument.title, "Second Equal")
        XCTAssertEqual(try String(contentsOf: URL(fileURLWithPath: equalDocument.localContentPath), encoding: .utf8), "# Second Equal")
        XCTAssertEqual(nilDocument.title, "Second Nil")
        XCTAssertNil(nilDocument.remoteUpdatedAt)
        XCTAssertEqual(try String(contentsOf: URL(fileURLWithPath: nilDocument.localContentPath), encoding: .utf8), "# Second Nil")
    }

    func testSyncDoesNotCountUnchangedResyncAsChanged() async throws {
        let fixture = try makeFixture(now: Date(timeIntervalSince1970: 1_778_100_600))
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let snapshot = Self.makeSnapshot(
            connectorInstanceID: "local-main",
            connectorID: .localFolderImport,
            remoteID: "docs/unchanged.md",
            title: "Unchanged",
            contentMarkdown: "# Same",
            remoteUpdatedAt: Date(timeIntervalSince1970: 1_778_100_550)
        )
        let connector = StubKnowledgeImportConnector(
            connectorInstanceID: "local-main",
            connectorID: .localFolderImport,
            snapshots: [snapshot]
        )

        _ = await fixture.coordinator.sync(connectors: [connector])
        let secondResult = await fixture.coordinator.sync(connectors: [connector])

        XCTAssertEqual(secondResult.succeededConnectorInstanceIDs, ["local-main"])
        XCTAssertEqual(secondResult.failedConnectorInstanceIDs, [])
        XCTAssertEqual(secondResult.changedDocumentCount, 0)
        XCTAssertEqual(secondResult.connectorResults.first?.changedDocumentCount, 0)
    }

    func testSyncRehydratesMissingDatabaseRowFromFresherStoreMetadataWithoutCountingChange() async throws {
        let fixture = try makeFixture(now: Date(timeIntervalSince1970: 1_778_100_900))
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let newerSnapshot = Self.makeSnapshot(
            connectorInstanceID: "local-main",
            connectorID: .localFolderImport,
            remoteID: "docs/rehydrate.md",
            title: "Newer",
            contentMarkdown: "# Newer on disk",
            remoteUpdatedAt: Date(timeIntervalSince1970: 1_778_100_800)
        )
        _ = try fixture.store.save(newerSnapshot, now: Date(timeIntervalSince1970: 1_778_100_850))
        let staleSnapshot = Self.makeSnapshot(
            connectorInstanceID: "local-main",
            connectorID: .localFolderImport,
            remoteID: "docs/rehydrate.md",
            title: "Stale",
            contentMarkdown: "# Stale incoming",
            remoteUpdatedAt: Date(timeIntervalSince1970: 1_778_100_700)
        )
        let connector = StubKnowledgeImportConnector(
            connectorInstanceID: "local-main",
            connectorID: .localFolderImport,
            snapshots: [staleSnapshot]
        )

        let result = await fixture.coordinator.sync(connectors: [connector])

        XCTAssertEqual(result.succeededConnectorInstanceIDs, ["local-main"])
        XCTAssertEqual(result.failedConnectorInstanceIDs, [])
        XCTAssertEqual(result.changedDocumentCount, 0)

        let document = try XCTUnwrap(fixture.databaseWriter.fetchImportedKnowledgeDocuments(connectorInstanceID: "local-main").first)
        XCTAssertEqual(document.title, "Newer")
        XCTAssertEqual(document.remoteUpdatedAt, newerSnapshot.remoteUpdatedAt)
        XCTAssertEqual(try String(contentsOf: URL(fileURLWithPath: document.localContentPath), encoding: .utf8), "# Newer on disk")
    }

    private func makeFixture(now: Date) throws -> CoordinatorFixture {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let store = KnowledgeImportStore(rootDirectory: root, fileManager: .default)
        let databaseWriter = try DatabaseWriter.inMemory()
        let coordinator = KnowledgeImportCoordinator(
            store: store,
            databaseWriter: databaseWriter,
            now: { now }
        )
        return CoordinatorFixture(root: root, store: store, databaseWriter: databaseWriter, coordinator: coordinator)
    }

    private static func makeSnapshot(
        connectorInstanceID: String,
        connectorID: KnowledgeConnectorID,
        remoteID: String,
        title: String,
        contentMarkdown: String,
        remoteUpdatedAt: Date? = Date(timeIntervalSince1970: 1_778_000_000)
    ) -> KnowledgeImportSnapshot {
        KnowledgeImportSnapshot(
            connectorInstanceID: connectorInstanceID,
            connectorID: connectorID,
            remoteID: remoteID,
            title: title,
            sourcePath: "/Users/test/\(remoteID)",
            remoteURL: nil,
            mimeType: "text/markdown",
            contentMarkdown: contentMarkdown,
            remoteUpdatedAt: remoteUpdatedAt,
            originKind: "test"
        )
    }

    private static func makeDocument(
        id: String,
        connectorInstanceID: String,
        connectorID: KnowledgeConnectorID,
        remoteID: String,
        title: String,
        contentHash: String,
        firstImportedAt: Date
    ) -> ImportedKnowledgeDocument {
        ImportedKnowledgeDocument(
            id: id,
            connectorInstanceID: connectorInstanceID,
            connectorID: connectorID,
            remoteID: remoteID,
            title: title,
            sourcePath: "/Users/test/\(remoteID)",
            remoteURL: nil,
            mimeType: "text/markdown",
            contentHash: contentHash,
            remoteUpdatedAt: Date(timeIntervalSince1970: 1_778_000_000),
            firstImportedAt: firstImportedAt,
            lastSyncedAt: Date(timeIntervalSince1970: 1_778_000_100),
            deletedAt: nil,
            localContentPath: "/missing/content.md",
            localMetadataPath: "/missing/metadata.json",
            normalizationVersion: 1,
            originKind: "test"
        )
    }

    private func decodeDocument(atPath path: String) throws -> ImportedKnowledgeDocument {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            if let date = Self.iso8601WithFractionalSeconds().date(from: value) ?? Self.iso8601().date(from: value) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO-8601 date: \(value)")
        }
        return try decoder.decode(ImportedKnowledgeDocument.self, from: data)
    }

    private static func iso8601WithFractionalSeconds() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }

    private static func iso8601() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }
}

private struct CoordinatorFixture {
    var root: URL
    var store: KnowledgeImportStore
    var databaseWriter: DatabaseWriter
    var coordinator: KnowledgeImportCoordinator
}

private struct StubKnowledgeImportConnector: KnowledgeImportConnector {
    var connectorInstanceID: String
    var connectorID: KnowledgeConnectorID
    var snapshots: [KnowledgeImportSnapshot]
    var error: Error?

    init(
        connectorInstanceID: String,
        connectorID: KnowledgeConnectorID,
        snapshots: [KnowledgeImportSnapshot] = [],
        error: Error? = nil
    ) {
        self.connectorInstanceID = connectorInstanceID
        self.connectorID = connectorID
        self.snapshots = snapshots
        self.error = error
    }

    func fetchSnapshots() async throws -> [KnowledgeImportSnapshot] {
        if let error {
            throw error
        }
        return snapshots
    }
}
