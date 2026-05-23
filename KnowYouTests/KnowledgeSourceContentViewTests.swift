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
}
