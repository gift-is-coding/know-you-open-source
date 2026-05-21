import XCTest
@testable import KnowYou

final class KnowledgeImportModelTests: XCTestCase {
    func testConnectorIDSeparatesExportAndImportDirections() {
        XCTAssertEqual(KnowledgeConnectorID.obsidianImport.rawValue, "obsidian-import")
        XCTAssertEqual(KnowledgeConnectorID.obsidianExport.rawValue, "obsidian-export")
        XCTAssertNotEqual(KnowledgeConnectorID.obsidianImport, .obsidianExport)
    }

    func testConfigPersistenceKeepsImportSeparateFromSyncMemoryExport() {
        let suiteName = "KnowledgeImportModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var config = KnowledgeImportConfig.default
        config.isImportEnabled = true
        config.dailyImportHour = 7
        config.dailyImportMinute = 45
        config.connectorInstances = [
            KnowledgeConnectorInstanceConfig(
                id: "local-main",
                connectorID: .localFolderImport,
                displayName: "Docs",
                sourcePath: "/Users/test/Documents",
                isEnabled: true
            )
        ]
        config.save(to: defaults)

        let loaded = KnowledgeImportConfig.load(from: defaults)
        XCTAssertTrue(loaded.isImportEnabled)
        XCTAssertEqual(loaded.dailyImportHour, 7)
        XCTAssertEqual(loaded.dailyImportMinute, 45)
        XCTAssertEqual(loaded.connectorInstances.count, 1)

        let loadedInstance = loaded.connectorInstances.first
        XCTAssertEqual(loadedInstance?.id, "local-main")
        XCTAssertEqual(loadedInstance?.connectorID, .localFolderImport)
        XCTAssertEqual(loadedInstance?.displayName, "Docs")
        XCTAssertEqual(loadedInstance?.sourcePath, "/Users/test/Documents")
        XCTAssertTrue(loadedInstance?.isEnabled == true)
        XCTAssertNil(loadedInstance?.accountID)
        XCTAssertNil(loadedInstance?.workspaceID)
    }
}
