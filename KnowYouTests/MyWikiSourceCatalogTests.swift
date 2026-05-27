import XCTest
@testable import KnowYou

final class MyWikiSourceCatalogTests: XCTestCase {
    func testNewDiaryDefaultsIncludedAndPending() throws {
        let candidate = MyWikiSourceCandidate(
            sourceID: "diary:2026-05-27",
            sourceKind: .diary,
            connectorInstanceID: nil,
            connectorID: nil,
            displayTitle: "2026-05-27",
            relativePath: "2026-05-27.md",
            sourcePath: "/tmp/vault/2026-05-27.md",
            sourceURL: nil,
            contentHash: "hash-a",
            remoteUpdatedAt: nil,
            defaultIncluded: true,
            materializedRelativePath: "knowyou-diary-2026-05-27.md",
            folderContext: "My Diary"
        )

        let snapshot = MyWikiSourceCatalogStore.emptySnapshot().merged(with: [candidate])

        XCTAssertEqual(snapshot.records.count, 1)
        XCTAssertEqual(snapshot.records[0].included, true)
        XCTAssertEqual(snapshot.records[0].status, .pending)
    }

    func testExternalDefaultsExcludedAndNotIncluded() throws {
        let candidate = MyWikiSourceCandidate(
            sourceID: "ci:local|remote:docs/spec.md",
            sourceKind: .externalDocument,
            connectorInstanceID: "local-main",
            connectorID: .localFolderImport,
            displayTitle: "spec.md",
            relativePath: "Projects/spec.md",
            sourcePath: "/tmp/Projects/spec.md",
            sourceURL: nil,
            contentHash: "hash-b",
            remoteUpdatedAt: nil,
            defaultIncluded: false,
            materializedRelativePath: "local-main/Projects/spec.md",
            folderContext: "Projects"
        )

        let snapshot = MyWikiSourceCatalogStore.emptySnapshot().merged(with: [candidate])

        XCTAssertEqual(snapshot.records[0].included, false)
        XCTAssertEqual(snapshot.records[0].status, .notIncluded)
    }

    func testExistingChoiceAndCheckpointSurviveCandidateRefresh() throws {
        var snapshot = MyWikiSourceCatalogStore.emptySnapshot().merged(with: [
            MyWikiSourceCandidate.fixture(
                sourceID: "diary:2026-05-27",
                sourceKind: .diary,
                defaultIncluded: true,
                contentHash: "hash-a"
            )
        ])
        snapshot.records[0].included = false
        snapshot.records[0].lastIndexedHash = "hash-a"
        snapshot.records[0].lastIndexedAt = Date(timeIntervalSince1970: 100)

        let refreshed = snapshot.merged(with: [
            MyWikiSourceCandidate.fixture(
                sourceID: "diary:2026-05-27",
                sourceKind: .diary,
                defaultIncluded: true,
                contentHash: "hash-b"
            )
        ])

        XCTAssertEqual(refreshed.records[0].included, false)
        XCTAssertEqual(refreshed.records[0].lastIndexedHash, "hash-a")
        XCTAssertEqual(refreshed.records[0].lastIndexedAt, Date(timeIntervalSince1970: 100))
        XCTAssertEqual(refreshed.records[0].contentHash, "hash-b")
        XCTAssertEqual(refreshed.records[0].status, .excludedIndexed)
    }

    func testMissingUnindexedRecordsAreDroppedOnMerge() throws {
        var snapshot = MyWikiSourceCatalogStore.emptySnapshot()
        snapshot.records = [
            MyWikiSourceCatalogRecord.fixture(
                sourceID: "external:stale",
                included: true,
                relativePath: "Projects/stale.md"
            )
        ]

        let refreshed = snapshot.merged(with: [])

        XCTAssertTrue(refreshed.records.isEmpty)
    }

    func testMissingIndexedRecordsAreRetainedOnMerge() throws {
        var indexedRecord = MyWikiSourceCatalogRecord.fixture(
            sourceID: "external:indexed",
            included: false,
            relativePath: "Projects/indexed.md"
        )
        indexedRecord.lastIndexedHash = "hash-indexed"
        indexedRecord.lastIndexedAt = Date(timeIntervalSince1970: 200)

        var snapshot = MyWikiSourceCatalogStore.emptySnapshot()
        snapshot.records = [indexedRecord]

        let refreshed = snapshot.merged(with: [])

        XCTAssertEqual(refreshed.records, [indexedRecord])
        XCTAssertEqual(refreshed.records[0].included, false)
        XCTAssertEqual(refreshed.records[0].lastIndexedHash, "hash-indexed")
        XCTAssertEqual(refreshed.records[0].lastIndexedAt, Date(timeIntervalSince1970: 200))
    }

    func testChangedIncludedSourceReportsChanged() throws {
        var record = MyWikiSourceCatalogRecord.fixture(
            sourceID: "diary:2026-05-27",
            included: true,
            contentHash: "hash-b"
        )
        record.lastIndexedHash = "hash-a"

        XCTAssertEqual(record.status, .changed)
    }

    func testDirectorySelectionReportsMixedWhenChildrenDiffer() throws {
        let records = [
            MyWikiSourceCatalogRecord.fixture(
                sourceID: "external:a",
                included: true,
                relativePath: "Projects/A/a.md"
            ),
            MyWikiSourceCatalogRecord.fixture(
                sourceID: "external:b",
                included: false,
                relativePath: "Projects/A/b.md"
            )
        ]

        let tree = MyWikiSourceCatalogTreeBuilder().build(records: records)
        let projects = try XCTUnwrap(tree.children.first { $0.title == "Projects" })
        let folderA = try XCTUnwrap(projects.children.first { $0.title == "A" })

        XCTAssertEqual(folderA.selectionState, .mixed)
    }

    func testStoreRoundTripsCatalogJSON() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = MyWikiSourceCatalogStore(projectRoot: root)
        var snapshot = MyWikiSourceCatalogStore.emptySnapshot()
        snapshot.records = [
            MyWikiSourceCatalogRecord.fixture(
                sourceID: "diary:2026-05-27",
                included: true,
                relativePath: "2026-05-27.md"
            )
        ]

        try store.save(snapshot)
        let loaded = try store.load()

        XCTAssertEqual(loaded.records, snapshot.records)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appending(path: ".knowyou/source-catalog.json").path))
    }

    func testStoreUpdateLoadsMutatesSavesAndReturnsSnapshot() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = MyWikiSourceCatalogStore(projectRoot: root)
        try store.save(MyWikiSourceCatalogSnapshot(records: [
            MyWikiSourceCatalogRecord.fixture(
                sourceID: "diary:2026-05-27",
                included: true,
                relativePath: "2026-05-27.md"
            )
        ]))

        let returned = try store.update { snapshot in
            snapshot.records[0].included = false
            snapshot.records[0].lastIndexedHash = "hash-a"
        }

        let loaded = try store.load()
        XCTAssertEqual(returned.records, loaded.records)
        XCTAssertEqual(loaded.records[0].included, false)
        XCTAssertEqual(loaded.records[0].lastIndexedHash, "hash-a")
    }
}

private extension MyWikiSourceCandidate {
    static func fixture(
        sourceID: String,
        sourceKind: MyWikiSourceKind,
        defaultIncluded: Bool,
        contentHash: String
    ) -> MyWikiSourceCandidate {
        MyWikiSourceCandidate(
            sourceID: sourceID,
            sourceKind: sourceKind,
            connectorInstanceID: nil,
            connectorID: nil,
            displayTitle: sourceID,
            relativePath: "\(sourceID).md",
            sourcePath: "/tmp/\(sourceID).md",
            sourceURL: nil,
            contentHash: contentHash,
            remoteUpdatedAt: nil,
            defaultIncluded: defaultIncluded,
            materializedRelativePath: "\(sourceID).md",
            folderContext: ""
        )
    }
}

private extension MyWikiSourceCatalogRecord {
    static func fixture(
        sourceID: String,
        included: Bool,
        contentHash: String = "hash",
        relativePath: String = "file.md"
    ) -> MyWikiSourceCatalogRecord {
        MyWikiSourceCatalogRecord(
            sourceID: sourceID,
            sourceKind: .externalDocument,
            connectorInstanceID: nil,
            connectorID: nil,
            displayTitle: sourceID,
            relativePath: relativePath,
            sourcePath: "/tmp/\(relativePath)",
            sourceURL: nil,
            contentHash: contentHash,
            remoteUpdatedAt: nil,
            included: included,
            includedDefault: false,
            lastIndexedHash: nil,
            lastIndexedAt: nil,
            lastIngestError: nil,
            rawSourcePath: "raw/sources/\(relativePath)",
            wikiSummaryPath: nil,
            folderContext: String(relativePath.split(separator: "/").dropLast().joined(separator: "/"))
        )
    }
}
