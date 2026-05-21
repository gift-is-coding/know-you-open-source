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
            error: StubConnectorError.failed
        )

        let result = await fixture.coordinator.sync(connectors: [failingConnector, goodConnector])

        XCTAssertEqual(result.succeededConnectorInstanceIDs, ["local-main"])
        XCTAssertEqual(result.failedConnectorInstanceIDs, ["notion-main"])
        XCTAssertEqual(result.changedDocumentCount, 1)
        XCTAssertEqual(result.connectorResults.first { $0.connectorInstanceID == "local-main" }?.changedDocumentCount, 1)
        XCTAssertNotNil(result.connectorResults.first { $0.connectorInstanceID == "notion-main" }?.errorMessage)

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
            snapshots: [newerSnapshot, olderSnapshot]
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

    private func makeFixture(now: Date) throws -> CoordinatorFixture {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let store = KnowledgeImportStore(rootDirectory: root, fileManager: .default)
        let databaseWriter = try DatabaseWriter.inMemory()
        let coordinator = KnowledgeImportCoordinator(
            store: store,
            databaseWriter: databaseWriter,
            now: { now }
        )
        return CoordinatorFixture(root: root, databaseWriter: databaseWriter, coordinator: coordinator)
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
}

private struct CoordinatorFixture {
    var root: URL
    var databaseWriter: DatabaseWriter
    var coordinator: KnowledgeImportCoordinator
}

private enum StubConnectorError: Error {
    case failed
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
