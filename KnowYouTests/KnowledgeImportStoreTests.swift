import CryptoKit
import XCTest
@testable import KnowYou

final class KnowledgeImportStoreTests: XCTestCase {
    func testSaveSnapshotWritesContentAndMetadata() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = KnowledgeImportStore(rootDirectory: root, fileManager: .default)
        let snapshot = Self.makeSnapshot(contentMarkdown: "# Hello")

        let document = try store.save(snapshot, now: Date(timeIntervalSince1970: 1_778_000_100))

        XCTAssertEqual(try String(contentsOf: URL(fileURLWithPath: document.localContentPath), encoding: .utf8), "# Hello")
        let metadataDocument = try decodeDocument(atPath: document.localMetadataPath)
        XCTAssertEqual(metadataDocument, document)
        XCTAssertEqual(document.contentHash, sha256Hex("# Hello"))

        let secondDocument = try store.save(snapshot, now: Date(timeIntervalSince1970: 1_778_000_200))
        XCTAssertEqual(secondDocument.contentHash, document.contentHash)
    }

    func testSaveWithResultReportsFreshWriteAsChanged() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = KnowledgeImportStore(rootDirectory: root, fileManager: .default)

        let result = try store.saveWithResult(
            Self.makeSnapshot(contentMarkdown: "# Hello"),
            now: Date(timeIntervalSince1970: 1_778_000_100)
        )

        XCTAssertTrue(result.didChange)
        XCTAssertEqual(try decodeDocument(atPath: result.document.localMetadataPath), result.document)
    }

    func testSaveWithResultDoesNotReportMetadataOnlyResyncAsChanged() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = KnowledgeImportStore(rootDirectory: root, fileManager: .default)
        let snapshot = Self.makeSnapshot(contentMarkdown: "# Same")
        _ = try store.save(snapshot, now: Date(timeIntervalSince1970: 1_778_000_100))

        let result = try store.saveWithResult(snapshot, now: Date(timeIntervalSince1970: 1_778_000_200))

        XCTAssertFalse(result.didChange)
        XCTAssertEqual(result.document.contentHash, sha256Hex("# Same"))
        XCTAssertEqual(result.document.lastSyncedAt, Date(timeIntervalSince1970: 1_778_000_200))
    }

    func testSaveWithResultDoesNotReportStaleIncomingSnapshotAsChanged() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = KnowledgeImportStore(rootDirectory: root, fileManager: .default)
        let newerSnapshot = Self.makeSnapshot(
            contentMarkdown: "# Newer",
            remoteUpdatedAt: Date(timeIntervalSince1970: 1_778_000_300)
        )
        _ = try store.save(newerSnapshot, now: Date(timeIntervalSince1970: 1_778_000_400))

        let result = try store.saveWithResult(
            Self.makeSnapshot(contentMarkdown: "# Stale", remoteUpdatedAt: Date(timeIntervalSince1970: 1_778_000_200)),
            now: Date(timeIntervalSince1970: 1_778_000_250)
        )

        XCTAssertFalse(result.didChange)
        XCTAssertEqual(result.document.remoteUpdatedAt, newerSnapshot.remoteUpdatedAt)
        XCTAssertEqual(try String(contentsOf: URL(fileURLWithPath: result.document.localContentPath), encoding: .utf8), "# Newer")
    }

    func testSaveWithResultReportsNewerRemoteUpdateAsChangedEvenWhenContentIsUnchanged() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = KnowledgeImportStore(rootDirectory: root, fileManager: .default)
        _ = try store.save(
            Self.makeSnapshot(
                contentMarkdown: "# Same",
                remoteUpdatedAt: Date(timeIntervalSince1970: 1_778_000_100)
            ),
            now: Date(timeIntervalSince1970: 1_778_000_150)
        )

        let result = try store.saveWithResult(
            Self.makeSnapshot(
                contentMarkdown: "# Same",
                remoteUpdatedAt: Date(timeIntervalSince1970: 1_778_000_200)
            ),
            now: Date(timeIntervalSince1970: 1_778_000_250)
        )

        XCTAssertTrue(result.didChange)
        XCTAssertEqual(result.document.contentHash, sha256Hex("# Same"))
        XCTAssertEqual(result.document.remoteUpdatedAt, Date(timeIntervalSince1970: 1_778_000_200))
    }

    func testSaveWithResultReportsTitleOnlyUpdateAsChanged() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = KnowledgeImportStore(rootDirectory: root, fileManager: .default)
        let remoteUpdatedAt = Date(timeIntervalSince1970: 1_778_000_100)
        _ = try store.save(
            Self.makeSnapshot(
                title: "Original",
                contentMarkdown: "# Same",
                remoteUpdatedAt: remoteUpdatedAt
            ),
            now: Date(timeIntervalSince1970: 1_778_000_150)
        )

        let result = try store.saveWithResult(
            Self.makeSnapshot(
                title: "Renamed",
                contentMarkdown: "# Same",
                remoteUpdatedAt: remoteUpdatedAt
            ),
            now: Date(timeIntervalSince1970: 1_778_000_200)
        )

        XCTAssertTrue(result.didChange)
        XCTAssertEqual(result.document.title, "Renamed")
        XCTAssertEqual(result.document.contentHash, sha256Hex("# Same"))
    }

    func testSaveWithResultDoesNotReportInternalNormalizationOnlyUpdateAsChanged() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = KnowledgeImportStore(rootDirectory: root, fileManager: .default)
        let snapshot = Self.makeSnapshot(contentMarkdown: "# Same")
        let original = try store.save(snapshot, now: Date(timeIntervalSince1970: 1_778_000_100))
        try FileManager.default.removeItem(at: URL(fileURLWithPath: original.localMetadataPath))
        let currentDirectory = URL(fileURLWithPath: original.localMetadataPath).deletingLastPathComponent()
        var legacyDocument = original
        legacyDocument.localContentPath = "/legacy/cache/content.md"
        legacyDocument.localMetadataPath = "/legacy/cache/metadata.json"
        legacyDocument.normalizationVersion = 0

        let result = try store.saveWithResult(
            snapshot,
            now: Date(timeIntervalSince1970: 1_778_000_200),
            existingDocument: legacyDocument
        )
        let metadataDocument = try decodeDocument(atPath: result.document.localMetadataPath)

        XCTAssertFalse(result.didChange)
        XCTAssertEqual(result.document.localContentPath, currentDirectory.appending(path: "content.md").path)
        XCTAssertEqual(result.document.localMetadataPath, currentDirectory.appending(path: "metadata.json").path)
        XCTAssertEqual(result.document.normalizationVersion, 1)
        XCTAssertEqual(metadataDocument, result.document)
    }

    func testSaveWithResultReportsClearedDeletionAsChanged() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = KnowledgeImportStore(rootDirectory: root, fileManager: .default)
        let snapshot = Self.makeSnapshot(contentMarkdown: "# Restored")
        let original = try store.save(snapshot, now: Date(timeIntervalSince1970: 1_778_000_100))
        try FileManager.default.removeItem(at: URL(fileURLWithPath: original.localMetadataPath))
        var deletedDocument = original
        deletedDocument.deletedAt = Date(timeIntervalSince1970: 1_778_000_150)

        let result = try store.saveWithResult(
            snapshot,
            now: Date(timeIntervalSince1970: 1_778_000_200),
            existingDocument: deletedDocument
        )

        XCTAssertTrue(result.didChange)
        XCTAssertNil(result.document.deletedAt)
        XCTAssertEqual(result.document.contentHash, original.contentHash)
    }

    func testSaveSnapshotPreservesFirstImportedAtAcrossResync() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = KnowledgeImportStore(rootDirectory: root, fileManager: .default)
        let firstImportedAt = Date(timeIntervalSince1970: 1_778_000_100)
        let secondSyncedAt = Date(timeIntervalSince1970: 1_778_000_200)

        _ = try store.save(Self.makeSnapshot(contentMarkdown: "# Hello"), now: firstImportedAt)
        let secondDocument = try store.save(Self.makeSnapshot(contentMarkdown: "# Updated"), now: secondSyncedAt)
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

    func testSaveSnapshotPreservesFractionalSecondDatesAcrossMetadataFallback() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = KnowledgeImportStore(rootDirectory: root, fileManager: .default)
        let firstImportedAt = Date(timeIntervalSince1970: 1_778_000_100.123)
        let secondSyncedAt = Date(timeIntervalSince1970: 1_778_000_200.789)
        let remoteUpdatedAt = Date(timeIntervalSince1970: 1_778_000_000.456)
        let snapshot = Self.makeSnapshot(remoteUpdatedAt: remoteUpdatedAt)

        _ = try store.save(snapshot, now: firstImportedAt)
        let secondDocument = try store.save(snapshot, now: secondSyncedAt)
        let metadataDocument = try decodeDocument(atPath: secondDocument.localMetadataPath)

        XCTAssertEqual(secondDocument.firstImportedAt.timeIntervalSince1970, firstImportedAt.timeIntervalSince1970, accuracy: 0.000_001)
        XCTAssertEqual(secondDocument.lastSyncedAt.timeIntervalSince1970, secondSyncedAt.timeIntervalSince1970, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(secondDocument.remoteUpdatedAt).timeIntervalSince1970, remoteUpdatedAt.timeIntervalSince1970, accuracy: 0.000_001)
        XCTAssertEqual(metadataDocument.firstImportedAt.timeIntervalSince1970, firstImportedAt.timeIntervalSince1970, accuracy: 0.000_001)
        XCTAssertEqual(metadataDocument.lastSyncedAt.timeIntervalSince1970, secondSyncedAt.timeIntervalSince1970, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(metadataDocument.remoteUpdatedAt).timeIntervalSince1970, remoteUpdatedAt.timeIntervalSince1970, accuracy: 0.000_001)
    }

    func testSaveSnapshotReadsLegacyNonFractionalMetadataDates() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = KnowledgeImportStore(rootDirectory: root, fileManager: .default)
        let legacyFirstImportedAt = Date(timeIntervalSince1970: 1_778_000_100)
        let legacyRemoteUpdatedAt = Date(timeIntervalSince1970: 1_778_000_000)
        let snapshot = Self.makeSnapshot(remoteUpdatedAt: legacyRemoteUpdatedAt)
        let originalDocument = try store.save(snapshot, now: Date(timeIntervalSince1970: 1_778_000_050))
        try legacyMetadata(
            from: originalDocument,
            firstImportedAt: Self.iso8601().string(from: legacyFirstImportedAt),
            lastSyncedAt: Self.iso8601().string(from: Date(timeIntervalSince1970: 1_778_000_130)),
            remoteUpdatedAt: Self.iso8601().string(from: legacyRemoteUpdatedAt)
        )
        .write(to: URL(fileURLWithPath: originalDocument.localMetadataPath), options: .atomic)

        let savedDocument = try store.save(snapshot, now: Date(timeIntervalSince1970: 1_778_000_200), existingDocument: nil)
        let metadataDocument = try decodeDocument(atPath: savedDocument.localMetadataPath)
        let rewrittenMetadata = try metadataDictionary(atPath: savedDocument.localMetadataPath)

        XCTAssertEqual(savedDocument.firstImportedAt, legacyFirstImportedAt)
        XCTAssertEqual(savedDocument.remoteUpdatedAt, legacyRemoteUpdatedAt)
        XCTAssertEqual(metadataDocument.firstImportedAt, legacyFirstImportedAt)
        XCTAssertEqual(metadataDocument.remoteUpdatedAt, legacyRemoteUpdatedAt)
        XCTAssertTrue(try XCTUnwrap(rewrittenMetadata["firstImportedAt"] as? String).contains(".000Z"))
        XCTAssertTrue(try XCTUnwrap(rewrittenMetadata["remoteUpdatedAt"] as? String).contains(".000Z"))
    }

    func testSaveSnapshotUsesExistingDocumentFirstImportedAtWhenMetadataIsMissing() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = KnowledgeImportStore(rootDirectory: root, fileManager: .default)
        let original = try store.save(Self.makeSnapshot(), now: Date(timeIntervalSince1970: 1_778_000_100))
        try FileManager.default.removeItem(at: URL(fileURLWithPath: original.localMetadataPath))
        let dbFirstImportedAt = Date(timeIntervalSince1970: 1_777_999_000)
        var existingDocument = original
        existingDocument.firstImportedAt = dbFirstImportedAt

        let savedDocument = try store.save(
            Self.makeSnapshot(contentMarkdown: "# From DB"),
            now: Date(timeIntervalSince1970: 1_778_000_300),
            existingDocument: existingDocument
        )
        let metadataDocument = try decodeDocument(atPath: savedDocument.localMetadataPath)

        XCTAssertEqual(savedDocument.firstImportedAt, dbFirstImportedAt)
        XCTAssertEqual(metadataDocument.firstImportedAt, dbFirstImportedAt)
        XCTAssertEqual(metadataDocument, savedDocument)
    }

    func testSaveSnapshotExistingDocumentFirstImportedAtWinsOverMetadata() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = KnowledgeImportStore(rootDirectory: root, fileManager: .default)
        let metadataFirstImportedAt = Date(timeIntervalSince1970: 1_778_000_100)
        let dbFirstImportedAt = Date(timeIntervalSince1970: 1_777_999_000)
        let original = try store.save(Self.makeSnapshot(), now: metadataFirstImportedAt)
        var existingDocument = original
        existingDocument.firstImportedAt = dbFirstImportedAt

        let savedDocument = try store.save(
            Self.makeSnapshot(contentMarkdown: "# Existing Wins"),
            now: Date(timeIntervalSince1970: 1_778_000_300),
            existingDocument: existingDocument
        )
        let metadataDocument = try decodeDocument(atPath: savedDocument.localMetadataPath)

        XCTAssertEqual(savedDocument.firstImportedAt, dbFirstImportedAt)
        XCTAssertEqual(metadataDocument.firstImportedAt, dbFirstImportedAt)
        XCTAssertEqual(metadataDocument, savedDocument)
    }

    func testSaveSnapshotPreservesExistingDocumentIDWhenProvided() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = KnowledgeImportStore(rootDirectory: root, fileManager: .default)
        let snapshot = Self.makeSnapshot()
        let computedID = KnowledgeImportStore.documentID(
            connectorInstanceID: snapshot.connectorInstanceID,
            remoteID: snapshot.remoteID
        )
        var existingDocument = try store.save(snapshot, now: Date(timeIntervalSince1970: 1_778_000_100))
        existingDocument.id = "legacy-db-row-id"

        let savedDocument = try store.save(
            Self.makeSnapshot(contentMarkdown: "# Existing ID"),
            now: Date(timeIntervalSince1970: 1_778_000_300),
            existingDocument: existingDocument
        )
        let metadataDocument = try decodeDocument(atPath: savedDocument.localMetadataPath)

        XCTAssertNotEqual(existingDocument.id, computedID)
        XCTAssertEqual(savedDocument.id, existingDocument.id)
        XCTAssertEqual(metadataDocument.id, existingDocument.id)
        XCTAssertEqual(metadataDocument, savedDocument)
    }

    func testSaveSnapshotRejectsMismatchedExistingDocumentIdentity() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = KnowledgeImportStore(rootDirectory: root, fileManager: .default)
        let snapshot = Self.makeSnapshot()
        var existingDocument = try store.save(snapshot, now: Date(timeIntervalSince1970: 1_778_000_100))
        existingDocument.remoteID = "docs/other.md"

        XCTAssertThrowsError(
            try store.save(snapshot, now: Date(timeIntervalSince1970: 1_778_000_200), existingDocument: existingDocument)
        ) { error in
            XCTAssertTrue(String(describing: error).contains("Existing document identity mismatch"))
        }
    }

    func testSaveSnapshotExistingDocumentRecoversCorruptMetadata() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = KnowledgeImportStore(rootDirectory: root, fileManager: .default)
        let original = try store.save(Self.makeSnapshot(), now: Date(timeIntervalSince1970: 1_778_000_100))
        try Data("{not-json".utf8).write(to: URL(fileURLWithPath: original.localMetadataPath), options: .atomic)
        let later = Date(timeIntervalSince1970: 1_778_000_400)

        let savedDocument = try store.save(
            Self.makeSnapshot(contentMarkdown: "# Recovered"),
            now: later,
            existingDocument: original
        )
        let metadataDocument = try decodeDocument(atPath: savedDocument.localMetadataPath)

        XCTAssertEqual(savedDocument.firstImportedAt, original.firstImportedAt)
        XCTAssertEqual(savedDocument.lastSyncedAt, later)
        XCTAssertEqual(metadataDocument, savedDocument)
        XCTAssertEqual(
            try String(contentsOf: URL(fileURLWithPath: savedDocument.localContentPath), encoding: .utf8),
            "# Recovered"
        )
    }

    func testSaveSnapshotSkipsStaleIncomingWhenMetadataIsCorruptAndExistingDocumentIsNewer() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = KnowledgeImportStore(rootDirectory: root, fileManager: .default)
        let original = try store.save(
            Self.makeSnapshot(contentMarkdown: "# Existing Newer", remoteUpdatedAt: Date(timeIntervalSince1970: 1_778_000_300)),
            now: Date(timeIntervalSince1970: 1_778_000_400)
        )
        try Data("{not-json".utf8).write(to: URL(fileURLWithPath: original.localMetadataPath), options: .atomic)
        var existingDocument = original
        existingDocument.id = "db-row-id"
        existingDocument.firstImportedAt = Date(timeIntervalSince1970: 1_777_000_000)

        let returnedDocument = try store.save(
            Self.makeSnapshot(contentMarkdown: "# Incoming Stale", remoteUpdatedAt: Date(timeIntervalSince1970: 1_778_000_200)),
            now: Date(timeIntervalSince1970: 1_778_000_250),
            existingDocument: existingDocument
        )
        let metadataDocument = try decodeDocument(atPath: returnedDocument.localMetadataPath)

        XCTAssertEqual(returnedDocument.id, existingDocument.id)
        XCTAssertEqual(returnedDocument.firstImportedAt, existingDocument.firstImportedAt)
        XCTAssertEqual(returnedDocument.contentHash, original.contentHash)
        XCTAssertEqual(returnedDocument.remoteUpdatedAt, original.remoteUpdatedAt)
        XCTAssertEqual(returnedDocument.lastSyncedAt, original.lastSyncedAt)
        XCTAssertEqual(metadataDocument, returnedDocument)
        XCTAssertEqual(
            try String(contentsOf: URL(fileURLWithPath: returnedDocument.localContentPath), encoding: .utf8),
            "# Existing Newer"
        )
    }

    func testSaveSnapshotRecoversCorruptMetadataWhenIncomingIsNewerThanExistingDocument() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = KnowledgeImportStore(rootDirectory: root, fileManager: .default)
        let original = try store.save(
            Self.makeSnapshot(contentMarkdown: "# Existing Older", remoteUpdatedAt: Date(timeIntervalSince1970: 1_778_000_100)),
            now: Date(timeIntervalSince1970: 1_778_000_200)
        )
        try Data("{not-json".utf8).write(to: URL(fileURLWithPath: original.localMetadataPath), options: .atomic)

        let savedDocument = try store.save(
            Self.makeSnapshot(contentMarkdown: "# Incoming Newer", remoteUpdatedAt: Date(timeIntervalSince1970: 1_778_000_300)),
            now: Date(timeIntervalSince1970: 1_778_000_400),
            existingDocument: original
        )
        let metadataDocument = try decodeDocument(atPath: savedDocument.localMetadataPath)

        XCTAssertEqual(savedDocument.firstImportedAt, original.firstImportedAt)
        XCTAssertEqual(savedDocument.remoteUpdatedAt, Date(timeIntervalSince1970: 1_778_000_300))
        XCTAssertEqual(savedDocument.lastSyncedAt, Date(timeIntervalSince1970: 1_778_000_400))
        XCTAssertEqual(metadataDocument, savedDocument)
        XCTAssertEqual(
            try String(contentsOf: URL(fileURLWithPath: savedDocument.localContentPath), encoding: .utf8),
            "# Incoming Newer"
        )
    }

    func testSaveSnapshotUsesExistingDocumentAsAuthorityWhenMetadataIsMissing() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = KnowledgeImportStore(rootDirectory: root, fileManager: .default)
        let original = try store.save(
            Self.makeSnapshot(contentMarkdown: "# DB Newer", remoteUpdatedAt: Date(timeIntervalSince1970: 1_778_000_300)),
            now: Date(timeIntervalSince1970: 1_778_000_400)
        )
        try FileManager.default.removeItem(at: URL(fileURLWithPath: original.localMetadataPath))
        var existingDocument = original
        existingDocument.id = "db-row-id"
        existingDocument.firstImportedAt = Date(timeIntervalSince1970: 1_777_000_000)

        let returnedDocument = try store.save(
            Self.makeSnapshot(contentMarkdown: "# Incoming Stale", remoteUpdatedAt: Date(timeIntervalSince1970: 1_778_000_200)),
            now: Date(timeIntervalSince1970: 1_778_000_250),
            existingDocument: existingDocument
        )
        let metadataDocument = try decodeDocument(atPath: returnedDocument.localMetadataPath)

        XCTAssertEqual(returnedDocument.id, existingDocument.id)
        XCTAssertEqual(returnedDocument.firstImportedAt, existingDocument.firstImportedAt)
        XCTAssertEqual(returnedDocument.contentHash, original.contentHash)
        XCTAssertEqual(returnedDocument.remoteUpdatedAt, original.remoteUpdatedAt)
        XCTAssertEqual(returnedDocument.lastSyncedAt, original.lastSyncedAt)
        XCTAssertEqual(metadataDocument, returnedDocument)
        XCTAssertEqual(
            try String(contentsOf: URL(fileURLWithPath: returnedDocument.localContentPath), encoding: .utf8),
            "# DB Newer"
        )
    }

    func testSaveSnapshotUsesFresherExistingDocumentOverOlderMetadataForStaleComparison() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = KnowledgeImportStore(rootDirectory: root, fileManager: .default)
        let original = try store.save(
            Self.makeSnapshot(contentMarkdown: "# DB Newer", remoteUpdatedAt: Date(timeIntervalSince1970: 1_778_000_300)),
            now: Date(timeIntervalSince1970: 1_778_000_400)
        )
        var olderMetadata = original
        olderMetadata.contentHash = sha256Hex("# Older Metadata")
        olderMetadata.remoteUpdatedAt = Date(timeIntervalSince1970: 1_778_000_100)
        olderMetadata.lastSyncedAt = Date(timeIntervalSince1970: 1_778_000_200)
        try encodeDocument(olderMetadata).write(to: URL(fileURLWithPath: original.localMetadataPath), options: .atomic)
        var existingDocument = original
        existingDocument.id = "db-row-id"
        existingDocument.firstImportedAt = Date(timeIntervalSince1970: 1_777_000_000)

        let returnedDocument = try store.save(
            Self.makeSnapshot(contentMarkdown: "# Incoming Stale", remoteUpdatedAt: Date(timeIntervalSince1970: 1_778_000_250)),
            now: Date(timeIntervalSince1970: 1_778_000_300),
            existingDocument: existingDocument
        )
        let metadataDocument = try decodeDocument(atPath: returnedDocument.localMetadataPath)

        XCTAssertEqual(returnedDocument.id, existingDocument.id)
        XCTAssertEqual(returnedDocument.firstImportedAt, existingDocument.firstImportedAt)
        XCTAssertEqual(returnedDocument.contentHash, original.contentHash)
        XCTAssertEqual(returnedDocument.remoteUpdatedAt, original.remoteUpdatedAt)
        XCTAssertEqual(returnedDocument.lastSyncedAt, original.lastSyncedAt)
        XCTAssertEqual(metadataDocument, returnedDocument)
        XCTAssertEqual(
            try String(contentsOf: URL(fileURLWithPath: returnedDocument.localContentPath), encoding: .utf8),
            "# DB Newer"
        )
    }

    func testSaveSnapshotUsesFresherMetadataOverOlderExistingDocumentForStaleComparison() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = KnowledgeImportStore(rootDirectory: root, fileManager: .default)
        let original = try store.save(
            Self.makeSnapshot(contentMarkdown: "# Metadata Newer", remoteUpdatedAt: Date(timeIntervalSince1970: 1_778_000_300)),
            now: Date(timeIntervalSince1970: 1_778_000_400)
        )
        var existingDocument = original
        existingDocument.id = "db-row-id"
        existingDocument.firstImportedAt = Date(timeIntervalSince1970: 1_777_000_000)
        existingDocument.remoteUpdatedAt = Date(timeIntervalSince1970: 1_778_000_100)
        existingDocument.lastSyncedAt = Date(timeIntervalSince1970: 1_778_000_200)

        let returnedDocument = try store.save(
            Self.makeSnapshot(contentMarkdown: "# Incoming Stale", remoteUpdatedAt: Date(timeIntervalSince1970: 1_778_000_250)),
            now: Date(timeIntervalSince1970: 1_778_000_300),
            existingDocument: existingDocument
        )
        let metadataDocument = try decodeDocument(atPath: returnedDocument.localMetadataPath)

        XCTAssertEqual(returnedDocument.id, existingDocument.id)
        XCTAssertEqual(returnedDocument.firstImportedAt, existingDocument.firstImportedAt)
        XCTAssertEqual(returnedDocument.contentHash, original.contentHash)
        XCTAssertEqual(returnedDocument.remoteUpdatedAt, original.remoteUpdatedAt)
        XCTAssertEqual(returnedDocument.lastSyncedAt, original.lastSyncedAt)
        XCTAssertEqual(metadataDocument, returnedDocument)
        XCTAssertEqual(
            try String(contentsOf: URL(fileURLWithPath: returnedDocument.localContentPath), encoding: .utf8),
            "# Metadata Newer"
        )
    }

    func testSaveSnapshotWritesStaleMetadataWhenCurrentDirectoryIsAbsent() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = KnowledgeImportStore(rootDirectory: root, fileManager: .default)
        let original = try store.save(
            Self.makeSnapshot(contentMarkdown: "# DB Newer", remoteUpdatedAt: Date(timeIntervalSince1970: 1_778_000_300)),
            now: Date(timeIntervalSince1970: 1_778_000_400)
        )
        let currentDirectory = URL(fileURLWithPath: original.localMetadataPath).deletingLastPathComponent()
        try FileManager.default.removeItem(at: currentDirectory)
        var existingDocument = original
        existingDocument.id = "db-row-id"
        existingDocument.firstImportedAt = Date(timeIntervalSince1970: 1_777_000_000)
        existingDocument.localContentPath = "/legacy/cache/content.md"
        existingDocument.localMetadataPath = "/legacy/cache/metadata.json"

        let returnedDocument = try store.save(
            Self.makeSnapshot(contentMarkdown: "# Incoming Stale", remoteUpdatedAt: Date(timeIntervalSince1970: 1_778_000_200)),
            now: Date(timeIntervalSince1970: 1_778_000_250),
            existingDocument: existingDocument
        )
        let metadataDocument = try decodeDocument(atPath: returnedDocument.localMetadataPath)

        XCTAssertEqual(returnedDocument.id, existingDocument.id)
        XCTAssertEqual(returnedDocument.firstImportedAt, existingDocument.firstImportedAt)
        XCTAssertEqual(returnedDocument.localContentPath, currentDirectory.appending(path: "content.md").path)
        XCTAssertEqual(returnedDocument.localMetadataPath, currentDirectory.appending(path: "metadata.json").path)
        XCTAssertEqual(metadataDocument, returnedDocument)
        XCTAssertTrue(FileManager.default.fileExists(atPath: returnedDocument.localMetadataPath))
        XCTAssertFalse(FileManager.default.fileExists(atPath: returnedDocument.localContentPath))
    }

    func testSaveSnapshotNormalizesCurrentLocalPathsWhenSkippingStaleWrite() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = KnowledgeImportStore(rootDirectory: root, fileManager: .default)
        let original = try store.save(
            Self.makeSnapshot(contentMarkdown: "# Metadata Newer", remoteUpdatedAt: Date(timeIntervalSince1970: 1_778_000_300)),
            now: Date(timeIntervalSince1970: 1_778_000_400)
        )
        let currentDirectory = URL(fileURLWithPath: original.localMetadataPath).deletingLastPathComponent()
        var legacyMetadata = original
        legacyMetadata.localContentPath = "/legacy/cache/content.md"
        legacyMetadata.localMetadataPath = "/legacy/cache/metadata.json"
        try encodeDocument(legacyMetadata).write(to: URL(fileURLWithPath: original.localMetadataPath), options: .atomic)
        var existingDocument = original
        existingDocument.id = "db-row-id"
        existingDocument.firstImportedAt = Date(timeIntervalSince1970: 1_777_000_000)
        existingDocument.localContentPath = "/db/cache/content.md"
        existingDocument.localMetadataPath = "/db/cache/metadata.json"

        let returnedDocument = try store.save(
            Self.makeSnapshot(contentMarkdown: "# Incoming Stale", remoteUpdatedAt: Date(timeIntervalSince1970: 1_778_000_200)),
            now: Date(timeIntervalSince1970: 1_778_000_250),
            existingDocument: existingDocument
        )
        let metadataDocument = try decodeDocument(atPath: returnedDocument.localMetadataPath)

        XCTAssertEqual(returnedDocument.id, existingDocument.id)
        XCTAssertEqual(returnedDocument.firstImportedAt, existingDocument.firstImportedAt)
        XCTAssertEqual(returnedDocument.localContentPath, currentDirectory.appending(path: "content.md").path)
        XCTAssertEqual(returnedDocument.localMetadataPath, currentDirectory.appending(path: "metadata.json").path)
        XCTAssertEqual(metadataDocument, returnedDocument)
    }

    func testSaveSnapshotSkipsOlderRemoteUpdateWhenNewerMetadataExists() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = KnowledgeImportStore(rootDirectory: root, fileManager: .default)
        let newerSnapshot = Self.makeSnapshot(
            contentMarkdown: "# Newer",
            remoteUpdatedAt: Date(timeIntervalSince1970: 1_778_000_200)
        )
        let newerDocument = try store.save(
            newerSnapshot,
            now: Date(timeIntervalSince1970: 1_778_000_300)
        )

        let returnedDocument = try store.save(
            Self.makeSnapshot(
                contentMarkdown: "# Older",
                remoteUpdatedAt: Date(timeIntervalSince1970: 1_778_000_100)
            ),
            now: Date(timeIntervalSince1970: 1_778_000_150)
        )
        let metadataDocument = try decodeDocument(atPath: returnedDocument.localMetadataPath)

        XCTAssertEqual(returnedDocument, newerDocument)
        XCTAssertEqual(metadataDocument, newerDocument)
        XCTAssertEqual(
            try String(contentsOf: URL(fileURLWithPath: returnedDocument.localContentPath), encoding: .utf8),
            "# Newer"
        )
    }

    func testSaveSnapshotSkipsOlderSyncWhenRemoteUpdateIsUnchanged() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = KnowledgeImportStore(rootDirectory: root, fileManager: .default)
        let remoteUpdatedAt = Date(timeIntervalSince1970: 1_778_000_100)
        let newerDocument = try store.save(
            Self.makeSnapshot(contentMarkdown: "# Synced Later", remoteUpdatedAt: remoteUpdatedAt),
            now: Date(timeIntervalSince1970: 1_778_000_300)
        )

        let returnedDocument = try store.save(
            Self.makeSnapshot(contentMarkdown: "# Synced Earlier", remoteUpdatedAt: remoteUpdatedAt),
            now: Date(timeIntervalSince1970: 1_778_000_200)
        )
        let metadataDocument = try decodeDocument(atPath: returnedDocument.localMetadataPath)

        XCTAssertEqual(returnedDocument, newerDocument)
        XCTAssertEqual(metadataDocument.lastSyncedAt, newerDocument.lastSyncedAt)
        XCTAssertEqual(
            try String(contentsOf: URL(fileURLWithPath: returnedDocument.localContentPath), encoding: .utf8),
            "# Synced Later"
        )
    }

    func testSaveSnapshotSkipsNilRemoteUpdateWhenMetadataHasRemoteUpdate() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = KnowledgeImportStore(rootDirectory: root, fileManager: .default)
        let remoteUpdatedAt = Date(timeIntervalSince1970: 1_778_000_100)
        let originalDocument = try store.save(
            Self.makeSnapshot(contentMarkdown: "# Has Remote Date", remoteUpdatedAt: remoteUpdatedAt),
            now: Date(timeIntervalSince1970: 1_778_000_200)
        )

        let returnedDocument = try store.save(
            Self.makeSnapshot(contentMarkdown: "# Missing Remote Date", remoteUpdatedAt: nil),
            now: Date(timeIntervalSince1970: 1_778_000_200)
        )
        let metadataDocument = try decodeDocument(atPath: returnedDocument.localMetadataPath)

        XCTAssertEqual(returnedDocument, originalDocument)
        XCTAssertEqual(metadataDocument.remoteUpdatedAt, remoteUpdatedAt)
        XCTAssertEqual(
            try String(contentsOf: URL(fileURLWithPath: returnedDocument.localContentPath), encoding: .utf8),
            "# Has Remote Date"
        )
    }

    func testSaveSnapshotNormalizesExistingDocumentFieldsWhenSkippingStaleWrite() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = KnowledgeImportStore(rootDirectory: root, fileManager: .default)
        let metadataRemoteUpdatedAt = Date(timeIntervalSince1970: 1_778_000_300)
        let originalDocument = try store.save(
            Self.makeSnapshot(contentMarkdown: "# Metadata Wins", remoteUpdatedAt: metadataRemoteUpdatedAt),
            now: Date(timeIntervalSince1970: 1_778_000_400)
        )
        var nonAuthoritativeMetadata = originalDocument
        nonAuthoritativeMetadata.id = "metadata-legacy-id"
        nonAuthoritativeMetadata.firstImportedAt = Date(timeIntervalSince1970: 1_777_000_000)
        try encodeDocument(nonAuthoritativeMetadata).write(
            to: URL(fileURLWithPath: originalDocument.localMetadataPath),
            options: .atomic
        )
        var existingDocument = originalDocument
        existingDocument.id = "db-authoritative-id"
        existingDocument.firstImportedAt = Date(timeIntervalSince1970: 1_776_000_000)

        let returnedDocument = try store.save(
            Self.makeSnapshot(contentMarkdown: "# Stale Incoming", remoteUpdatedAt: Date(timeIntervalSince1970: 1_778_000_200)),
            now: Date(timeIntervalSince1970: 1_778_000_250),
            existingDocument: existingDocument
        )
        let metadataDocument = try decodeDocument(atPath: returnedDocument.localMetadataPath)

        XCTAssertEqual(returnedDocument.id, existingDocument.id)
        XCTAssertEqual(returnedDocument.firstImportedAt, existingDocument.firstImportedAt)
        XCTAssertEqual(returnedDocument.contentHash, originalDocument.contentHash)
        XCTAssertEqual(returnedDocument.remoteUpdatedAt, metadataRemoteUpdatedAt)
        XCTAssertEqual(metadataDocument, returnedDocument)
        XCTAssertEqual(
            try String(contentsOf: URL(fileURLWithPath: returnedDocument.localContentPath), encoding: .utf8),
            "# Metadata Wins"
        )
    }

    func testDocumentIDIsCollisionSafeForColonSeparatedInputs() throws {
        let firstID = KnowledgeImportStore.documentID(connectorInstanceID: "a:b", remoteID: "c")
        let secondID = KnowledgeImportStore.documentID(connectorInstanceID: "a", remoteID: "b:c")

        XCTAssertNotEqual(firstID, secondID)

        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = KnowledgeImportStore(rootDirectory: root, fileManager: .default)
        let firstDocument = try store.save(Self.makeSnapshot(connectorInstanceID: "a:b", remoteID: "c"))
        let secondDocument = try store.save(Self.makeSnapshot(connectorInstanceID: "a", remoteID: "b:c"))
        let firstDirectory = URL(fileURLWithPath: firstDocument.localContentPath).deletingLastPathComponent()
        let secondDirectory = URL(fileURLWithPath: secondDocument.localContentPath).deletingLastPathComponent()

        XCTAssertNotEqual(firstDirectory, secondDirectory)
    }

    func testConnectorInstanceIDIsNotUsedAsRawPathComponent() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = KnowledgeImportStore(rootDirectory: root, fileManager: .default)
        let document = try store.save(Self.makeSnapshot(connectorInstanceID: "local/main"))

        let relativePath = URL(fileURLWithPath: document.localContentPath).pathComponents.dropFirst(root.pathComponents.count)

        XCTAssertFalse(relativePath.contains("local"))
        XCTAssertFalse(relativePath.contains("main"))
        XCTAssertFalse(document.localContentPath.contains("/local/main/"))
    }

    func testConcurrentSavesProduceReadableMetadata() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let count = 12

        let documents = try await withThrowingTaskGroup(of: ImportedKnowledgeDocument.self) { group in
            for index in 0..<count {
                group.addTask {
                    let store = KnowledgeImportStore(rootDirectory: root, fileManager: .default)
                    return try store.save(
                        Self.makeSnapshot(remoteID: "docs/readme-\(index).md", contentMarkdown: "# Hello \(index)"),
                        now: Date(timeIntervalSince1970: 1_778_000_100 + Double(index))
                    )
                }
            }

            var documents = [ImportedKnowledgeDocument]()
            for try await document in group {
                documents.append(document)
            }
            return documents
        }

        XCTAssertEqual(documents.count, count)
        for document in documents {
            XCTAssertEqual(try decodeDocument(atPath: document.localMetadataPath), document)
        }
    }

    func testConcurrentSavesToSameDocumentIdentitySucceed() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let count = 50
        let baseRemoteUpdatedAt = Date(timeIntervalSince1970: 1_778_000_000)
        let baseSyncedAt = Date(timeIntervalSince1970: 1_778_000_100)

        let documents = try await withThrowingTaskGroup(of: ImportedKnowledgeDocument.self) { group in
            for index in 0..<count {
                group.addTask {
                    let store = KnowledgeImportStore(rootDirectory: root, fileManager: .default)
                    return try store.save(
                        Self.makeSnapshot(
                            contentMarkdown: "# Shared \(index)",
                            remoteUpdatedAt: baseRemoteUpdatedAt.addingTimeInterval(Double(index))
                        ),
                        now: baseSyncedAt.addingTimeInterval(Double(index))
                    )
                }
            }

            var documents = [ImportedKnowledgeDocument]()
            for try await document in group {
                documents.append(document)
            }
            return documents
        }

        XCTAssertEqual(documents.count, count)
        let finalDocument = try decodeDocument(atPath: try XCTUnwrap(documents.last).localMetadataPath)
        XCTAssertEqual(
            try String(contentsOf: URL(fileURLWithPath: finalDocument.localContentPath), encoding: .utf8),
            "# Shared 49"
        )
        XCTAssertEqual(finalDocument.contentHash, sha256Hex("# Shared 49"))
        XCTAssertEqual(finalDocument.remoteUpdatedAt, baseRemoteUpdatedAt.addingTimeInterval(49))
        XCTAssertEqual(finalDocument.lastSyncedAt, baseSyncedAt.addingTimeInterval(49))
    }

    private static func makeSnapshot(
        connectorInstanceID: String = "local-main",
        remoteID: String = "docs/readme.md",
        title: String = "Readme",
        contentMarkdown: String = "# Hello",
        remoteUpdatedAt: Date? = Date(timeIntervalSince1970: 1_778_000_000)
    ) -> KnowledgeImportSnapshot {
        KnowledgeImportSnapshot(
            connectorInstanceID: connectorInstanceID,
            connectorID: .localFolderImport,
            remoteID: remoteID,
            title: title,
            sourcePath: "/Users/test/docs/readme.md",
            remoteURL: nil,
            mimeType: "text/markdown",
            contentMarkdown: contentMarkdown,
            remoteUpdatedAt: remoteUpdatedAt,
            originKind: "local-file"
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

    private func encodeDocument(_ document: ImportedKnowledgeDocument) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(Self.iso8601WithFractionalSeconds().string(from: date))
        }
        return try encoder.encode(document)
    }

    private func metadataDictionary(atPath path: String) throws -> [String: Any] {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func legacyMetadata(
        from document: ImportedKnowledgeDocument,
        firstImportedAt: String,
        lastSyncedAt: String,
        remoteUpdatedAt: String
    ) throws -> Data {
        let metadata: [String: Any] = [
            "id": document.id,
            "connectorInstanceID": document.connectorInstanceID,
            "connectorID": document.connectorID.rawValue,
            "remoteID": document.remoteID,
            "title": document.title,
            "sourcePath": document.sourcePath as Any,
            "remoteURL": document.remoteURL as Any,
            "mimeType": document.mimeType,
            "contentHash": document.contentHash,
            "remoteUpdatedAt": remoteUpdatedAt,
            "firstImportedAt": firstImportedAt,
            "lastSyncedAt": lastSyncedAt,
            "deletedAt": document.deletedAt as Any,
            "localContentPath": document.localContentPath,
            "localMetadataPath": document.localMetadataPath,
            "normalizationVersion": document.normalizationVersion,
            "originKind": document.originKind
        ]
        return try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
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

    private func sha256Hex(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
