import XCTest
@testable import KnowYou

final class ConnectorsPanelTests: XCTestCase {
    func testAddSourceRootDoesNotExposeLegacyAPIFormMode() {
        let presentation = ConnectorsManagementPresentation(
            panelPresentation: ConnectorsPanelPresentation(
                syncMemoryConfig: .default,
                knowledgeImportConfig: .default,
                syncMemoryStatusMessage: nil,
                knowledgeImportStatusMessage: nil
            ),
            surface: .otherSourceRoot
        )

        XCTAssertFalse(presentation.showsAPIConnectorOption)
        XCTAssertEqual(presentation.panelPresentation.importRows, [])
    }

    func testAddSourceRootPresentationUsesApprovedCopyAndCards() {
        let externalRoot = URL(fileURLWithPath: "/Users/me/Library/Application Support/KnowYou/ExternalSources")
        let presentation = ConnectorsManagementPresentation(
            panelPresentation: ConnectorsPanelPresentation(
                syncMemoryConfig: .default,
                knowledgeImportConfig: .default,
                syncMemoryStatusMessage: nil,
                knowledgeImportStatusMessage: nil
            ),
            surface: .otherSourceRoot,
            externalSourcesRootURL: externalRoot
        )

        XCTAssertEqual(presentation.title, "Add Source")
        XCTAssertEqual(
            presentation.subtitle,
            "Manage all sources that feed your local Markdown library."
        )
        XCTAssertEqual(
            presentation.addSourceCards.map(\.title),
            ["My Diary", "Local Folder", "Obsidian Vault", "Feishu Docs", "Notion", "Google Drive"]
        )
        XCTAssertEqual(
            presentation.addSourceCards.map(\.status),
            ["Built-in", "Not connected", "Detected", "Not connected", "Not connected", "Not connected"]
        )
        XCTAssertEqual(
            presentation.addSourceCards.map(\.primaryActionTitle),
            ["Open", "Add Folder", "Use Vault", "Generate Prompt", "Generate Prompt", "Generate Prompt"]
        )
        XCTAssertFalse(presentation.showsAPIConnectorOption)
        XCTAssertFalse(presentation.showsDailyMemoryExport)
        XCTAssertFalse(presentation.showsHeaderAddConnector)
        XCTAssertFalse(presentation.showsConnectedSection)
        XCTAssertEqual(
            presentation.addSourceCards.first { $0.id == "feishu" }?.localDirectory,
            "/Users/me/Library/Application Support/KnowYou/ExternalSources/feishu"
        )
    }

    func testAddSourceRootFoldsConnectedSourcesIntoSingleSourceCardList() throws {
        let root = try makeTemporaryDirectory()
        let notionURL = root.appending(path: "notion", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: notionURL, withIntermediateDirectories: true)
        try "# Plan".write(
            to: notionURL.appending(path: "plan.md"),
            atomically: true,
            encoding: .utf8
        )
        let sourcePath = notionURL.path
        let presentation = ConnectorsManagementPresentation(
            panelPresentation: ConnectorsPanelPresentation(
                syncMemoryConfig: .default,
                knowledgeImportConfig: KnowledgeImportConfig(
                    connectorInstances: [
                        KnowledgeConnectorInstanceConfig(
                            id: "notion-main",
                            connectorID: .notionImport,
                            displayName: "Notion",
                            sourcePath: sourcePath,
                            isEnabled: true
                        )
                    ]
                ),
                syncMemoryStatusMessage: nil,
                knowledgeImportStatusMessage: "Imported 2 documents"
            ),
            surface: .otherSourceRoot,
            externalSourcesRootURL: root
        )

        XCTAssertFalse(presentation.showsConnectedSection)
        XCTAssertEqual(presentation.panelPresentation.importRows.map(\.title), ["Notion"])
        let notionCard = try XCTUnwrap(presentation.addSourceCards.first { $0.id == "notion" })
        XCTAssertEqual(notionCard.status, "Connected")
        XCTAssertEqual(notionCard.detail, sourcePath)
        XCTAssertEqual(notionCard.primaryActionTitle, "Sync Now")
    }

    func testPromptBackedSourceShowsNeedsFirstSyncWhenLocalDirectoryIsEmpty() throws {
        let root = try makeTemporaryDirectory()
        let feishuURL = root.appending(path: "feishu", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: feishuURL, withIntermediateDirectories: true)
        let presentation = ConnectorsManagementPresentation(
            panelPresentation: ConnectorsPanelPresentation(
                syncMemoryConfig: .default,
                knowledgeImportConfig: KnowledgeImportConfig(
                    connectorInstances: [
                        KnowledgeConnectorInstanceConfig(
                            id: "feishu-main",
                            connectorID: .feishuImport,
                            displayName: "Feishu Docs",
                            sourcePath: feishuURL.path,
                            isEnabled: true
                        )
                    ]
                ),
                syncMemoryStatusMessage: nil,
                knowledgeImportStatusMessage: nil
            ),
            surface: .otherSourceRoot,
            externalSourcesRootURL: root
        )

        let feishuCard = try XCTUnwrap(presentation.addSourceCards.first { $0.id == "feishu" })
        XCTAssertEqual(feishuCard.status, "Needs first sync")
        XCTAssertEqual(feishuCard.primaryActionTitle, "Generate Prompt")
    }

    func testExternalSourcePromptPresentationContainsScheduleOutputDirectoryAndNoTokenRequest() {
        let root = URL(fileURLWithPath: "/Users/me/Library/Application Support/KnowYou/ExternalSources")
        let prompt = ExternalSourcePromptPresentation(
            connectorID: .feishuImport,
            frequency: .daily,
            importTime: makeTime(hour: 9, minute: 15),
            scopeDescription: "Marketing docs",
            externalSourcesRootURL: root
        )

        XCTAssertEqual(prompt.platformName, "Feishu Docs")
        XCTAssertEqual(prompt.outputDirectory, root.appending(path: "feishu", directoryHint: .isDirectory).path)
        XCTAssertTrue(prompt.prompt.contains("daily"))
        XCTAssertTrue(prompt.prompt.contains("09:15"))
        XCTAssertTrue(prompt.prompt.contains("Marketing docs"))
        XCTAssertTrue(prompt.prompt.contains(prompt.outputDirectory))
        XCTAssertFalse(prompt.prompt.localizedCaseInsensitiveContains("paste token back to KnowYou"))
        XCTAssertFalse(prompt.prompt.localizedCaseInsensitiveContains("bearer token"))
    }

    func testLegacyConnectorsSheetPresentationOnlyKeepsDailyExportCopy() {
        let presentation = ConnectorsManagementPresentation(
            panelPresentation: ConnectorsPanelPresentation(
                syncMemoryConfig: .default,
                knowledgeImportConfig: .default,
                syncMemoryStatusMessage: nil,
                knowledgeImportStatusMessage: nil
            ),
            surface: .connectorsSheet
        )

        XCTAssertEqual(presentation.title, "Connectors")
        XCTAssertEqual(
            presentation.subtitle,
            "Manage daily memory exports."
        )
        XCTAssertEqual(presentation.emptyImportMessage, "No connectors configured")
        XCTAssertTrue(presentation.showsDailyMemoryExport)
        XCTAssertFalse(presentation.showsAPIConnectorOption)
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

    private func makeTime(hour: Int, minute: Int) -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.hour = hour
        components.minute = minute
        return components.date ?? Date(timeIntervalSince1970: 0)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "KnowYouConnectorsPanelTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
