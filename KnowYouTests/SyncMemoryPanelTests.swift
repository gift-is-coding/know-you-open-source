import XCTest
@testable import KnowYou

final class SyncMemoryPanelTests: XCTestCase {
    func testPresentationUsesFallbackCopyForUnconfiguredChannels() {
        let presentation = SyncMemoryPanelPresentation(
            obsidianPath: nil,
            openClawPath: nil,
            isAutoSyncDailyEnabled: false
        )

        XCTAssertEqual(presentation.channelRows.map(\.title), ["Obsidian", "OpenClaw"])
        XCTAssertEqual(presentation.channelRows.map(\.status), ["Missing", "Missing"])
        XCTAssertEqual(presentation.channelRows.map(\.detail), ["Not connected", "Not connected"])
        XCTAssertEqual(
            presentation.autoSyncDescription,
            "When enabled, Know You syncs all daily notes to connected memory targets."
        )
    }

    func testPresentationPreservesConfiguredPathsAndToggleState() {
        let presentation = SyncMemoryPanelPresentation(
            obsidianPath: "/Users/test/Vault/KnowYou",
            openClawPath: "/Users/test/.openclaw/workspace/know-you-memory",
            isAutoSyncDailyEnabled: true,
            statusMessage: "Synced 12 notes to 2 destinations"
        )

        XCTAssertEqual(presentation.channelRows.map(\.status), ["Ready", "Ready"])
        XCTAssertEqual(
            presentation.channelRows.map(\.detail),
            [
                "/Users/test/Vault/KnowYou",
                "/Users/test/.openclaw/workspace/know-you-memory",
            ]
        )
        XCTAssertTrue(presentation.isAutoSyncDailyEnabled)
        XCTAssertEqual(presentation.statusMessage, "Synced 12 notes to 2 destinations")
    }
}
