# My Wiki Source Catalog Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a persistent hierarchical My Wiki source catalog so diaries are included by default, external sources are opt-in, and Update My Wiki only processes included pending or changed sources.

**Architecture:** Add a Swift catalog layer under `KnowYou/Services/MyWiki/` that discovers candidate sources, persists inclusion/checkpoint state in `<projectRoot>/.knowyou/source-catalog.json`, materializes included sources to hierarchical `raw/sources` paths, and writes an explicit ingest manifest. Extend the headless `llm_wiki` runner to accept that manifest instead of scanning all raw sources, then replace the Source Library sheet with a hierarchical catalog manager.

**Tech Stack:** Swift/SwiftUI/XCTest for KnowYou, JSON Codable persistence, existing `SHA256Hasher`, existing `ImportedKnowledgeDocument` metadata, Node/Vitest for `ThirdParty/llm_wiki`.

---

## File Structure

- Create `KnowYou/Services/MyWiki/MyWikiSourceCatalog.swift`: catalog records, candidates, status calculation, tree nodes, directory selection reducer, store load/save.
- Create `KnowYou/Services/MyWiki/MyWikiSourceCatalogBuilder.swift`: diary/external/manual source discovery, catalog refresh, ingest planning, raw source materialization, manifest writing, checkpoint update.
- Modify `KnowYou/Services/MyWiki/MyWikiPipelineBridge.swift`: accept an optional manifest URL and pass `--manifest` to the development headless runner.
- Modify `KnowYou/Services/MyWiki/MyWikiProjectExporter.swift`: keep `ensureProject`, but move diary export responsibility into catalog materialization for the new update path.
- Modify `KnowYou/Services/MyWiki/MyWikiSourceLibrary.swift`: keep drag/drop import support but place new manual imports under `raw/sources/Manual Imports`.
- Modify `KnowYou/UI/MyWiki/MyWikiSourceLibraryView.swift`: replace flat raw-source list with hierarchical catalog rows, filters, counters, and include/exclude/invert visible actions.
- Modify `KnowYou/UI/MyWiki/MyWikiPanel.swift`: pass source catalog inputs into Source Library and run catalog update + manifest ingest from `syncDiaries`.
- Modify `KnowYou/UI/KnowledgeOntology/KnowledgeOntologyPanel.swift` and `KnowYou/UI/MainWindowView.swift`: pass connector configs and imported documents into My Wiki.
- Modify `ThirdParty/llm_wiki/src/headless/knowyou-ingest.ts`: add `--manifest` parsing and manifest source loading.
- Modify `ThirdParty/llm_wiki/src/headless/knowyou-ingest.test.ts`: cover manifest-limited ingest and nested source paths.
- Create/update Swift tests:
  - `KnowYouTests/MyWikiSourceCatalogTests.swift`
  - `KnowYouTests/MyWikiSourceCatalogBuilderTests.swift`
  - `KnowYouTests/MyWikiSourceLibraryPresentationTests.swift`
  - update `KnowYouTests/MyWikiPipelineBridgeTests.swift`
  - update `KnowYouTests/MyWikiSourceLibraryTests.swift`
- Modify `KnowYou.xcodeproj/project.pbxproj`: add new Swift service/test files to app and test targets.
- Review/update `docs/architecture.md` and `docs/requirements-spec.md` after implementation.

---

### Task 1: Catalog Domain Model And Persistence

**Files:**
- Create: `KnowYou/Services/MyWiki/MyWikiSourceCatalog.swift`
- Create: `KnowYouTests/MyWikiSourceCatalogTests.swift`
- Modify: `KnowYou.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write failing catalog status and persistence tests**

Add `KnowYouTests/MyWikiSourceCatalogTests.swift`:

```swift
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
                contentHash: "hash-a"
            )
        ])

        XCTAssertEqual(refreshed.records[0].included, false)
        XCTAssertEqual(refreshed.records[0].lastIndexedHash, "hash-a")
        XCTAssertEqual(refreshed.records[0].status, .excludedIndexed)
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
```

- [ ] **Step 2: Run the new tests to verify they fail**

Run:

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/MyWikiSourceCatalogTests
```

Expected: FAIL because `MyWikiSourceCandidate`, `MyWikiSourceCatalogRecord`, `MyWikiSourceCatalogStore`, and tree types do not exist.

- [ ] **Step 3: Implement catalog models and store**

Create `KnowYou/Services/MyWiki/MyWikiSourceCatalog.swift`:

```swift
import Foundation

enum MyWikiSourceKind: String, Codable, Equatable, Sendable {
    case diary
    case externalDocument
    case manualFile
}

enum MyWikiSourceProcessingStatus: String, Codable, Equatable, Sendable {
    case notIncluded = "Not included"
    case pending = "Pending"
    case indexed = "Indexed"
    case changed = "Changed"
    case excludedIndexed = "Excluded, indexed"
    case failed = "Failed"
}

enum MyWikiSourceSelectionState: Hashable, Sendable {
    case included
    case excluded
    case mixed
}

struct MyWikiSourceCandidate: Equatable, Sendable {
    var sourceID: String
    var sourceKind: MyWikiSourceKind
    var connectorInstanceID: String?
    var connectorID: KnowledgeConnectorID?
    var displayTitle: String
    var relativePath: String
    var sourcePath: String?
    var sourceURL: String?
    var contentHash: String
    var remoteUpdatedAt: Date?
    var defaultIncluded: Bool
    var materializedRelativePath: String
    var folderContext: String
}

struct MyWikiSourceCatalogRecord: Codable, Equatable, Identifiable, Sendable {
    var id: String { sourceID }
    var sourceID: String
    var sourceKind: MyWikiSourceKind
    var connectorInstanceID: String?
    var connectorID: KnowledgeConnectorID?
    var displayTitle: String
    var relativePath: String
    var sourcePath: String?
    var sourceURL: String?
    var contentHash: String
    var remoteUpdatedAt: Date?
    var included: Bool
    var includedDefault: Bool
    var lastIndexedHash: String?
    var lastIndexedAt: Date?
    var lastIngestError: String?
    var rawSourcePath: String
    var wikiSummaryPath: String?
    var folderContext: String

    var status: MyWikiSourceProcessingStatus {
        if lastIngestError != nil, included {
            return .failed
        }
        if included == false {
            return lastIndexedHash == nil ? .notIncluded : .excludedIndexed
        }
        guard let lastIndexedHash else {
            return .pending
        }
        return lastIndexedHash == contentHash ? .indexed : .changed
    }

    init(candidate: MyWikiSourceCandidate) {
        sourceID = candidate.sourceID
        sourceKind = candidate.sourceKind
        connectorInstanceID = candidate.connectorInstanceID
        connectorID = candidate.connectorID
        displayTitle = candidate.displayTitle
        relativePath = candidate.relativePath
        sourcePath = candidate.sourcePath
        sourceURL = candidate.sourceURL
        contentHash = candidate.contentHash
        remoteUpdatedAt = candidate.remoteUpdatedAt
        included = candidate.defaultIncluded
        includedDefault = candidate.defaultIncluded
        lastIndexedHash = nil
        lastIndexedAt = nil
        lastIngestError = nil
        rawSourcePath = "raw/sources/\(candidate.materializedRelativePath)"
        wikiSummaryPath = nil
        folderContext = candidate.folderContext
    }

    init(
        sourceID: String,
        sourceKind: MyWikiSourceKind,
        connectorInstanceID: String?,
        connectorID: KnowledgeConnectorID?,
        displayTitle: String,
        relativePath: String,
        sourcePath: String?,
        sourceURL: String?,
        contentHash: String,
        remoteUpdatedAt: Date?,
        included: Bool,
        includedDefault: Bool,
        lastIndexedHash: String?,
        lastIndexedAt: Date?,
        lastIngestError: String?,
        rawSourcePath: String,
        wikiSummaryPath: String?,
        folderContext: String
    ) {
        self.sourceID = sourceID
        self.sourceKind = sourceKind
        self.connectorInstanceID = connectorInstanceID
        self.connectorID = connectorID
        self.displayTitle = displayTitle
        self.relativePath = relativePath
        self.sourcePath = sourcePath
        self.sourceURL = sourceURL
        self.contentHash = contentHash
        self.remoteUpdatedAt = remoteUpdatedAt
        self.included = included
        self.includedDefault = includedDefault
        self.lastIndexedHash = lastIndexedHash
        self.lastIndexedAt = lastIndexedAt
        self.lastIngestError = lastIngestError
        self.rawSourcePath = rawSourcePath
        self.wikiSummaryPath = wikiSummaryPath
        self.folderContext = folderContext
    }

    mutating func update(from candidate: MyWikiSourceCandidate) {
        sourceKind = candidate.sourceKind
        connectorInstanceID = candidate.connectorInstanceID
        connectorID = candidate.connectorID
        displayTitle = candidate.displayTitle
        relativePath = candidate.relativePath
        sourcePath = candidate.sourcePath
        sourceURL = candidate.sourceURL
        contentHash = candidate.contentHash
        remoteUpdatedAt = candidate.remoteUpdatedAt
        rawSourcePath = "raw/sources/\(candidate.materializedRelativePath)"
        folderContext = candidate.folderContext
    }
}

struct MyWikiSourceCatalogSnapshot: Codable, Equatable, Sendable {
    var records: [MyWikiSourceCatalogRecord]

    func merged(with candidates: [MyWikiSourceCandidate]) -> MyWikiSourceCatalogSnapshot {
        var existingByID = Dictionary(uniqueKeysWithValues: records.map { ($0.sourceID, $0) })
        var merged: [MyWikiSourceCatalogRecord] = []
        for candidate in candidates.sorted(by: Self.candidateSort) {
            if var record = existingByID.removeValue(forKey: candidate.sourceID) {
                record.update(from: candidate)
                merged.append(record)
            } else {
                merged.append(MyWikiSourceCatalogRecord(candidate: candidate))
            }
        }
        let retainedHistoricalRecords = existingByID.values
            .filter { $0.lastIndexedHash != nil }
            .sorted { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }
        merged.append(contentsOf: retainedHistoricalRecords)
        return MyWikiSourceCatalogSnapshot(records: merged)
    }

    private static func candidateSort(_ lhs: MyWikiSourceCandidate, _ rhs: MyWikiSourceCandidate) -> Bool {
        if lhs.sourceKind != rhs.sourceKind {
            return lhs.sourceKind.rawValue < rhs.sourceKind.rawValue
        }
        return lhs.relativePath.localizedStandardCompare(rhs.relativePath) == .orderedAscending
    }
}

struct MyWikiSourceCatalogNode: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case root
        case directory
        case source(MyWikiSourceCatalogRecord)
    }

    var id: String
    var title: String
    var kind: Kind
    var selectionState: MyWikiSourceSelectionState
    var children: [MyWikiSourceCatalogNode]
}

struct MyWikiSourceCatalogTreeBuilder {
    func build(records: [MyWikiSourceCatalogRecord]) -> MyWikiSourceCatalogNode {
        let children = groupedNodes(records: records, prefix: "", componentsIndex: 0)
        return MyWikiSourceCatalogNode(id: "root", title: "Sources", kind: .root, selectionState: state(for: children), children: children)
    }

    private func groupedNodes(records: [MyWikiSourceCatalogRecord], prefix: String, componentsIndex: Int) -> [MyWikiSourceCatalogNode] {
        let groups = Dictionary(grouping: records) { record -> String in
            let components = record.relativePath.split(separator: "/").map(String.init)
            return components.indices.contains(componentsIndex) ? components[componentsIndex] : record.displayTitle
        }
        return groups.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.map { key in
            let groupRecords = groups[key] ?? []
            let leafRecords = groupRecords.filter { $0.relativePath.split(separator: "/").count == componentsIndex + 1 }
            let nestedRecords = groupRecords.filter { $0.relativePath.split(separator: "/").count > componentsIndex + 1 }
            var children = leafRecords.map { record in
                MyWikiSourceCatalogNode(
                    id: record.sourceID,
                    title: record.displayTitle,
                    kind: .source(record),
                    selectionState: record.included ? .included : .excluded,
                    children: []
                )
            }
            children.append(contentsOf: groupedNodes(records: nestedRecords, prefix: prefix.isEmpty ? key : "\(prefix)/\(key)", componentsIndex: componentsIndex + 1))
            let nodeID = prefix.isEmpty ? key : "\(prefix)/\(key)"
            return MyWikiSourceCatalogNode(id: nodeID, title: key, kind: children.count == 1 && nestedRecords.isEmpty ? children[0].kind : .directory, selectionState: state(for: children), children: children)
        }
    }

    private func state(for children: [MyWikiSourceCatalogNode]) -> MyWikiSourceSelectionState {
        let states = Set(children.map(\.selectionState))
        if states.count == 1, let only = states.first {
            return only
        }
        return .mixed
    }
}

struct MyWikiSourceCatalogStore {
    let projectRoot: URL
    let fileManager: FileManager

    init(projectRoot: URL, fileManager: FileManager = .default) {
        self.projectRoot = projectRoot
        self.fileManager = fileManager
    }

    static func emptySnapshot() -> MyWikiSourceCatalogSnapshot {
        MyWikiSourceCatalogSnapshot(records: [])
    }

    func load() throws -> MyWikiSourceCatalogSnapshot {
        let url = catalogURL
        guard fileManager.fileExists(atPath: url.path) else {
            return Self.emptySnapshot()
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder.knowledgeImport().decode(MyWikiSourceCatalogSnapshot.self, from: data)
    }

    func save(_ snapshot: MyWikiSourceCatalogSnapshot) throws {
        try fileManager.createDirectory(at: catalogURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder.knowledgeImport().encode(snapshot)
        try data.write(to: catalogURL, options: .atomic)
    }

    private var catalogURL: URL {
        projectRoot.appending(path: ".knowyou/source-catalog.json")
    }
}
```

If `JSONEncoder.knowledgeImport()` / `JSONDecoder.knowledgeImport()` are not visible from this file, use the same extension already used by `KnowledgeImportStore`; do not add a second date format.

- [ ] **Step 4: Register files in Xcode project**

Edit `KnowYou.xcodeproj/project.pbxproj` by following the existing `MyWikiSourceLibrary.swift` entries:

```text
/* MyWikiSourceCatalog.swift in Sources */
/* MyWikiSourceCatalogTests.swift in Sources */
```

Add `KnowYou/Services/MyWiki/MyWikiSourceCatalog.swift` to the app target Sources phase and `KnowYouTests/MyWikiSourceCatalogTests.swift` to the test target Sources phase.

- [ ] **Step 5: Run catalog tests**

Run:

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/MyWikiSourceCatalogTests
```

Expected: PASS.

- [ ] **Step 6: Commit Task 1**

```bash
git add KnowYou/Services/MyWiki/MyWikiSourceCatalog.swift KnowYouTests/MyWikiSourceCatalogTests.swift KnowYou.xcodeproj/project.pbxproj
git commit -m "Add My Wiki source catalog model"
```

---

### Task 2: Source Discovery, Materialization, And Ingest Planning

**Files:**
- Create: `KnowYou/Services/MyWiki/MyWikiSourceCatalogBuilder.swift`
- Create: `KnowYouTests/MyWikiSourceCatalogBuilderTests.swift`
- Modify: `KnowYou.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write failing builder tests**

Add `KnowYouTests/MyWikiSourceCatalogBuilderTests.swift`:

```swift
import XCTest
@testable import KnowYou

final class MyWikiSourceCatalogBuilderTests: XCTestCase {
    func testRefreshDiscoversDiariesIncludedByDefault() throws {
        let fixture = try Fixture()
        try fixture.writeDiary(day: "2026-05-27", markdown: "# 2026-05-27\n\nDiary text.")

        let snapshot = try MyWikiSourceCatalogBuilder().refreshCatalog(
            projectRoot: fixture.projectRoot,
            sourceVault: fixture.vault,
            importedDocuments: []
        )

        XCTAssertEqual(snapshot.records.map(\.sourceID), ["diary:2026-05-27"])
        XCTAssertEqual(snapshot.records[0].included, true)
        XCTAssertEqual(snapshot.records[0].rawSourcePath, "raw/sources/My Diary/knowyou-diary-2026-05-27.md")
    }

    func testRefreshDiscoversExternalDocumentsExcludedByDefaultWithHierarchy() throws {
        let fixture = try Fixture()
        let source = fixture.root.appending(path: "External/Projects/AI/notes.md")
        try FileManager.default.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "# Notes".write(to: source, atomically: true, encoding: .utf8)
        let document = ImportedKnowledgeDocument.fixture(
            id: "doc-1",
            connectorInstanceID: "local-main",
            connectorID: .localFolderImport,
            title: "notes.md",
            sourcePath: source.path,
            contentHash: SHA256Hasher.hash("# Notes"),
            localContentPath: source.path
        )

        let snapshot = try MyWikiSourceCatalogBuilder().refreshCatalog(
            projectRoot: fixture.projectRoot,
            sourceVault: fixture.vault,
            importedDocuments: [document]
        )

        XCTAssertEqual(snapshot.records[0].included, false)
        XCTAssertEqual(snapshot.records[0].relativePath, "Local Folder/local-main/Projects/AI/notes.md")
        XCTAssertEqual(snapshot.records[0].rawSourcePath, "raw/sources/Local Folder/local-main/Projects/AI/notes.md")
        XCTAssertEqual(snapshot.records[0].folderContext, "Local Folder/local-main/Projects/AI")
    }

    func testRefreshDiscoversManualSourcesIncludedByDefaultUnderManualImports() throws {
        let fixture = try Fixture()
        let manual = fixture.projectRoot.appending(path: "raw/sources/Manual Imports/Research/note.md")
        try FileManager.default.createDirectory(at: manual.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "# Manual note".write(to: manual, atomically: true, encoding: .utf8)

        let snapshot = try MyWikiSourceCatalogBuilder().refreshCatalog(
            projectRoot: fixture.projectRoot,
            sourceVault: fixture.vault,
            importedDocuments: []
        )

        XCTAssertEqual(snapshot.records.map(\.sourceID), ["manual:Manual Imports/Research/note.md"])
        XCTAssertEqual(snapshot.records[0].sourceKind, .manualFile)
        XCTAssertEqual(snapshot.records[0].included, true)
        XCTAssertEqual(snapshot.records[0].relativePath, "Manual Imports/Research/note.md")
        XCTAssertEqual(snapshot.records[0].rawSourcePath, "raw/sources/Manual Imports/Research/note.md")
    }

    func testIngestPlanOnlyIncludesPendingAndChangedIncludedSources() throws {
        let records = [
            MyWikiSourceCatalogRecord.planFixture(sourceID: "pending", included: true, contentHash: "a", lastIndexedHash: nil),
            MyWikiSourceCatalogRecord.planFixture(sourceID: "indexed", included: true, contentHash: "b", lastIndexedHash: "b"),
            MyWikiSourceCatalogRecord.planFixture(sourceID: "changed", included: true, contentHash: "c2", lastIndexedHash: "c1"),
            MyWikiSourceCatalogRecord.planFixture(sourceID: "excluded", included: false, contentHash: "d2", lastIndexedHash: "d1")
        ]

        let plan = MyWikiSourceCatalogBuilder().ingestPlan(
            snapshot: MyWikiSourceCatalogSnapshot(records: records),
            maxSources: 10
        )

        XCTAssertEqual(plan.sources.map(\.sourceID), ["pending", "changed"])
    }

    func testMaterializePreservesNestedRawSourcePathAndWritesManifest() throws {
        let fixture = try Fixture()
        let external = fixture.root.appending(path: "External/Projects/AI/notes.md")
        try FileManager.default.createDirectory(at: external.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "# Notes".write(to: external, atomically: true, encoding: .utf8)
        var record = MyWikiSourceCatalogRecord.planFixture(
            sourceID: "doc-1",
            included: true,
            contentHash: SHA256Hasher.hash("# Notes"),
            lastIndexedHash: nil,
            rawSourcePath: "raw/sources/Local Folder/local-main/Projects/AI/notes.md"
        )
        record.sourcePath = external.path
        record.folderContext = "Local Folder/local-main/Projects/AI"
        let plan = MyWikiSourceIngestPlan(sources: [MyWikiSourceIngestSource(record: record)])

        let result = try MyWikiSourceCatalogBuilder().materialize(plan: plan, projectRoot: fixture.projectRoot)

        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.projectRoot.appending(path: "raw/sources/Local Folder/local-main/Projects/AI/notes.md").path))
        let manifest = try String(contentsOf: result.manifestURL, encoding: .utf8)
        XCTAssertTrue(manifest.contains(#""sourceID" : "doc-1""#) || manifest.contains(#""sourceID": "doc-1""#), manifest)
        XCTAssertTrue(manifest.contains(#""folderContext" : "Local Folder/local-main/Projects/AI""#) || manifest.contains(#""folderContext": "Local Folder/local-main/Projects/AI""#), manifest)
    }
}

private final class Fixture {
    let root: URL
    let vault: URL
    let projectRoot: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        vault = root.appending(path: "Vault", directoryHint: .isDirectory)
        projectRoot = root.appending(path: "Project", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    func writeDiary(day: String, markdown: String) throws {
        try markdown.write(to: vault.appending(path: "\(day).md"), atomically: true, encoding: .utf8)
    }
}

private extension ImportedKnowledgeDocument {
    static func fixture(
        id: String,
        connectorInstanceID: String,
        connectorID: KnowledgeConnectorID,
        title: String,
        sourcePath: String,
        contentHash: String,
        localContentPath: String
    ) -> ImportedKnowledgeDocument {
        ImportedKnowledgeDocument(
            id: id,
            connectorInstanceID: connectorInstanceID,
            connectorID: connectorID,
            remoteID: id,
            title: title,
            sourcePath: sourcePath,
            remoteURL: nil,
            mimeType: "text/markdown",
            contentHash: contentHash,
            remoteUpdatedAt: nil,
            firstImportedAt: Date(timeIntervalSince1970: 1),
            lastSyncedAt: Date(timeIntervalSince1970: 2),
            deletedAt: nil,
            localContentPath: localContentPath,
            localMetadataPath: "/tmp/\(id).json",
            normalizationVersion: 1,
            originKind: "local-file"
        )
    }
}
```

- [ ] **Step 2: Run builder tests to verify they fail**

Run:

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/MyWikiSourceCatalogBuilderTests
```

Expected: FAIL because `MyWikiSourceCatalogBuilder`, `MyWikiSourceIngestPlan`, and materialization types do not exist.

- [ ] **Step 3: Implement builder, ingest plan, and materialization**

Create `KnowYou/Services/MyWiki/MyWikiSourceCatalogBuilder.swift`:

```swift
import Foundation

struct MyWikiSourceIngestSource: Codable, Equatable, Sendable {
    var sourcePath: String
    var sourceID: String
    var displayTitle: String
    var folderContext: String
    var sourceKind: MyWikiSourceKind
    var contentHash: String

    init(record: MyWikiSourceCatalogRecord) {
        sourcePath = record.rawSourcePath
        sourceID = record.sourceID
        displayTitle = record.displayTitle
        folderContext = record.folderContext
        sourceKind = record.sourceKind
        contentHash = record.contentHash
    }
}

struct MyWikiSourceIngestPlan: Codable, Equatable, Sendable {
    var sources: [MyWikiSourceIngestSource]
}

struct MyWikiSourceMaterializationResult: Equatable, Sendable {
    var manifestURL: URL
    var materializedCount: Int
}

struct MyWikiSourceCatalogBuilder {
    var fileManager: FileManager = .default

    func refreshCatalog(
        projectRoot: URL,
        sourceVault: URL?,
        importedDocuments: [ImportedKnowledgeDocument]
    ) throws -> MyWikiSourceCatalogSnapshot {
        try MyWikiProjectExporter(fileManager: fileManager).ensureProject(at: projectRoot)
        var candidates: [MyWikiSourceCandidate] = []
        if let sourceVault {
            candidates.append(contentsOf: try diaryCandidates(sourceVault: sourceVault))
        }
        candidates.append(contentsOf: try manualCandidates(projectRoot: projectRoot))
        candidates.append(contentsOf: externalCandidates(importedDocuments: importedDocuments))

        let store = MyWikiSourceCatalogStore(projectRoot: projectRoot, fileManager: fileManager)
        let snapshot = try store.load().merged(with: candidates)
        try store.save(snapshot)
        return snapshot
    }

    func ingestPlan(snapshot: MyWikiSourceCatalogSnapshot, maxSources: Int) -> MyWikiSourceIngestPlan {
        let sources = snapshot.records
            .filter { [.pending, .changed, .failed].contains($0.status) }
            .filter(\.included)
            .sorted { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }
            .prefix(max(0, maxSources))
            .map(MyWikiSourceIngestSource.init(record:))
        return MyWikiSourceIngestPlan(sources: Array(sources))
    }

    func materialize(plan: MyWikiSourceIngestPlan, projectRoot: URL) throws -> MyWikiSourceMaterializationResult {
        for source in plan.sources {
            let sourceURL = projectRoot.appending(path: source.sourcePath)
            try fileManager.createDirectory(at: sourceURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        }
        let manifestURL = projectRoot.appending(path: ".knowyou/ingest-manifest.json")
        try fileManager.createDirectory(at: manifestURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder.knowledgeImport().encode(plan)
        try data.write(to: manifestURL, options: .atomic)
        return MyWikiSourceMaterializationResult(manifestURL: manifestURL, materializedCount: plan.sources.count)
    }

    func materialize(records: [MyWikiSourceCatalogRecord], projectRoot: URL) throws {
        for record in records {
            guard let sourcePath = record.sourcePath else { continue }
            let sourceURL = URL(fileURLWithPath: sourcePath)
            let destination = projectRoot.appending(path: record.rawSourcePath)
            try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.copyItem(at: sourceURL, to: destination)
        }
    }

    func mark(plan: MyWikiSourceIngestPlan, succeededIn snapshot: MyWikiSourceCatalogSnapshot, at date: Date) -> MyWikiSourceCatalogSnapshot {
        let succeededIDs = Set(plan.sources.map(\.sourceID))
        var next = snapshot
        for index in next.records.indices where succeededIDs.contains(next.records[index].sourceID) {
            next.records[index].lastIndexedHash = next.records[index].contentHash
            next.records[index].lastIndexedAt = date
            next.records[index].lastIngestError = nil
            let basename = URL(fileURLWithPath: next.records[index].rawSourcePath).deletingPathExtension().lastPathComponent
            next.records[index].wikiSummaryPath = "wiki/sources/\(basename).md"
        }
        return next
    }

    func mark(plan: MyWikiSourceIngestPlan, failedWith message: String, in snapshot: MyWikiSourceCatalogSnapshot) -> MyWikiSourceCatalogSnapshot {
        let failedIDs = Set(plan.sources.map(\.sourceID))
        var next = snapshot
        for index in next.records.indices where failedIDs.contains(next.records[index].sourceID) {
            next.records[index].lastIngestError = message
        }
        return next
    }

    private func diaryCandidates(sourceVault: URL) throws -> [MyWikiSourceCandidate] {
        guard fileManager.fileExists(atPath: sourceVault.path) else { return [] }
        let files = try fileManager.contentsOfDirectory(at: sourceVault, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        return try files
            .filter { $0.pathExtension == "md" }
            .filter { $0.deletingPathExtension().lastPathComponent.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .map { file in
                let day = file.deletingPathExtension().lastPathComponent
                let markdown = try String(contentsOf: file, encoding: .utf8)
                let exported = MyWikiProjectExporter.exportedDiaryMarkdownForCatalog(dayKey: day, markdown: markdown)
                return MyWikiSourceCandidate(
                    sourceID: "diary:\(day)",
                    sourceKind: .diary,
                    connectorInstanceID: nil,
                    connectorID: nil,
                    displayTitle: day,
                    relativePath: "My Diary/\(day).md",
                    sourcePath: file.path,
                    sourceURL: nil,
                    contentHash: SHA256Hasher.hash(exported),
                    remoteUpdatedAt: nil,
                    defaultIncluded: true,
                    materializedRelativePath: "My Diary/knowyou-diary-\(day).md",
                    folderContext: "My Diary"
                )
            }
    }

    private func externalCandidates(importedDocuments: [ImportedKnowledgeDocument]) -> [MyWikiSourceCandidate] {
        importedDocuments
            .filter { $0.deletedAt == nil }
            .map { document in
                let connectorTitle = displayName(for: document.connectorID)
                let relative = relativePath(for: document)
                let folder = String(relative.split(separator: "/").dropLast().joined(separator: "/"))
                return MyWikiSourceCandidate(
                    sourceID: document.id,
                    sourceKind: .externalDocument,
                    connectorInstanceID: document.connectorInstanceID,
                    connectorID: document.connectorID,
                    displayTitle: document.title,
                    relativePath: "\(connectorTitle)/\(document.connectorInstanceID)/\(relative)",
                    sourcePath: document.localContentPath,
                    sourceURL: document.remoteURL,
                    contentHash: document.contentHash,
                    remoteUpdatedAt: document.remoteUpdatedAt,
                    defaultIncluded: false,
                    materializedRelativePath: "\(connectorTitle)/\(document.connectorInstanceID)/\(relative)",
                    folderContext: "\(connectorTitle)/\(document.connectorInstanceID)/\(folder)"
                )
            }
    }

    private func manualCandidates(projectRoot: URL) throws -> [MyWikiSourceCandidate] {
        let manualRoot = projectRoot.appending(path: "raw/sources/Manual Imports", directoryHint: .isDirectory)
        guard fileManager.fileExists(atPath: manualRoot.path) else { return [] }
        guard let enumerator = fileManager.enumerator(
            at: manualRoot,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var candidates: [MyWikiSourceCandidate] = []
        for case let file as URL in enumerator where ["md", "markdown", "txt"].contains(file.pathExtension.lowercased()) {
            let relative = file.path.replacingOccurrences(of: "\(projectRoot.appending(path: "raw/sources").path)/", with: "")
            let markdown = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
            let folder = String(relative.split(separator: "/").dropLast().joined(separator: "/"))
            candidates.append(
                MyWikiSourceCandidate(
                    sourceID: "manual:\(relative)",
                    sourceKind: .manualFile,
                    connectorInstanceID: nil,
                    connectorID: nil,
                    displayTitle: file.lastPathComponent,
                    relativePath: relative,
                    sourcePath: file.path,
                    sourceURL: nil,
                    contentHash: SHA256Hasher.hash(markdown),
                    remoteUpdatedAt: nil,
                    defaultIncluded: true,
                    materializedRelativePath: relative,
                    folderContext: folder
                )
            )
        }
        return candidates.sorted { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }
    }

    private func relativePath(for document: ImportedKnowledgeDocument) -> String {
        if let sourcePath = document.sourcePath, sourcePath.isEmpty == false {
            return URL(fileURLWithPath: sourcePath).lastPathComponent == document.title
                ? document.title
                : URL(fileURLWithPath: sourcePath).pathComponents.suffix(3).joined(separator: "/")
        }
        return document.title
    }

    private func displayName(for connectorID: KnowledgeConnectorID) -> String {
        switch connectorID {
        case .localFolderImport: return "Local Folder"
        case .obsidianImport: return "Obsidian"
        case .feishuImport: return "Feishu Docs"
        case .notionImport: return "Notion"
        case .googleDriveImport: return "Google Drive"
        case .obsidianExport: return "Obsidian Export"
        case .openClawExport: return "OpenClaw Export"
        }
    }
}
```

Expose diary wrapping without duplicating markdown format by modifying `KnowYou/Services/MyWiki/MyWikiProjectExporter.swift`:

```swift
static func exportedDiaryMarkdownForCatalog(dayKey: String, markdown: String) -> String {
    exportedDiaryMarkdown(dayKey: dayKey, markdown: markdown)
}
```

Keep `exportedDiaryMarkdown(dayKey:markdown:)` private.

- [ ] **Step 4: Fix materialize implementation to copy source records**

After writing the initial code, adjust the test and implementation so `materialize(plan:projectRoot:)` has enough source record data to copy source files. The final public API should be:

```swift
func materialize(
    plan: MyWikiSourceIngestPlan,
    from snapshot: MyWikiSourceCatalogSnapshot,
    projectRoot: URL
) throws -> MyWikiSourceMaterializationResult
```

Implementation:

```swift
func materialize(
    plan: MyWikiSourceIngestPlan,
    from snapshot: MyWikiSourceCatalogSnapshot,
    projectRoot: URL
) throws -> MyWikiSourceMaterializationResult {
    let recordsByID = Dictionary(uniqueKeysWithValues: snapshot.records.map { ($0.sourceID, $0) })
    for source in plan.sources {
        guard let record = recordsByID[source.sourceID],
              let sourcePath = record.sourcePath else {
            continue
        }
        let sourceURL = URL(fileURLWithPath: sourcePath)
        let destination = projectRoot.appending(path: record.rawSourcePath)
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        if record.sourceKind == .diary {
            let dayKey = record.sourceID.replacingOccurrences(of: "diary:", with: "")
            let markdown = try String(contentsOf: sourceURL, encoding: .utf8)
            let exported = MyWikiProjectExporter.exportedDiaryMarkdownForCatalog(dayKey: dayKey, markdown: markdown)
            try exported.write(to: destination, atomically: true, encoding: .utf8)
        } else {
            try fileManager.copyItem(at: sourceURL, to: destination)
        }
    }

    let manifestURL = projectRoot.appending(path: ".knowyou/ingest-manifest.json")
    try fileManager.createDirectory(at: manifestURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    let data = try JSONEncoder.knowledgeImport().encode(plan)
    try data.write(to: manifestURL, options: .atomic)
    return MyWikiSourceMaterializationResult(manifestURL: manifestURL, materializedCount: plan.sources.count)
}
```

- [ ] **Step 5: Register files and run builder tests**

Add `MyWikiSourceCatalogBuilder.swift` and `MyWikiSourceCatalogBuilderTests.swift` to `KnowYou.xcodeproj/project.pbxproj`.

Run:

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/MyWikiSourceCatalogBuilderTests
```

Expected: PASS.

- [ ] **Step 6: Commit Task 2**

```bash
git add KnowYou/Services/MyWiki/MyWikiSourceCatalogBuilder.swift KnowYou/Services/MyWiki/MyWikiProjectExporter.swift KnowYouTests/MyWikiSourceCatalogBuilderTests.swift KnowYou.xcodeproj/project.pbxproj
git commit -m "Plan My Wiki source catalog ingest inputs"
```

---

### Task 3: Headless llm_wiki Manifest Support

**Files:**
- Modify: `ThirdParty/llm_wiki/src/headless/knowyou-ingest.ts`
- Modify: `ThirdParty/llm_wiki/src/headless/knowyou-ingest.test.ts`

- [ ] **Step 1: Write failing manifest tests**

Append tests to `ThirdParty/llm_wiki/src/headless/knowyou-ingest.test.ts`:

```ts
it("uses an explicit manifest instead of scanning all raw sources", async () => {
  const tmp = await createTempProject("knowyou-headless-manifest")
  try {
    await fs.mkdir(path.join(tmp.path, "raw/sources/My Diary"), { recursive: true })
    await fs.mkdir(path.join(tmp.path, "raw/sources/External/Projects"), { recursive: true })
    await writeFileRaw(path.join(tmp.path, "purpose.md"), "# Purpose\n\nBuild My Wiki.")
    await writeFileRaw(path.join(tmp.path, "wiki/index.md"), "# My Wiki Index\n")
    await writeFileRaw(path.join(tmp.path, "wiki/overview.md"), "# Overview\n")
    await writeFileRaw(path.join(tmp.path, "raw/sources/My Diary/knowyou-diary-2026-05-27.md"), "# Diary\n\nUse me.")
    await writeFileRaw(path.join(tmp.path, "raw/sources/External/Projects/skip-me.md"), "# External\n\nDo not use me.")
    const manifestPath = path.join(tmp.path, ".knowyou/ingest-manifest.json")
    await fs.mkdir(path.dirname(manifestPath), { recursive: true })
    await writeFileRaw(
      manifestPath,
      JSON.stringify({
        sources: [
          {
            sourcePath: "raw/sources/My Diary/knowyou-diary-2026-05-27.md",
            sourceID: "diary:2026-05-27",
            displayTitle: "2026-05-27",
            folderContext: "My Diary",
            sourceKind: "diary",
            contentHash: "hash-a",
          },
        ],
      }),
    )

    pendingResponses = [
      "Diary analysis.",
      sourceSummaryBlock("2026-05-27"),
    ]

    const status = await runKnowYouIngest({
      projectPath: tmp.path,
      provider: "openai",
      model: "test-model",
      manifestPath,
    })

    expect(status.sourcesProcessed).toBe(1)
    expect(streamedPrompts.join("\n")).toContain("knowyou-diary-2026-05-27.md")
    expect(streamedPrompts.join("\n")).toContain("My Diary")
    expect(streamedPrompts.join("\n")).not.toContain("skip-me.md")
  } finally {
    await tmp.cleanup()
  }
})

it("rejects manifest source paths outside raw sources", async () => {
  const tmp = await createTempProject("knowyou-headless-manifest-path-safety")
  try {
    const manifestPath = path.join(tmp.path, ".knowyou/ingest-manifest.json")
    await fs.mkdir(path.dirname(manifestPath), { recursive: true })
    await writeFileRaw(
      manifestPath,
      JSON.stringify({
        sources: [
          {
            sourcePath: "../secret.md",
            sourceID: "bad",
            displayTitle: "bad",
            folderContext: "",
            sourceKind: "externalDocument",
            contentHash: "hash",
          },
        ],
      }),
    )

    await expect(runKnowYouIngest({ projectPath: tmp.path, manifestPath })).rejects.toThrow(
      "Manifest source must stay under raw/sources",
    )
  } finally {
    await tmp.cleanup()
  }
})
```

Also extend `interface IngestOptions` in the test expectation by using the production type after implementation.

- [ ] **Step 2: Run Vitest to verify manifest tests fail**

Run:

```bash
npm --prefix ThirdParty/llm_wiki test -- src/headless/knowyou-ingest.test.ts
```

Expected: FAIL because `manifestPath` is not accepted and the runner still scans all raw sources.

- [ ] **Step 3: Implement manifest parsing and source loading**

Modify `ThirdParty/llm_wiki/src/headless/knowyou-ingest.ts`:

```ts
interface IngestOptions {
  projectPath: string
  provider?: LlmConfig["provider"]
  model?: string
  maxSources?: number
  manifestPath?: string
}

interface ManifestSource {
  sourcePath: string
  sourceID: string
  displayTitle: string
  folderContext: string
  sourceKind: string
  contentHash: string
}

interface IngestManifest {
  sources: ManifestSource[]
}
```

Add parse support:

```ts
} else if (arg === "--manifest" && next) {
  options.manifestPath = next
  index += 1
}
```

Add manifest loader:

```ts
async function loadManifestSources(projectPath: string, manifestPath: string): Promise<string[]> {
  const raw = await fs.readFile(manifestPath, "utf-8")
  const manifest = JSON.parse(raw) as IngestManifest
  if (!Array.isArray(manifest.sources)) {
    throw new Error("Manifest must contain a sources array.")
  }
  return manifest.sources.map((source) => {
    const normalizedRelative = source.sourcePath.replace(/\\/g, "/")
    if (!normalizedRelative.startsWith("raw/sources/")) {
      throw new Error("Manifest source must stay under raw/sources.")
    }
    const fullPath = path.resolve(projectPath, normalizedRelative).replace(/\\/g, "/")
    const rawRoot = path.resolve(projectPath, "raw", "sources").replace(/\\/g, "/")
    if (!fullPath.startsWith(`${rawRoot}/`)) {
      throw new Error("Manifest source must stay under raw/sources.")
    }
    return fullPath
  })
}
```

Use manifest in `runKnowYouIngest`:

```ts
const sources = options.manifestPath
  ? await loadManifestSources(projectPath, options.manifestPath)
  : await listSources(projectPath, options.maxSources)
```

To include folder context in prompts without changing `autoIngest`, pass it through the existing `folderContext` parameter:

```ts
const manifestByFullPath = options.manifestPath
  ? await loadManifestSourceMap(projectPath, options.manifestPath)
  : new Map<string, ManifestSource>()

for (const sourcePath of sources) {
  const manifestSource = manifestByFullPath.get(sourcePath)
  const written = await autoIngest(projectPath, sourcePath, llmConfig, undefined, manifestSource?.folderContext ?? "")
  written.forEach((filePath) => filesWritten.add(filePath))
  processed += 1
}
```

Implement `loadManifestSourceMap` with the same validation as `loadManifestSources` so validation logic is shared.

- [ ] **Step 4: Run headless tests**

Run:

```bash
npm --prefix ThirdParty/llm_wiki test -- src/headless/knowyou-ingest.test.ts
```

Expected: PASS.

- [ ] **Step 5: Commit Task 3**

```bash
git add ThirdParty/llm_wiki/src/headless/knowyou-ingest.ts ThirdParty/llm_wiki/src/headless/knowyou-ingest.test.ts
git commit -m "Add My Wiki ingest manifest support"
```

---

### Task 4: Pipeline Bridge Manifest Wiring And Checkpoints

**Files:**
- Modify: `KnowYou/Services/MyWiki/MyWikiPipelineBridge.swift`
- Modify: `KnowYouTests/MyWikiPipelineBridgeTests.swift`

- [ ] **Step 1: Write failing bridge test for manifest argument**

Modify `testRunIngestInvokesDevelopmentHeadlessRunner` in `KnowYouTests/MyWikiPipelineBridgeTests.swift`:

```swift
let manifestURL = root.appending(path: ".knowyou/ingest-manifest.json")
try FileManager.default.createDirectory(at: manifestURL.deletingLastPathComponent(), withIntermediateDirectories: true)
try #"{"sources":[]}"#.write(to: manifestURL, atomically: true, encoding: .utf8)

try MyWikiPipelineBridge(processRunner: runner).runIngest(
    target: .developmentSource(dev),
    projectRoot: root,
    manifestURL: manifestURL
)

XCTAssertEqual(
    runner.calls[0].arguments,
    [
        "npm",
        "run",
        "knowyou:ingest",
        "--",
        "--project",
        root.path,
        "--provider",
        "codex-cli",
        "--model",
        "gpt-5.5",
        "--max-sources",
        "3",
        "--manifest",
        manifestURL.path
    ]
)
```

Keep a second assertion in a separate test that calling without a manifest still omits `--manifest`.

- [ ] **Step 2: Run bridge tests to verify they fail**

Run:

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/MyWikiPipelineBridgeTests
```

Expected: FAIL because `runIngest(target:projectRoot:manifestURL:)` does not exist.

- [ ] **Step 3: Add optional manifest URL to bridge API**

Modify `KnowYou/Services/MyWiki/MyWikiPipelineBridge.swift`:

```swift
func runIngest(target: MyWikiPipelineTarget, projectRoot: URL, manifestURL: URL? = nil) throws {
    try FileManager.default.createDirectory(
        at: projectRoot.appending(path: ".llm-wiki", directoryHint: .isDirectory),
        withIntermediateDirectories: true
    )

    switch target {
    case .bundledHelperApp:
        let message = "headless llm_wiki runner is not available for bundled helper apps yet."
        try writeFailureStatus(message: message, projectRoot: projectRoot)
        throw MyWikiPipelineBridgeError.pipelineExecutionFailed(message)
    case .developmentSource(let sourceURL):
        try runDevelopmentPipeline(sourceURL: sourceURL, projectRoot: projectRoot, manifestURL: manifestURL)
    case .missing:
        let message = "llm_wiki pipeline is not available."
        try writeFailureStatus(message: message, projectRoot: projectRoot)
        throw MyWikiPipelineBridgeError.missingPipeline
    }
}

private func runDevelopmentPipeline(sourceURL: URL, projectRoot: URL, manifestURL: URL?) throws {
    let packageURL = sourceURL.appending(path: "package.json")
    guard FileManager.default.fileExists(atPath: packageURL.path) else {
        let message = "headless llm_wiki runner is not available for development source yet."
        try writeFailureStatus(message: message, projectRoot: projectRoot)
        throw MyWikiPipelineBridgeError.pipelineExecutionFailed(message)
    }

    var arguments = [
        "npm",
        "run",
        "knowyou:ingest",
        "--",
        "--project",
        projectRoot.path,
        "--provider",
        "codex-cli",
        "--model",
        "gpt-5.5",
        "--max-sources",
        "\(MyWikiIngestBatchPolicy.maxSourcesPerRun)"
    ]
    if let manifestURL {
        arguments.append(contentsOf: ["--manifest", manifestURL.path])
    }

    let result = try processRunner.run(
        executable: npmExecutable,
        arguments: arguments,
        workingDirectory: sourceURL,
        timeoutSeconds: 30 * 60
    )

    guard result.terminationStatus == 0 else {
        let detail = [result.stderr, result.stdout]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
            .joined(separator: "\n")
        let message = detail.isEmpty
            ? "llm_wiki headless runner exited with status \(result.terminationStatus)."
            : detail
        try writeFailureStatus(message: message, projectRoot: projectRoot)
        throw MyWikiPipelineBridgeError.pipelineExecutionFailed(message)
    }

    try writeSuccessStatus(message: "My Wiki pipeline completed.", projectRoot: projectRoot)
}
```

- [ ] **Step 4: Run bridge tests**

Run:

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/MyWikiPipelineBridgeTests
```

Expected: PASS.

- [ ] **Step 5: Commit Task 4**

```bash
git add KnowYou/Services/MyWiki/MyWikiPipelineBridge.swift KnowYouTests/MyWikiPipelineBridgeTests.swift
git commit -m "Pass My Wiki source manifest to ingest"
```

---

### Task 5: Source Library Presentation And Hierarchical UI

**Files:**
- Modify: `KnowYou/Services/MyWiki/MyWikiSourceLibrary.swift`
- Modify: `KnowYou/UI/MyWiki/MyWikiSourceLibraryView.swift`
- Modify: `KnowYouTests/MyWikiSourceLibraryTests.swift`
- Create: `KnowYouTests/MyWikiSourceLibraryPresentationTests.swift`
- Modify: `KnowYou.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write failing presentation tests**

Add `KnowYouTests/MyWikiSourceLibraryPresentationTests.swift`:

```swift
import XCTest
@testable import KnowYou

final class MyWikiSourceLibraryPresentationTests: XCTestCase {
    func testSummaryCountsStatuses() {
        let presentation = MyWikiSourceLibraryPresentation(
            snapshot: MyWikiSourceCatalogSnapshot(records: [
                .presentationFixture(sourceID: "a", included: true, contentHash: "a", lastIndexedHash: nil),
                .presentationFixture(sourceID: "b", included: true, contentHash: "b", lastIndexedHash: "b"),
                .presentationFixture(sourceID: "c", included: true, contentHash: "c2", lastIndexedHash: "c1"),
                .presentationFixture(sourceID: "d", included: false, contentHash: "d", lastIndexedHash: nil)
            ]),
            query: "",
            statusFilter: nil
        )

        XCTAssertEqual(presentation.totalCount, 4)
        XCTAssertEqual(presentation.includedCount, 3)
        XCTAssertEqual(presentation.pendingCount, 1)
        XCTAssertEqual(presentation.changedCount, 1)
    }

    func testSearchFiltersByPathAndTitle() {
        let presentation = MyWikiSourceLibraryPresentation(
            snapshot: MyWikiSourceCatalogSnapshot(records: [
                .presentationFixture(sourceID: "a", displayTitle: "Budget", relativePath: "Finance/Budget.md"),
                .presentationFixture(sourceID: "b", displayTitle: "Roadmap", relativePath: "Product/Roadmap.md")
            ]),
            query: "finance",
            statusFilter: nil
        )

        XCTAssertEqual(presentation.visibleRecords.map(\.sourceID), ["a"])
    }

    func testInvertVisibleOnlyChangesFilteredRows() {
        var snapshot = MyWikiSourceCatalogSnapshot(records: [
            .presentationFixture(sourceID: "a", included: true, relativePath: "Finance/A.md"),
            .presentationFixture(sourceID: "b", included: false, relativePath: "Product/B.md")
        ])

        snapshot.apply(.invertVisible, visibleSourceIDs: ["a"])

        XCTAssertEqual(snapshot.records.first { $0.sourceID == "a" }?.included, false)
        XCTAssertEqual(snapshot.records.first { $0.sourceID == "b" }?.included, false)
    }
}

private extension MyWikiSourceCatalogRecord {
    static func presentationFixture(
        sourceID: String,
        displayTitle: String? = nil,
        included: Bool = true,
        contentHash: String = "hash",
        lastIndexedHash: String? = nil,
        relativePath: String = "Root/file.md"
    ) -> MyWikiSourceCatalogRecord {
        var record = MyWikiSourceCatalogRecord(
            sourceID: sourceID,
            sourceKind: .externalDocument,
            connectorInstanceID: nil,
            connectorID: nil,
            displayTitle: displayTitle ?? sourceID,
            relativePath: relativePath,
            sourcePath: "/tmp/\(relativePath)",
            sourceURL: nil,
            contentHash: contentHash,
            remoteUpdatedAt: nil,
            included: included,
            includedDefault: false,
            lastIndexedHash: lastIndexedHash,
            lastIndexedAt: lastIndexedHash == nil ? nil : Date(timeIntervalSince1970: 1),
            lastIngestError: nil,
            rawSourcePath: "raw/sources/\(relativePath)",
            wikiSummaryPath: nil,
            folderContext: ""
        )
        return record
    }
}
```

- [ ] **Step 2: Run presentation tests to verify they fail**

Run:

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/MyWikiSourceLibraryPresentationTests
```

Expected: FAIL because `MyWikiSourceLibraryPresentation` and bulk actions do not exist.

- [ ] **Step 3: Add presentation helpers**

Add these helpers near the top of `KnowYou/UI/MyWiki/MyWikiSourceLibraryView.swift` or in `MyWikiSourceCatalog.swift` if they are UI-independent:

```swift
enum MyWikiSourceCatalogBulkAction {
    case includeVisible
    case excludeVisible
    case invertVisible
}

struct MyWikiSourceLibraryPresentation {
    var snapshot: MyWikiSourceCatalogSnapshot
    var query: String
    var statusFilter: MyWikiSourceProcessingStatus?

    var visibleRecords: [MyWikiSourceCatalogRecord] {
        snapshot.records.filter { record in
            let matchesQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || record.displayTitle.localizedCaseInsensitiveContains(query)
                || record.relativePath.localizedCaseInsensitiveContains(query)
                || (record.connectorInstanceID?.localizedCaseInsensitiveContains(query) ?? false)
            let matchesStatus = statusFilter == nil || record.status == statusFilter
            return matchesQuery && matchesStatus
        }
    }

    var tree: MyWikiSourceCatalogNode {
        MyWikiSourceCatalogTreeBuilder().build(records: visibleRecords)
    }

    var totalCount: Int { snapshot.records.count }
    var includedCount: Int { snapshot.records.filter(\.included).count }
    var pendingCount: Int { snapshot.records.filter { $0.status == .pending }.count }
    var changedCount: Int { snapshot.records.filter { $0.status == .changed }.count }
    var failedCount: Int { snapshot.records.filter { $0.status == .failed }.count }
}

extension MyWikiSourceCatalogSnapshot {
    mutating func apply(_ action: MyWikiSourceCatalogBulkAction, visibleSourceIDs: [String]) {
        let visible = Set(visibleSourceIDs)
        for index in records.indices where visible.contains(records[index].sourceID) {
            switch action {
            case .includeVisible:
                records[index].included = true
            case .excludeVisible:
                records[index].included = false
            case .invertVisible:
                records[index].included.toggle()
            }
        }
    }
}
```

- [ ] **Step 4: Move manual imports under Manual Imports**

Modify `KnowYouTests/MyWikiSourceLibraryTests.swift` expectations:

```swift
XCTAssertTrue(FileManager.default.fileExists(atPath: root.appending(path: "raw/sources/Manual Imports/meeting.md").path))
XCTAssertTrue(FileManager.default.fileExists(atPath: root.appending(path: "raw/sources/Manual Imports/note.txt").path))
XCTAssertFalse(FileManager.default.fileExists(atPath: root.appending(path: "raw/sources/Manual Imports/image.png").path))
```

Modify `MyWikiSourceLibrary.rawSourcesDirectory(projectRoot:)`:

```swift
private func rawSourcesDirectory(projectRoot: URL) -> URL {
    projectRoot.appending(path: "raw/sources/Manual Imports", directoryHint: .isDirectory)
}
```

Keep `sourceSummaryURL(for:projectRoot:)` pointing at `wiki/sources` so previously indexed manual files can still show a summary.

- [ ] **Step 5: Replace the Source Library view state**

Modify `MyWikiSourceLibraryView` signature:

```swift
struct MyWikiSourceLibraryView: View {
    let projectRoot: URL
    let sourceVault: URL?
    let importedDocuments: [ImportedKnowledgeDocument]
    var onDidChange: () -> Void = {}

    @State private var snapshot = MyWikiSourceCatalogStore.emptySnapshot()
    @State private var query = ""
    @State private var statusFilter: MyWikiSourceProcessingStatus?
    @State private var statusMessage = "Choose which sources My Wiki can use."
}
```

Replace flat list with:

```swift
private var sourceList: some View {
    let presentation = MyWikiSourceLibraryPresentation(snapshot: snapshot, query: query, statusFilter: statusFilter)
    return ScrollView {
        LazyVStack(alignment: .leading, spacing: 6) {
            ForEach(presentation.tree.children) { node in
                sourceNode(node, depth: 0)
            }
        }
    }
}
```

Add row rendering:

```swift
@ViewBuilder
private func sourceNode(_ node: MyWikiSourceCatalogNode, depth: Int) -> some View {
    HStack(spacing: 8) {
        Image(systemName: iconName(for: node))
            .frame(width: 18)
        selectionButton(for: node)
        VStack(alignment: .leading, spacing: 2) {
            Text(node.title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
            if case .source(let record) = node.kind {
                Text(record.relativePath)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        Spacer()
        if case .source(let record) = node.kind {
            Text(record.status.rawValue)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(color(for: record.status))
        }
    }
    .padding(.leading, CGFloat(depth * 16))
    .padding(.vertical, 6)
    .padding(.horizontal, 8)
    .background(RoundedRectangle(cornerRadius: 8).fill(MyWikiTheme.cardBackground))

    ForEach(node.children) { child in
        sourceNode(child, depth: depth + 1)
    }
}
```

Add selection behavior:

```swift
private func setIncluded(_ included: Bool, for node: MyWikiSourceCatalogNode) {
    let ids = sourceIDs(in: node)
    for index in snapshot.records.indices where ids.contains(snapshot.records[index].sourceID) {
        snapshot.records[index].included = included
    }
    saveSnapshot()
}

private func sourceIDs(in node: MyWikiSourceCatalogNode) -> Set<String> {
    switch node.kind {
    case .source(let record):
        return [record.sourceID]
    case .root, .directory:
        return Set(node.children.flatMap { sourceIDs(in: $0) })
    }
}

private func saveSnapshot() {
    do {
        try MyWikiSourceCatalogStore(projectRoot: projectRoot).save(snapshot)
        statusMessage = "Saved source selection."
        onDidChange()
    } catch {
        statusMessage = error.localizedDescription
    }
}
```

- [ ] **Step 6: Update reload to refresh catalog**

Replace `reload()`:

```swift
private func reload() {
    do {
        snapshot = try MyWikiSourceCatalogBuilder().refreshCatalog(
            projectRoot: projectRoot,
            sourceVault: sourceVault,
            importedDocuments: importedDocuments
        )
        statusMessage = "\(snapshot.records.count) source(s), \(snapshot.records.filter(\.included).count) included."
    } catch {
        statusMessage = error.localizedDescription
    }
}
```

Keep manual file import buttons. Task 5 moves their destination to `raw/sources/Manual Imports`, and Task 2 catalog discovery reads that folder as `manualFile` candidates.

- [ ] **Step 7: Run Source Library tests**

Run:

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' \
  -only-testing:KnowYouTests/MyWikiSourceLibraryTests \
  -only-testing:KnowYouTests/MyWikiSourceLibraryPresentationTests
```

Expected: PASS.

- [ ] **Step 8: Run presentation tests**

Run:

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/MyWikiSourceLibraryPresentationTests
```

Expected: PASS.

- [ ] **Step 9: Commit Task 5**

```bash
git add KnowYou/Services/MyWiki/MyWikiSourceLibrary.swift KnowYou/UI/MyWiki/MyWikiSourceLibraryView.swift KnowYouTests/MyWikiSourceLibraryTests.swift KnowYouTests/MyWikiSourceLibraryPresentationTests.swift KnowYou.xcodeproj/project.pbxproj
git commit -m "Show hierarchical My Wiki source catalog"
```

---

### Task 6: Wire Update My Wiki To Catalog Selection

**Files:**
- Modify: `KnowYou/UI/MyWiki/MyWikiPanel.swift`
- Modify: `KnowYou/UI/KnowledgeOntology/KnowledgeOntologyPanel.swift`
- Modify: `KnowYou/UI/MainWindowView.swift`
- Modify: `KnowYouTests/MyWikiProjectExporterTests.swift`
- Modify: `KnowYouTests/MyWikiSourceCatalogBuilderTests.swift`
- Modify: `KnowYouTests/MyWikiPipelineBridgeTests.swift`

- [ ] **Step 1: Update panel signatures**

Modify `KnowledgeOntologyPanel`:

```swift
struct KnowledgeOntologyPanel: View {
    let sourceVault: URL?
    let projectRoot: URL?
    let developmentSourceURL: URL
    let bundledHelperAppURL: URL?
    let importedDocuments: [ImportedKnowledgeDocument]
    @Binding var selectedEntry: MyWikiEntry?

    var body: some View {
        MyWikiPanel(
            sourceVault: sourceVault,
            projectRoot: projectRoot,
            developmentSourceURL: developmentSourceURL,
            bundledHelperAppURL: bundledHelperAppURL,
            importedDocuments: importedDocuments,
            selectedEntry: $selectedEntry
        )
    }
}
```

Modify `MyWikiPanel`:

```swift
struct MyWikiPanel: View {
    let sourceVault: URL?
    let projectRoot: URL?
    let developmentSourceURL: URL
    let bundledHelperAppURL: URL?
    let importedDocuments: [ImportedKnowledgeDocument]
    @Binding var selectedEntry: MyWikiEntry?

    @State private var query = ""
    @State private var snapshot = MyWikiDashboardSnapshot.empty
    @State private var duplicateSuggestions: [MyWikiDuplicateSuggestion] = []
    @State private var statusMessage = "Ready"
    @State private var ingestProgress: MyWikiIngestProgress?
    @State private var isSyncing = false
}
```

Modify `MainWindowView.knowledgeOntologyWorkspace`:

```swift
KnowledgeOntologyPanel(
    sourceVault: appState.environment?.vaultURL,
    projectRoot: knowledgeOntologyProjectRoot,
    developmentSourceURL: KnowledgeOntologyLauncher.defaultDevelopmentSourceURL(),
    bundledHelperAppURL: KnowledgeOntologyLauncher.defaultBundledHelperAppURL(),
    importedDocuments: appState.knowledgeDocumentsByConnector.values.flatMap { $0 },
    selectedEntry: $selectedMyWikiEntry
)
```

- [ ] **Step 2: Pass catalog inputs into Source Library**

Modify the sheet in `MyWikiPanel`:

```swift
.sheet(isPresented: $isShowingSourceLibrary) {
    if let projectRoot {
        MyWikiSourceLibraryView(
            projectRoot: projectRoot,
            sourceVault: sourceVault,
            importedDocuments: importedDocuments
        ) {
            loadIngestProgress()
            loadDashboard()
        }
    } else {
        Text("My Wiki folder is not available.")
            .padding(24)
    }
}
```

- [ ] **Step 3: Replace syncDiaries pipeline with catalog update plan**

Modify `syncDiaries()` in `MyWikiPanel`:

```swift
private func syncDiaries() {
    guard let projectRoot else { return }
    guard !isSyncing else { return }
    isSyncing = true
    statusMessage = "Updating My Wiki sources..."
    loadIngestProgress()

    let target = pipelineTarget
    let sourceVault = sourceVault
    let importedDocuments = importedDocuments
    Task {
        let outcome = await Task.detached(priority: .userInitiated) {
            do {
                try MyWikiProjectExporter().ensureProject(at: projectRoot)
                let builder = MyWikiSourceCatalogBuilder()
                var snapshot = try builder.refreshCatalog(
                    projectRoot: projectRoot,
                    sourceVault: sourceVault,
                    importedDocuments: importedDocuments
                )
                let plan = builder.ingestPlan(
                    snapshot: snapshot,
                    maxSources: MyWikiIngestBatchPolicy.maxSourcesPerRun
                )
                guard plan.sources.isEmpty == false else {
                    return "My Wiki sources are already up to date."
                }

                let materialized = try builder.materialize(
                    plan: plan,
                    from: snapshot,
                    projectRoot: projectRoot
                )
                do {
                    try MyWikiPipelineBridge().runIngest(
                        target: target,
                        projectRoot: projectRoot,
                        manifestURL: materialized.manifestURL
                    )
                    snapshot = builder.mark(plan: plan, succeededIn: snapshot, at: Date())
                    try MyWikiSourceCatalogStore(projectRoot: projectRoot).save(snapshot)
                    return "Updated \(materialized.materializedCount) My Wiki source(s)."
                } catch {
                    snapshot = builder.mark(plan: plan, failedWith: error.localizedDescription, in: snapshot)
                    try? MyWikiSourceCatalogStore(projectRoot: projectRoot).save(snapshot)
                    return "My Wiki source update failed: \(error.localizedDescription)"
                }
            } catch {
                return error.localizedDescription
            }
        }.value

        await MainActor.run {
            statusMessage = outcome
            isSyncing = false
            loadDashboard()
        }
    }
}
```

- [ ] **Step 4: Update old exporter tests to reflect catalog ownership**

Keep `MyWikiProjectExporterTests.testSyncDiariesExportsKnowYouSourceTags` passing by leaving `syncDiaries` intact for compatibility, or rename it to a compatibility test. Add a new assertion in `MyWikiSourceCatalogBuilderTests` that catalog materialization writes the same frontmatter:

```swift
let exported = try String(
    contentsOf: fixture.projectRoot.appending(path: "raw/sources/My Diary/knowyou-diary-2026-05-27.md"),
    encoding: .utf8
)
XCTAssertTrue(exported.contains("tags: [knowyou, diary]"), exported)
```

- [ ] **Step 5: Run focused Swift tests**

Run:

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' \
  -only-testing:KnowYouTests/MyWikiSourceCatalogTests \
  -only-testing:KnowYouTests/MyWikiSourceCatalogBuilderTests \
  -only-testing:KnowYouTests/MyWikiSourceLibraryPresentationTests \
  -only-testing:KnowYouTests/MyWikiPipelineBridgeTests \
  -only-testing:KnowYouTests/MyWikiProjectExporterTests
```

Expected: PASS.

- [ ] **Step 6: Commit Task 6**

```bash
git add KnowYou/UI/MyWiki/MyWikiPanel.swift KnowYou/UI/KnowledgeOntology/KnowledgeOntologyPanel.swift KnowYou/UI/MainWindowView.swift KnowYouTests/MyWikiProjectExporterTests.swift KnowYouTests/MyWikiSourceCatalogBuilderTests.swift
git commit -m "Wire My Wiki updates through source catalog"
```

---

### Task 7: Documentation And Full Verification

**Files:**
- Modify: `docs/architecture.md`
- Modify: `docs/requirements-spec.md`

- [ ] **Step 1: Update architecture docs**

Add a My Wiki Source Catalog paragraph to `docs/architecture.md` near the My Wiki/Knowledge Ontology section:

```markdown
### My Wiki Source Catalog

My Wiki uses a project-local source catalog at `.knowyou/source-catalog.json` to separate document discovery from LLM processing permission. Diaries are included by default and external documents are opt-in. The catalog stores source identity, inclusion state, content hash, last indexed hash, and source hierarchy. `Update My Wiki` materializes only included pending or changed sources into `raw/sources` and passes an explicit ingest manifest to `llm_wiki`.
```

- [ ] **Step 2: Update requirements spec**

Add requirements to `docs/requirements-spec.md`:

```markdown
### My Wiki Source Selection

- KnowYou must show My Wiki candidate sources in a hierarchy that preserves source roots and nested folders.
- Diary sources must be included by default, and users must be able to exclude them.
- External source documents must be excluded by default until the user includes them.
- My Wiki updates must process only included sources that are new, changed, or previously failed.
- Excluding a previously indexed source must not delete existing wiki source summaries, entity pages, or concept pages.
```

- [ ] **Step 3: Run targeted Swift tests**

Run:

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' \
  -only-testing:KnowYouTests/MyWikiSourceCatalogTests \
  -only-testing:KnowYouTests/MyWikiSourceCatalogBuilderTests \
  -only-testing:KnowYouTests/MyWikiSourceLibraryPresentationTests \
  -only-testing:KnowYouTests/MyWikiPipelineBridgeTests
```

Expected: PASS.

- [ ] **Step 4: Run targeted llm_wiki tests**

Run:

```bash
npm --prefix ThirdParty/llm_wiki test -- src/headless/knowyou-ingest.test.ts
```

Expected: PASS.

- [ ] **Step 5: Run repository-required full test**

Run:

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS'
```

Expected: PASS.

- [ ] **Step 6: Run repository-required build**

Run:

```bash
xcodebuild build -scheme KnowYou -destination 'platform=macOS'
```

Expected: PASS.

- [ ] **Step 7: Review diff**

Run:

```bash
git diff --stat origin/main...HEAD
git diff --check
git status -sb
```

Expected:

- `git diff --check` has no output.
- `git status -sb` shows only intentional changes or a clean tree after commit.

- [ ] **Step 8: Commit docs and any verification-only fixes**

```bash
git add docs/architecture.md docs/requirements-spec.md
git commit -m "Document My Wiki source catalog"
```

---

## Self-Review Notes

- Spec coverage: Tasks 1-2 cover persistent state, diary/external defaults, hierarchy, changed/indexed status, materialization, and exclusion semantics. Task 3 covers explicit manifest and raw source scan replacement. Task 4 wires the bridge. Task 5 covers hierarchical Source Library UI and bulk visible operations. Task 6 wires Update My Wiki. Task 7 covers required docs and verification.
- Scope: This is one coherent subsystem because the UI selection layer, materialization, and manifest ingest must land together to avoid a state where the UI permits selection but the pipeline still processes everything.
- Placeholder scan: This plan intentionally defines concrete file paths, test names, commands, and expected outputs. Code snippets define the names used by later tasks.
