import XCTest
@testable import KnowYou

final class SyncMemoryConfigTests: XCTestCase {
    func testSaveAndLoadPersistsEnabledChannelsAndDailyTime() {
        let suiteName = "SyncMemoryConfigTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var config = SyncMemoryConfig.default
        config.obsidian.isEnabled = true
        config.obsidian.bookmarkData = Data([0x01, 0x02])
        config.openClaw.isEnabled = true
        config.openClaw.resolvedPath = "/Users/test/.openclaw/workspace/know-you-memory"
        config.autoSyncEnabled = true
        config.dailySyncHour = 21
        config.dailySyncMinute = 30

        config.save(to: defaults)
        let loaded = SyncMemoryConfig.load(from: defaults)

        XCTAssertTrue(loaded.obsidian.isEnabled)
        XCTAssertEqual(loaded.obsidian.bookmarkData, Data([0x01, 0x02]))
        XCTAssertTrue(loaded.openClaw.isEnabled)
        XCTAssertEqual(loaded.openClaw.resolvedPath, "/Users/test/.openclaw/workspace/know-you-memory")
        XCTAssertTrue(loaded.autoSyncEnabled)
        XCTAssertEqual(loaded.dailySyncHour, 21)
        XCTAssertEqual(loaded.dailySyncMinute, 30)
    }

    func testLoadFallsBackToDefaultWhenStoreIsEmpty() {
        let suiteName = "SyncMemoryConfigTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let loaded = SyncMemoryConfig.load(from: defaults)

        XCTAssertFalse(loaded.obsidian.isEnabled)
        XCTAssertFalse(loaded.openClaw.isEnabled)
        XCTAssertFalse(loaded.autoSyncEnabled)
        XCTAssertEqual(loaded.dailySyncHour, 21)
        XCTAssertEqual(loaded.dailySyncMinute, 0)
    }
}
