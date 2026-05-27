import XCTest
@testable import KnowYou

final class MyWikiSourceCatalogBuilderTests: XCTestCase {
    func testDiaryDiscoveryDefaultsIncludedAndUsesMyDiaryRawPath() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let vault = root.appending(path: "vault", directoryHint: .isDirectory)
        let project = root.appending(path: "project", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        try "# Daily\n\nBuilt catalog inputs.".write(
            to: vault.appending(path: "2026-05-27.md"),
            atomically: true,
            encoding: .utf8
        )
        try "ignore".write(to: vault.appending(path: "notes.md"), atomically: true, encoding: .utf8)

        let snapshot = try MyWikiSourceCatalogBuilder().refreshCatalog(
            projectRoot: project,
            sourceVault: vault,
            importedDocuments: []
        )

        let record = try XCTUnwrap(snapshot.records.first)
        XCTAssertEqual(record.sourceID, "diary:2026-05-27")
        XCTAssertEqual(record.sourceKind, .diary)
        XCTAssertEqual(record.relativePath, "My Diary/2026-05-27.md")
        XCTAssertEqual(record.rawSourcePath, "raw/sources/My Diary/knowyou-diary-2026-05-27.md")
        XCTAssertEqual(record.folderContext, "My Diary")
        XCTAssertTrue(record.included)
        XCTAssertEqual(record.contentHash, SHA256Hasher.hash(MyWikiProjectExporter.exportedDiaryMarkdownForCatalog(
            dayKey: "2026-05-27",
            markdown: "# Daily\n\nBuilt catalog inputs."
        )))
    }

    func testExternalDiscoveryDefaultsExcludedAndPreservesHierarchy() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appending(path: "Projects/AI/notes.md")
        try FileManager.default.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "# External".write(to: source, atomically: true, encoding: .utf8)
        let document = importedDocument(
            id: "doc-1",
            connectorInstanceID: "local-main",
            connectorID: .localFolderImport,
            remoteID: "Projects/AI/notes.md",
            title: "notes.md",
            sourcePath: source.path,
            localContentPath: source.path
        )

        let snapshot = try MyWikiSourceCatalogBuilder().refreshCatalog(
            projectRoot: root.appending(path: "project", directoryHint: .isDirectory),
            sourceVault: root.appending(path: "vault", directoryHint: .isDirectory),
            importedDocuments: [document]
        )

        let record = try XCTUnwrap(snapshot.records.first)
        XCTAssertEqual(record.sourceID, "doc-1")
        XCTAssertEqual(record.sourceKind, .externalDocument)
        XCTAssertEqual(record.relativePath, "Local Folder/local-main/Projects/AI/notes.md")
        XCTAssertEqual(record.rawSourcePath, "raw/sources/Local Folder/local-main/Projects/AI/notes.md")
        XCTAssertEqual(record.folderContext, "Local Folder/local-main/Projects/AI")
        XCTAssertFalse(record.included)
    }

    func testManualDiscoveryDefaultsIncludedUnderManualImports() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let manual = root.appending(path: "project/raw/sources/Manual Imports/Projects/AI/manual.txt")
        try FileManager.default.createDirectory(at: manual.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "Manual note".write(to: manual, atomically: true, encoding: .utf8)

        let snapshot = try MyWikiSourceCatalogBuilder().refreshCatalog(
            projectRoot: root.appending(path: "project", directoryHint: .isDirectory),
            sourceVault: root.appending(path: "vault", directoryHint: .isDirectory),
            importedDocuments: []
        )

        let record = try XCTUnwrap(snapshot.records.first)
        XCTAssertEqual(record.sourceID, "manual:Manual Imports/Projects/AI/manual.txt")
        XCTAssertEqual(record.sourceKind, .manualFile)
        XCTAssertEqual(record.relativePath, "Manual Imports/Projects/AI/manual.txt")
        XCTAssertEqual(record.rawSourcePath, "raw/sources/Manual Imports/Projects/AI/manual.txt")
        XCTAssertEqual(record.folderContext, "Manual Imports/Projects/AI")
        XCTAssertTrue(record.included)
    }

    func testIngestPlanOnlyIncludesPendingChangedAndFailedIncludedSources() throws {
        let pending = catalogRecord(sourceID: "pending", included: true, contentHash: "hash-pending")
        var changed = catalogRecord(sourceID: "changed", included: true, contentHash: "hash-new")
        changed.lastIndexedHash = "hash-old"
        var failed = catalogRecord(sourceID: "failed", included: true, contentHash: "hash-failed")
        failed.lastIndexedHash = "hash-failed"
        failed.lastIngestError = "Prompt failed"
        var indexed = catalogRecord(sourceID: "indexed", included: true, contentHash: "hash-indexed")
        indexed.lastIndexedHash = "hash-indexed"
        let excluded = catalogRecord(sourceID: "excluded", included: false, contentHash: "hash-excluded")
        let snapshot = MyWikiSourceCatalogSnapshot(records: [indexed, excluded, failed, changed, pending])

        let plan = MyWikiSourceCatalogBuilder().ingestPlan(snapshot: snapshot, maxSources: 2)
        let emptyPlan = MyWikiSourceCatalogBuilder().ingestPlan(snapshot: snapshot, maxSources: 0)

        XCTAssertEqual(plan.sources.map(\.sourceID), ["changed", "failed"])
        XCTAssertEqual(emptyPlan.sources, [])
    }

    func testMaterializeWritesNestedSourcesAndManifest() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let project = root.appending(path: "project", directoryHint: .isDirectory)
        let external = root.appending(path: "external/Projects/AI/notes.md")
        try FileManager.default.createDirectory(at: external.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "# External\n\nNested source.".write(to: external, atomically: true, encoding: .utf8)
        let record = catalogRecord(
            sourceID: "doc-1",
            included: true,
            contentHash: "hash-doc",
            relativePath: "Local Folder/local-main/Projects/AI/notes.md",
            sourcePath: external.path,
            rawSourcePath: "raw/sources/Local Folder/local-main/Projects/AI/notes.md",
            folderContext: "Local Folder/local-main/Projects/AI",
            sourceKind: .externalDocument
        )
        let snapshot = MyWikiSourceCatalogSnapshot(records: [record])
        let plan = MyWikiSourceCatalogBuilder().ingestPlan(snapshot: snapshot, maxSources: nil)

        let result = try MyWikiSourceCatalogBuilder().materialize(
            plan: plan,
            from: snapshot,
            projectRoot: project
        )

        XCTAssertEqual(result.materializedCount, 1)
        XCTAssertEqual(result.manifestURL, project.appending(path: ".knowyou/ingest-manifest.json"))
        let copied = try String(
            contentsOf: project.appending(path: "raw/sources/Local Folder/local-main/Projects/AI/notes.md"),
            encoding: .utf8
        )
        XCTAssertEqual(copied, "# External\n\nNested source.")

        let manifestData = try Data(contentsOf: result.manifestURL)
        let manifest = try JSONDecoder.knowledgeImport().decode(MyWikiSourceIngestPlan.self, from: manifestData)
        XCTAssertEqual(manifest.sources.map(\.sourceID), ["doc-1"])
        XCTAssertEqual(manifest.sources.first?.folderContext, "Local Folder/local-main/Projects/AI")
        XCTAssertEqual(manifest.sources.first?.sourcePath, "raw/sources/Local Folder/local-main/Projects/AI/notes.md")
    }

    func testMaterializeLeavesManualSourceInPlaceWhenAlreadyUnderRawSources() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let project = root.appending(path: "project", directoryHint: .isDirectory)
        let manual = project.appending(path: "raw/sources/Manual Imports/Projects/AI/manual.md")
        try FileManager.default.createDirectory(at: manual.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "# Manual\n\nAlready materialized.".write(to: manual, atomically: true, encoding: .utf8)
        let record = catalogRecord(
            sourceID: "manual:Manual Imports/Projects/AI/manual.md",
            included: true,
            contentHash: "hash-manual",
            relativePath: "Manual Imports/Projects/AI/manual.md",
            sourcePath: manual.path,
            rawSourcePath: "raw/sources/Manual Imports/Projects/AI/manual.md",
            folderContext: "Manual Imports/Projects/AI",
            sourceKind: .manualFile
        )
        let snapshot = MyWikiSourceCatalogSnapshot(records: [record])
        let plan = MyWikiSourceCatalogBuilder().ingestPlan(snapshot: snapshot, maxSources: nil)

        _ = try MyWikiSourceCatalogBuilder().materialize(
            plan: plan,
            from: snapshot,
            projectRoot: project
        )

        let preserved = try String(contentsOf: manual, encoding: .utf8)
        XCTAssertEqual(preserved, "# Manual\n\nAlready materialized.")
    }

    func testMarkSuccessAndFailureCheckpointBehavior() throws {
        let date = Date(timeIntervalSince1970: 1_779_000_000)
        var previous = catalogRecord(sourceID: "previous", included: true, contentHash: "hash-current")
        previous.lastIndexedHash = "hash-old"
        previous.lastIndexedAt = Date(timeIntervalSince1970: 1_778_000_000)
        let snapshot = MyWikiSourceCatalogSnapshot(records: [previous])
        let plan = MyWikiSourceCatalogBuilder().ingestPlan(snapshot: snapshot, maxSources: nil)

        let succeeded = MyWikiSourceCatalogBuilder().mark(plan: plan, succeededIn: snapshot, at: date)

        XCTAssertEqual(succeeded.records[0].lastIndexedHash, "hash-current")
        XCTAssertEqual(succeeded.records[0].lastIndexedAt, date)
        XCTAssertNil(succeeded.records[0].lastIngestError)
        XCTAssertEqual(succeeded.records[0].wikiSummaryPath, "wiki/sources/previous.md")

        let failed = MyWikiSourceCatalogBuilder().mark(
            plan: plan,
            failedWith: "Ingest failed",
            in: snapshot
        )

        XCTAssertEqual(failed.records[0].lastIndexedHash, "hash-old")
        XCTAssertEqual(failed.records[0].lastIndexedAt, Date(timeIntervalSince1970: 1_778_000_000))
        XCTAssertEqual(failed.records[0].lastIngestError, "Ingest failed")
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func importedDocument(
        id: String,
        connectorInstanceID: String,
        connectorID: KnowledgeConnectorID,
        remoteID: String,
        title: String,
        sourcePath: String?,
        localContentPath: String,
        deletedAt: Date? = nil
    ) -> ImportedKnowledgeDocument {
        ImportedKnowledgeDocument(
            id: id,
            connectorInstanceID: connectorInstanceID,
            connectorID: connectorID,
            remoteID: remoteID,
            title: title,
            sourcePath: sourcePath,
            remoteURL: nil,
            mimeType: "text/markdown",
            contentHash: "hash-\(id)",
            remoteUpdatedAt: nil,
            firstImportedAt: Date(timeIntervalSince1970: 1_778_000_000),
            lastSyncedAt: Date(timeIntervalSince1970: 1_778_000_100),
            deletedAt: deletedAt,
            localContentPath: localContentPath,
            localMetadataPath: "/tmp/\(id).json",
            normalizationVersion: 1,
            originKind: "test"
        )
    }

    private func catalogRecord(
        sourceID: String,
        included: Bool,
        contentHash: String,
        relativePath: String? = nil,
        sourcePath: String? = nil,
        rawSourcePath: String? = nil,
        folderContext: String? = nil,
        sourceKind: MyWikiSourceKind = .externalDocument
    ) -> MyWikiSourceCatalogRecord {
        let path = relativePath ?? "\(sourceID).md"
        return MyWikiSourceCatalogRecord(
            sourceID: sourceID,
            sourceKind: sourceKind,
            connectorInstanceID: nil,
            connectorID: nil,
            displayTitle: sourceID,
            relativePath: path,
            sourcePath: sourcePath,
            sourceURL: nil,
            contentHash: contentHash,
            remoteUpdatedAt: nil,
            included: included,
            includedDefault: included,
            lastIndexedHash: nil,
            lastIndexedAt: nil,
            lastIngestError: nil,
            rawSourcePath: rawSourcePath ?? "raw/sources/\(path)",
            wikiSummaryPath: nil,
            folderContext: folderContext ?? String(path.split(separator: "/").dropLast().joined(separator: "/"))
        )
    }
}
