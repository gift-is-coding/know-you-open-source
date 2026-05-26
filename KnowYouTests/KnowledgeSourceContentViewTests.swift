import XCTest
@testable import KnowYou

final class KnowledgeSourceContentViewTests: XCTestCase {
    func testPresentationShowsEmptyStateWithoutIndexOrReadingActions() {
        let connector = makeConnector()

        let presentation = KnowledgeSourceContentPresentation(
            connector: connector,
            documents: [],
            selectedDocumentID: nil,
            selectedMarkdown: nil,
            statusMessage: "Refreshed 314 documents"
        )

        XCTAssertEqual(presentation.title, "飞书文档")
        XCTAssertEqual(presentation.state, .empty)
        XCTAssertEqual(presentation.emptyTitle, "No document selected")
        XCTAssertEqual(
            presentation.emptyMessage,
            "Choose a Markdown or text file from the source tree on the left."
        )
        XCTAssertFalse(presentation.showsDocumentList)
        XCTAssertFalse(presentation.showsRefreshAction)
        XCTAssertFalse(presentation.showsConfigureAction)
        XCTAssertNil(presentation.statusMessage)
    }

    func testPresentationShowsOnlySelectedDocumentMarkdownWithoutIndexChrome() {
        let connector = makeConnector()
        let document = makeDocument(id: "doc-1", title: "Project Plan")

        let presentation = KnowledgeSourceContentPresentation(
            connector: connector,
            documents: [document],
            selectedDocumentID: "doc-1",
            selectedMarkdown: "# Project Plan",
            statusMessage: "Refreshed 1 document"
        )

        XCTAssertEqual(presentation.state, .documents)
        XCTAssertEqual(presentation.markdown, "# Project Plan")
        XCTAssertFalse(presentation.showsDocumentList)
        XCTAssertFalse(presentation.showsRefreshAction)
        XCTAssertFalse(presentation.showsConfigureAction)
        XCTAssertNil(presentation.statusMessage)
    }

    func testPresentationStripsFrontmatterBeforeMarkdownPreview() {
        let connector = makeConnector()
        let document = makeDocument(id: "doc-1", title: "Project Plan")

        let presentation = KnowledgeSourceContentPresentation(
            connector: connector,
            documents: [document],
            selectedDocumentID: "doc-1",
            selectedMarkdown: """
            ---
            source: feishu
            title: Project Plan
            ---

            # Project Plan

            **Important** item
            """,
            statusMessage: nil
        )

        XCTAssertEqual(
            presentation.markdown,
            """
            # Project Plan

            **Important** item
            """
        )
    }

    func testPresentationClearsMarkdownWhenSelectedDocumentDoesNotMatchCurrentSource() {
        let connector = makeConnector()
        let document = makeDocument(id: "doc-1", title: "Project Plan")

        let presentation = KnowledgeSourceContentPresentation(
            connector: connector,
            documents: [document],
            selectedDocumentID: "stale-doc",
            selectedMarkdown: "# Stale",
            statusMessage: nil
        )

        XCTAssertNil(presentation.markdown)
    }

    func testPresentationShowsDisabledStateWithoutRefreshAction() {
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
        XCTAssertFalse(presentation.showsRefreshAction)
    }

    private func makeConnector() -> KnowledgeConnectorInstanceConfig {
        KnowledgeConnectorInstanceConfig(
            id: "feishu-main",
            connectorID: .feishuImport,
            displayName: "飞书文档",
            sourcePath: "doc-token",
            isEnabled: true
        )
    }

    private func makeDocument(
        id: String,
        title: String
    ) -> ImportedKnowledgeDocument {
        ImportedKnowledgeDocument(
            id: id,
            connectorInstanceID: "feishu-main",
            connectorID: .feishuImport,
            remoteID: "remote-\(id)",
            title: title,
            sourcePath: "/tmp/\(id).md",
            remoteURL: nil,
            mimeType: "text/markdown",
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
