import XCTest
@testable import KnowYou

final class KnowledgeSourceContentViewTests: XCTestCase {
    func testPresentationShowsEmptyStateWhenConnectorHasNoDocuments() {
        let connector = KnowledgeConnectorInstanceConfig(
            id: "feishu-main",
            connectorID: .feishuImport,
            displayName: "飞书文档",
            sourcePath: "doc-token",
            isEnabled: true
        )

        let presentation = KnowledgeSourceContentPresentation(
            connector: connector,
            documents: [],
            selectedDocumentID: nil,
            selectedMarkdown: nil,
            statusMessage: nil
        )

        XCTAssertEqual(presentation.title, "飞书文档")
        XCTAssertEqual(presentation.state, .empty)
        XCTAssertEqual(presentation.emptyTitle, "No documents yet")
        XCTAssertTrue(presentation.showsSyncNow)
    }

    func testPresentationShowsSelectedDocumentMarkdown() {
        let connector = KnowledgeConnectorInstanceConfig(
            id: "feishu-main",
            connectorID: .feishuImport,
            displayName: "飞书文档",
            sourcePath: "doc-token",
            isEnabled: true
        )
        let document = ImportedKnowledgeDocument(
            id: "doc-1",
            connectorInstanceID: "feishu-main",
            connectorID: .feishuImport,
            remoteID: "remote-1",
            title: "Project Plan",
            sourcePath: nil,
            remoteURL: nil,
            mimeType: "text/markdown",
            contentHash: "hash",
            remoteUpdatedAt: nil,
            firstImportedAt: Date(timeIntervalSince1970: 1_778_000_000),
            lastSyncedAt: Date(timeIntervalSince1970: 1_778_000_100),
            deletedAt: nil,
            localContentPath: "/tmp/content.md",
            localMetadataPath: "/tmp/metadata.json",
            normalizationVersion: 1,
            originKind: "feishu"
        )

        let presentation = KnowledgeSourceContentPresentation(
            connector: connector,
            documents: [document],
            selectedDocumentID: "doc-1",
            selectedMarkdown: "# Project Plan",
            statusMessage: "Imported 1 document"
        )

        XCTAssertEqual(presentation.state, .documents)
        XCTAssertEqual(presentation.documentRows.map(\.title), ["Project Plan"])
        XCTAssertEqual(presentation.documentRows.first?.isSelected, true)
        XCTAssertEqual(presentation.markdown, "# Project Plan")
        XCTAssertEqual(presentation.statusMessage, "Imported 1 document")
    }

    func testPresentationClearsMarkdownWhenSelectedDocumentDoesNotMatchCurrentRows() {
        let connector = KnowledgeConnectorInstanceConfig(
            id: "feishu-main",
            connectorID: .feishuImport,
            displayName: "飞书文档",
            sourcePath: "doc-token",
            isEnabled: true
        )
        let document = makeDocument(id: "doc-1", title: "Project Plan")

        let missingSelectionPresentation = KnowledgeSourceContentPresentation(
            connector: connector,
            documents: [document],
            selectedDocumentID: "stale-doc",
            selectedMarkdown: "# Stale",
            statusMessage: nil
        )

        XCTAssertNil(missingSelectionPresentation.markdown)
        XCTAssertFalse(missingSelectionPresentation.documentRows.contains { $0.isSelected })

        let unselectedPresentation = KnowledgeSourceContentPresentation(
            connector: connector,
            documents: [document],
            selectedDocumentID: nil,
            selectedMarkdown: "# Unmatched",
            statusMessage: nil
        )

        XCTAssertNil(unselectedPresentation.markdown)
        XCTAssertFalse(unselectedPresentation.documentRows.contains { $0.isSelected })
    }

    func testPresentationDocumentSubtitlePrefersSourcePathThenRemoteURLThenMimeType() {
        let connector = KnowledgeConnectorInstanceConfig(
            id: "feishu-main",
            connectorID: .feishuImport,
            displayName: "飞书文档",
            sourcePath: "doc-token",
            isEnabled: true
        )
        let sourcePathDocument = makeDocument(
            id: "doc-1",
            title: "Source Path",
            sourcePath: "/Users/me/plan.md",
            remoteURL: "https://example.com/plan",
            mimeType: "text/markdown"
        )
        let remoteURLDocument = makeDocument(
            id: "doc-2",
            title: "Remote URL",
            sourcePath: nil,
            remoteURL: "https://example.com/remote",
            mimeType: "application/pdf"
        )
        let mimeTypeDocument = makeDocument(
            id: "doc-3",
            title: "MIME Type",
            sourcePath: nil,
            remoteURL: nil,
            mimeType: "text/plain"
        )
        let blankSourcePathDocument = makeDocument(
            id: "doc-4",
            title: "Blank Source Path",
            sourcePath: "   ",
            remoteURL: "https://example.com/fallback",
            mimeType: "text/html"
        )

        let presentation = KnowledgeSourceContentPresentation(
            connector: connector,
            documents: [sourcePathDocument, remoteURLDocument, mimeTypeDocument, blankSourcePathDocument],
            selectedDocumentID: nil,
            selectedMarkdown: nil,
            statusMessage: nil
        )

        XCTAssertEqual(
            presentation.documentRows.map(\.subtitle),
            [
                "/Users/me/plan.md",
                "https://example.com/remote",
                "text/plain",
                "https://example.com/fallback"
            ]
        )
    }

    func testPresentationShowsDisabledStateForDisabledConnector() {
        let connector = KnowledgeConnectorInstanceConfig(
            id: "drive-main",
            connectorID: .googleDriveImport,
            displayName: "Google Drive",
            accountID: "me@example.com",
            isEnabled: false
        )

        let presentation = KnowledgeSourceContentPresentation(
            connector: connector,
            documents: [],
            selectedDocumentID: nil,
            selectedMarkdown: nil,
            statusMessage: nil
        )

        XCTAssertEqual(presentation.state, .disabled)
        XCTAssertEqual(presentation.emptyTitle, "Connector disabled")
        XCTAssertFalse(presentation.showsSyncNow)
    }

    private func makeDocument(
        id: String,
        title: String,
        sourcePath: String? = nil,
        remoteURL: String? = nil,
        mimeType: String = "text/markdown"
    ) -> ImportedKnowledgeDocument {
        ImportedKnowledgeDocument(
            id: id,
            connectorInstanceID: "feishu-main",
            connectorID: .feishuImport,
            remoteID: "remote-\(id)",
            title: title,
            sourcePath: sourcePath,
            remoteURL: remoteURL,
            mimeType: mimeType,
            contentHash: "hash-\(id)",
            remoteUpdatedAt: nil,
            firstImportedAt: Date(timeIntervalSince1970: 1_778_000_000),
            lastSyncedAt: Date(timeIntervalSince1970: 1_778_000_100),
            deletedAt: nil,
            localContentPath: "/tmp/\(id).md",
            localMetadataPath: "/tmp/\(id).json",
            normalizationVersion: 1,
            originKind: "feishu"
        )
    }
}
