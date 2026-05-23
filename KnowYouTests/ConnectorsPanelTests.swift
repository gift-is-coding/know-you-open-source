import XCTest
@testable import KnowYou

final class ConnectorsPanelTests: XCTestCase {
    func testConnectorsManagementFormStateStartsWithAPIFormVisible() {
        let state = ConnectorsManagementFormState(startsWithAddAPIForm: true)

        XCTAssertTrue(state.isShowingAPIConnectorForm)
    }

    func testConnectorsManagementFormStateStartsWithAPIFormHidden() {
        let state = ConnectorsManagementFormState(startsWithAddAPIForm: false)

        XCTAssertFalse(state.isShowingAPIConnectorForm)
    }

    func testConnectorsManagementFormStateOpensWhenAddAPIFormFocusBecomesTrue() {
        var state = ConnectorsManagementFormState(startsWithAddAPIForm: false)

        state.apply(startsWithAddAPIForm: true)

        XCTAssertTrue(state.isShowingAPIConnectorForm)
    }

    func testConnectorsManagementFormStateDoesNotCloseWhenAddAPIFormFocusBecomesFalse() {
        var state = ConnectorsManagementFormState(startsWithAddAPIForm: true)

        state.apply(startsWithAddAPIForm: false)

        XCTAssertTrue(state.isShowingAPIConnectorForm)
    }

    func testConnectorsManagementPresentationCanStartInAddAPIFormMode() {
        let presentation = ConnectorsManagementPresentation(
            panelPresentation: ConnectorsPanelPresentation(
                syncMemoryConfig: .default,
                knowledgeImportConfig: .default,
                syncMemoryStatusMessage: nil,
                knowledgeImportStatusMessage: nil
            ),
            surface: .otherSourceRoot,
            startsWithAddAPIForm: true
        )

        XCTAssertTrue(presentation.startsWithAddAPIForm)
        XCTAssertEqual(presentation.panelPresentation.importRows, [])
    }

    func testOtherSourceRootPresentationUsesMockupCopyAndEmptyState() {
        let presentation = ConnectorsManagementPresentation(
            panelPresentation: ConnectorsPanelPresentation(
                syncMemoryConfig: .default,
                knowledgeImportConfig: .default,
                syncMemoryStatusMessage: nil,
                knowledgeImportStatusMessage: nil
            ),
            surface: .otherSourceRoot,
            startsWithAddAPIForm: false
        )

        XCTAssertEqual(presentation.title, "Other Source")
        XCTAssertEqual(
            presentation.subtitle,
            "Sync files from connected sources into a local Markdown library."
        )
        XCTAssertEqual(
            presentation.emptyImportMessage,
            "No sources connected yet. Add a connector and it will appear as a first-level item in the sidebar."
        )
        XCTAssertFalse(presentation.showsDailyMemoryExport)
    }

    func testLegacyConnectorsSheetPresentationKeepsMixedExportAndImportCopy() {
        let presentation = ConnectorsManagementPresentation(
            panelPresentation: ConnectorsPanelPresentation(
                syncMemoryConfig: .default,
                knowledgeImportConfig: .default,
                syncMemoryStatusMessage: nil,
                knowledgeImportStatusMessage: nil
            ),
            surface: .connectorsSheet,
            startsWithAddAPIForm: false
        )

        XCTAssertEqual(presentation.title, "Connectors")
        XCTAssertEqual(
            presentation.subtitle,
            "Manage daily memory exports and local-first knowledge imports."
        )
        XCTAssertEqual(presentation.emptyImportMessage, "No connectors configured")
        XCTAssertTrue(presentation.showsDailyMemoryExport)
    }

    func testPresentationSeparatesDailyExportAndKnowledgeImportRows() {
        var syncMemoryConfig = SyncMemoryConfig.default
        syncMemoryConfig.obsidian.isEnabled = true
        syncMemoryConfig.obsidian.resolvedPath = "/vault/KnowYou/Daily Memories"
        syncMemoryConfig.openClaw.isEnabled = false

        let knowledgeImportConfig = KnowledgeImportConfig(
            isImportEnabled: true,
            dailyImportHour: 7,
            dailyImportMinute: 30,
            connectorInstances: [
                KnowledgeConnectorInstanceConfig(
                    id: "obsidian-main",
                    connectorID: .obsidianImport,
                    displayName: "Vault",
                    sourcePath: "/vault",
                    isEnabled: true
                ),
                KnowledgeConnectorInstanceConfig(
                    id: "notion-main",
                    connectorID: .notionImport,
                    displayName: "Notion",
                    accountID: "workspace@example.com",
                    isEnabled: false
                ),
            ]
        )

        let presentation = ConnectorsPanelPresentation(
            syncMemoryConfig: syncMemoryConfig,
            knowledgeImportConfig: knowledgeImportConfig,
            syncMemoryStatusMessage: "Export ready",
            knowledgeImportStatusMessage: "Import ready"
        )

        XCTAssertEqual(presentation.exportRows.map(\.title), ["Obsidian Export", "OpenClaw Export"])
        XCTAssertEqual(presentation.exportRows.map(\.direction), ["Export", "Export"])
        XCTAssertEqual(presentation.exportRows.map(\.status), ["Ready", "Disabled"])
        XCTAssertEqual(presentation.importRows.map(\.title), ["Vault", "Notion"])
        XCTAssertEqual(presentation.importRows.map(\.direction), ["Import", "Import"])
        XCTAssertEqual(presentation.importRows.map(\.status), ["Ready", "Disabled"])
        XCTAssertEqual(presentation.importRows.map(\.detail), ["/vault", "workspace@example.com"])
        XCTAssertEqual(presentation.syncMemoryStatusMessage, "Export ready")
        XCTAssertEqual(presentation.knowledgeImportStatusMessage, "Import ready")
    }
}
