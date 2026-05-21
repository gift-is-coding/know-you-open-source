import XCTest
@testable import KnowYou

final class KnowledgeImportModelTests: XCTestCase {
    private final class InMemoryKeychainStore: KeychainStoring, @unchecked Sendable {
        private var values: [String: String] = [:]

        func save(_ value: String, forKey key: String, service: String) {
            values["\(service).\(key)"] = value
        }

        func load(forKey key: String, service: String) -> String? {
            values["\(service).\(key)"]
        }

        func delete(forKey key: String, service: String) {
            values["\(service).\(key)"] = nil
        }
    }

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

    func testConfigPersistenceFiltersExportOnlyConnectorInstances() {
        let suiteName = "KnowledgeImportModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var config = KnowledgeImportConfig.default
        config.connectorInstances = [
            KnowledgeConnectorInstanceConfig(
                id: "obsidian-import",
                connectorID: .obsidianImport,
                displayName: "Obsidian Import",
                isEnabled: true
            ),
            KnowledgeConnectorInstanceConfig(
                id: "obsidian-export",
                connectorID: .obsidianExport,
                displayName: "Obsidian Export",
                isEnabled: true
            ),
            KnowledgeConnectorInstanceConfig(
                id: "openclaw-export",
                connectorID: .openClawExport,
                displayName: "OpenClaw Export",
                isEnabled: true
            ),
        ]

        config.save(to: defaults)
        let loaded = KnowledgeImportConfig.load(from: defaults)

        XCTAssertEqual(loaded.connectorInstances.map(\.id), ["obsidian-import"])
        XCTAssertTrue(loaded.connectorInstances.allSatisfy { $0.connectorID.isImport })
    }

    func testConfigLoadFiltersLegacyExportOnlyConnectorInstances() throws {
        let suiteName = "KnowledgeImportModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var config = KnowledgeImportConfig.default
        config.connectorInstances = [
            KnowledgeConnectorInstanceConfig(
                id: "local-main",
                connectorID: .localFolderImport,
                displayName: "Docs",
                isEnabled: true
            ),
            KnowledgeConnectorInstanceConfig(
                id: "obsidian-export",
                connectorID: .obsidianExport,
                displayName: "Obsidian Export",
                isEnabled: true
            ),
        ]
        let data = try JSONEncoder().encode(config)
        defaults.set(data, forKey: "knowledgeImportConfig")

        let loaded = KnowledgeImportConfig.load(from: defaults)

        XCTAssertEqual(loaded.connectorInstances.map(\.id), ["local-main"])
        XCTAssertTrue(loaded.connectorInstances.allSatisfy { $0.connectorID.isImport })
    }

    func testCredentialStoreSavesLoadsAndDeletesBearerToken() {
        let keychain = InMemoryKeychainStore()
        let store = KnowledgeImportCredentialStore(keychain: keychain, service: "test-service")

        store.saveBearerToken("token-123", connectorInstanceID: "local-main")

        XCTAssertEqual(store.bearerToken(connectorInstanceID: "local-main"), "token-123")

        store.deleteBearerToken(connectorInstanceID: "local-main")

        XCTAssertNil(store.bearerToken(connectorInstanceID: "local-main"))
    }

    func testCredentialStoreClearsEmptyBearerToken() {
        let keychain = InMemoryKeychainStore()
        let store = KnowledgeImportCredentialStore(keychain: keychain, service: "test-service")

        store.saveBearerToken("token-123", connectorInstanceID: "local-main")
        store.saveBearerToken(" \n\t ", connectorInstanceID: "local-main")

        XCTAssertNil(store.bearerToken(connectorInstanceID: "local-main"))

        store.saveBearerToken("token-456", connectorInstanceID: "local-main")
        store.saveBearerToken("", connectorInstanceID: "local-main")

        XCTAssertNil(store.bearerToken(connectorInstanceID: "local-main"))
    }

    func testCredentialStoreClearsLegacyWhitespaceBearerTokenOnRead() {
        let keychain = InMemoryKeychainStore()
        let store = KnowledgeImportCredentialStore(keychain: keychain, service: "test-service")
        let key = "knowledge-import.local-main.bearer-token"
        keychain.save(" \n\t ", forKey: key, service: "test-service")

        XCTAssertNil(store.bearerToken(connectorInstanceID: "local-main"))
        XCTAssertNil(keychain.load(forKey: key, service: "test-service"))
    }
}
