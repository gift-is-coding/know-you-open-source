import XCTest
@testable import KnowYou

final class MyWikiSourceLibraryPresentationTests: XCTestCase {
    func testCountsSummarizeCatalogStatus() {
        let snapshot = MyWikiSourceCatalogSnapshot(records: [
            record(sourceID: "pending", included: true, relativePath: "My Diary/2026-05-27.md"),
            record(
                sourceID: "indexed",
                sourceKind: .manualFile,
                included: true,
                relativePath: "Manual Imports/indexed.md",
                contentHash: "hash-indexed",
                lastIndexedHash: "hash-indexed"
            ),
            record(sourceID: "changed", included: true, relativePath: "Local Folder/main/changed.md", contentHash: "new", lastIndexedHash: "old"),
            record(sourceID: "failed", included: true, relativePath: "Local Folder/main/failed.md", lastIngestError: "failed"),
            record(sourceID: "excluded", included: false, relativePath: "Local Folder/main/excluded.md")
        ])

        let presentation = MyWikiSourceLibraryPresentation(snapshot: snapshot)

        XCTAssertEqual(presentation.totalCount, 5)
        XCTAssertEqual(presentation.includedCount, 4)
        XCTAssertEqual(presentation.pendingCount, 1)
        XCTAssertEqual(presentation.changedCount, 1)
        XCTAssertEqual(presentation.failedCount, 1)
        XCTAssertEqual(presentation.visibleRecords.map(\.sourceID), ["changed", "excluded", "failed", "indexed", "pending"])
    }

    func testQueryMatchesTitleAndPath() {
        let snapshot = MyWikiSourceCatalogSnapshot(records: [
            record(sourceID: "design", displayTitle: "Product Strategy", relativePath: "Local Folder/main/notes.md"),
            record(sourceID: "path", sourceKind: .manualFile, displayTitle: "Readme", relativePath: "Manual Imports/Research/AI.md"),
            record(sourceID: "hidden", sourceKind: .manualFile, displayTitle: "Finance", relativePath: "Manual Imports/Budget.md")
        ])

        XCTAssertEqual(
            MyWikiSourceLibraryPresentation(snapshot: snapshot, query: "strategy").visibleRecords.map(\.sourceID),
            ["design"]
        )
        XCTAssertEqual(
            MyWikiSourceLibraryPresentation(snapshot: snapshot, query: "Research").visibleRecords.map(\.sourceID),
            ["path"]
        )
        XCTAssertEqual(
            MyWikiSourceLibraryPresentation(snapshot: snapshot, query: "Manual Uploads").visibleRecords.map(\.sourceID),
            ["hidden", "path"]
        )
    }

    func testStatusFilterLimitsVisibleRecords() {
        var indexed = record(sourceID: "indexed", sourceKind: .manualFile, included: true, relativePath: "Manual Imports/indexed.md")
        indexed.lastIndexedHash = indexed.contentHash
        let snapshot = MyWikiSourceCatalogSnapshot(records: [
            record(sourceID: "pending", sourceKind: .manualFile, included: true, relativePath: "Manual Imports/pending.md"),
            indexed,
            record(sourceID: "excluded", sourceKind: .manualFile, included: false, relativePath: "Manual Imports/excluded.md")
        ])

        let presentation = MyWikiSourceLibraryPresentation(snapshot: snapshot, statusFilter: .indexed)

        XCTAssertEqual(presentation.visibleRecords.map(\.sourceID), ["indexed"])
        XCTAssertEqual(presentation.tree.children.map(\.title), ["Manual Uploads"])
        XCTAssertEqual(presentation.tree.children.first?.children.map(\.title), ["indexed"])
    }

    func testIncludedFilterLimitsVisibleRecords() {
        let snapshot = MyWikiSourceCatalogSnapshot(records: [
            record(sourceID: "included", included: true, relativePath: "Manual Imports/included.md"),
            record(sourceID: "excluded", included: false, relativePath: "Manual Imports/excluded.md")
        ])

        let presentation = MyWikiSourceLibraryPresentation(snapshot: snapshot, includedOnly: true)

        XCTAssertEqual(presentation.visibleRecords.map(\.sourceID), ["included"])
    }

    func testManualImportsAreDisplayedAsManualUploadsWithoutChangingRawPath() throws {
        let manual = record(
            sourceID: "manual",
            sourceKind: .manualFile,
            relativePath: "Manual Imports/Research/AI.md"
        )
        let snapshot = MyWikiSourceCatalogSnapshot(records: [manual])

        let presentation = MyWikiSourceLibraryPresentation(snapshot: snapshot)

        XCTAssertEqual(MyWikiSourceLibraryDisplayPolicy.displayRelativePath(for: manual), "Manual Uploads/Research/AI.md")
        XCTAssertEqual(presentation.visibleRecords.first?.relativePath, "Manual Imports/Research/AI.md")
        XCTAssertEqual(presentation.tree.children.map(\.title), ["Manual Uploads"])
        let manualUploads = try XCTUnwrap(presentation.tree.children.first)
        XCTAssertNil(manualUploads.children.first { $0.title == "Manual Imports" })
    }

    func testSourceLibraryActionCopyClarifiesAutosaveAndManualUpdate() {
        XCTAssertEqual(MyWikiSourceLibraryActionCopy.closeTitle, "Close")
        XCTAssertEqual(MyWikiSourceLibraryActionCopy.updateTitle, "Update My Wiki")
        XCTAssertEqual(MyWikiSourceLibraryActionCopy.manualUploadsTitle, "Manual Uploads")
        XCTAssertTrue(MyWikiSourceLibraryActionCopy.autosaveExplanation.contains("saved automatically"))
        XCTAssertTrue(MyWikiSourceLibraryActionCopy.autosaveExplanation.contains("Update My Wiki"))
    }

    func testSourceLibraryLayoutGivesMajorityWidthToSourceTree() {
        XCTAssertGreaterThanOrEqual(MyWikiSourceLibraryLayoutPolicy.minimumWidth, 980)
        XCTAssertGreaterThanOrEqual(MyWikiSourceLibraryLayoutPolicy.minimumHeight, 680)
        XCTAssertLessThanOrEqual(MyWikiSourceLibraryLayoutPolicy.preferredWidth, 1200)
        XCTAssertLessThanOrEqual(MyWikiSourceLibraryLayoutPolicy.preferredHeight, 820)
        XCTAssertGreaterThanOrEqual(MyWikiSourceLibraryLayoutPolicy.managementColumnWidth, 330)
        XCTAssertGreaterThanOrEqual(MyWikiSourceLibraryLayoutPolicy.sourceTreeWidthRatio, 0.65)
        XCTAssertLessThanOrEqual(MyWikiSourceLibraryLayoutPolicy.sourceTreeWidthRatio, 0.70)
        XCTAssertTrue(MyWikiSourceLibraryLayoutPolicy.usesScrollableManagementPane)
        XCTAssertFalse(MyWikiSourceLibraryLayoutPolicy.showsSeparateSelectionPanel)
        XCTAssertTrue(MyWikiSourceLibraryLayoutPolicy.statusBadgesFilterSources)
        XCTAssertTrue(MyWikiSourceLibraryLayoutPolicy.directoryRowsToggleOnDoubleClick)
    }

    func testSourceLibraryLayoutResolvesInsideVisibleFrame() {
        let compact = MyWikiSourceLibraryLayoutPolicy.resolvedPresentationSize(
            forVisibleFrame: CGSize(width: 1280, height: 800)
        )
        let regular = MyWikiSourceLibraryLayoutPolicy.resolvedPresentationSize(
            forVisibleFrame: CGSize(width: 1440, height: 900)
        )

        XCTAssertLessThanOrEqual(compact.width, 1180)
        XCTAssertLessThanOrEqual(compact.height, 720)
        XCTAssertLessThanOrEqual(regular.width, 1200)
        XCTAssertLessThanOrEqual(regular.height, 820)
    }

    func testSourceTreeDefaultsToCollapsedAndKeepsExpandedDirectories() throws {
        let snapshot = MyWikiSourceCatalogSnapshot(records: [
            record(sourceID: "a", relativePath: "Feishu Docs/import/minutes/a.md"),
            record(sourceID: "b", relativePath: "Feishu Docs/import/minutes/b.md"),
            record(sourceID: "c", relativePath: "My Diary/2026-05-27.md")
        ])
        let tree = MyWikiSourceLibraryPresentation(snapshot: snapshot).tree

        XCTAssertEqual(MyWikiSourceLibraryTreeExpansion.defaultExpandedDirectoryIDs, [])
        XCTAssertEqual(
            MyWikiSourceLibraryTreeExpansion.visibleNodeIDs(
                from: tree.children,
                expandedDirectoryIDs: MyWikiSourceLibraryTreeExpansion.defaultExpandedDirectoryIDs
            ),
            ["Feishu Docs", "My Diary"]
        )

        let expandedIDs: Set<String> = ["Feishu Docs", "Feishu Docs/import"]
        XCTAssertEqual(
            MyWikiSourceLibraryTreeExpansion.visibleNodeIDs(
                from: tree.children,
                expandedDirectoryIDs: expandedIDs
            ),
            ["Feishu Docs", "Feishu Docs/import", "Feishu Docs/import/minutes", "My Diary"]
        )

        let rebuiltTree = MyWikiSourceLibraryPresentation(snapshot: snapshot).tree
        XCTAssertEqual(
            MyWikiSourceLibraryTreeExpansion.visibleNodeIDs(
                from: rebuiltTree.children,
                expandedDirectoryIDs: expandedIDs
            ),
            ["Feishu Docs", "Feishu Docs/import", "Feishu Docs/import/minutes", "My Diary"]
        )
    }

    func testInvertVisibleOnlyMutatesMatchingSourceIDs() {
        var snapshot = MyWikiSourceCatalogSnapshot(records: [
            record(sourceID: "visible-included", included: true),
            record(sourceID: "visible-excluded", included: false),
            record(sourceID: "hidden-included", included: true)
        ])

        snapshot.apply(action: .invertVisible, visibleSourceIDs: ["visible-included", "visible-excluded"])

        XCTAssertEqual(snapshot.records.first { $0.sourceID == "visible-included" }?.included, false)
        XCTAssertEqual(snapshot.records.first { $0.sourceID == "visible-excluded" }?.included, true)
        XCTAssertEqual(snapshot.records.first { $0.sourceID == "hidden-included" }?.included, true)
    }

    func testTreePreservesHierarchyAndMixedDirectoryState() throws {
        let snapshot = MyWikiSourceCatalogSnapshot(records: [
            record(sourceID: "a", included: true, relativePath: "Local Folder/main/Projects/A/a.md"),
            record(sourceID: "b", included: false, relativePath: "Local Folder/main/Projects/A/b.md"),
            record(sourceID: "c", included: true, relativePath: "My Diary/2026-05-27.md")
        ])

        let presentation = MyWikiSourceLibraryPresentation(snapshot: snapshot)
        let localFolder = try XCTUnwrap(presentation.tree.children.first { $0.title == "Local Folder" })
        let main = try XCTUnwrap(localFolder.children.first { $0.title == "main" })
        let projects = try XCTUnwrap(main.children.first { $0.title == "Projects" })
        let folderA = try XCTUnwrap(projects.children.first { $0.title == "A" })

        XCTAssertEqual(folderA.selectionState, .mixed)
        XCTAssertEqual(folderA.children.map(\.title), ["a", "b"])
    }

    private func record(
        sourceID: String,
        sourceKind: MyWikiSourceKind = .externalDocument,
        displayTitle: String? = nil,
        included: Bool = true,
        relativePath: String = "Manual Imports/file.md",
        contentHash: String = "hash",
        lastIndexedHash: String? = nil,
        lastIngestError: String? = nil
    ) -> MyWikiSourceCatalogRecord {
        MyWikiSourceCatalogRecord(
            sourceID: sourceID,
            sourceKind: sourceKind,
            connectorInstanceID: nil,
            connectorID: nil,
            displayTitle: displayTitle ?? URL(fileURLWithPath: relativePath).deletingPathExtension().lastPathComponent,
            relativePath: relativePath,
            sourcePath: "/tmp/\(relativePath)",
            sourceURL: nil,
            contentHash: contentHash,
            remoteUpdatedAt: nil,
            included: included,
            includedDefault: included,
            lastIndexedHash: lastIndexedHash,
            lastIndexedAt: nil,
            lastIngestError: lastIngestError,
            rawSourcePath: "raw/sources/\(relativePath)",
            wikiSummaryPath: nil,
            folderContext: String(relativePath.split(separator: "/").dropLast().joined(separator: "/"))
        )
    }
}
