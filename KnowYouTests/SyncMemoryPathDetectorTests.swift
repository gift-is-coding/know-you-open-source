import XCTest
@testable import KnowYou

final class SyncMemoryPathDetectorTests: XCTestCase {
    func testDetectConfiguredObsidianVaultsReadsVaultsFromObsidianJSON() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let configDirectory = root.appendingPathComponent("obsidian", isDirectory: true)
        let olderVault = root.appendingPathComponent("OlderVault", isDirectory: true)
        let newerVault = root.appendingPathComponent("NewerVault", isDirectory: true)
        try FileManager.default.createDirectory(
            at: olderVault.appendingPathComponent(".obsidian", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: newerVault.appendingPathComponent(".obsidian", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(at: configDirectory, withIntermediateDirectories: true)
        try """
        {
          "vaults": {
            "old": { "path": "\(olderVault.path)", "ts": 1 },
            "new": { "path": "\(newerVault.path)", "ts": 2 }
          }
        }
        """.write(
            to: configDirectory.appendingPathComponent("obsidian.json"),
            atomically: true,
            encoding: .utf8
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let detector = SyncMemoryPathDetector(fileManager: .default)

        let result = detector.detectConfiguredObsidianVaults(configDirectory: configDirectory)

        XCTAssertEqual(result.map(\.lastPathComponent), ["NewerVault", "OlderVault"])
    }

    func testDetectObsidianVaultsReturnsFoldersContainingDotObsidian() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let matchingVault = root.appendingPathComponent("WorkVault", isDirectory: true)
        let ignoredVault = root.appendingPathComponent("OtherVault", isDirectory: true)

        try FileManager.default.createDirectory(
            at: matchingVault.appendingPathComponent(".obsidian", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(at: ignoredVault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let detector = SyncMemoryPathDetector(fileManager: .default)

        let result = detector.detectObsidianVaults(searchRoots: [root])

        XCTAssertEqual(result.map(\.lastPathComponent), ["WorkVault"])
    }

    func testDefaultObsidianConfigDirectoryUsesApplicationSupportObsidian() {
        let detector = SyncMemoryPathDetector(fileManager: .default)

        let configDirectory = detector.defaultObsidianConfigDirectory(homePath: "/Users/test")

        XCTAssertEqual(configDirectory.path, "/Users/test/Library/Application Support/obsidian")
    }

    func testDefaultOpenClawWorkspaceAppendsWorkspacePathUnderHome() {
        let detector = SyncMemoryPathDetector(fileManager: .default)

        let workspace = detector.defaultOpenClawWorkspace(homePath: "/Users/test")

        XCTAssertEqual(workspace.path, "/Users/test/.openclaw/workspace")
    }

    func testOpenClawMemoryDirectoryAppendsKnowYouMemoryFolder() {
        let detector = SyncMemoryPathDetector(fileManager: .default)
        let workspace = URL(fileURLWithPath: "/Users/test/.openclaw/workspace", isDirectory: true)

        XCTAssertEqual(
            detector.openClawMemoryDirectory(for: workspace).path,
            "/Users/test/.openclaw/workspace/know-you-memory"
        )
    }
}
