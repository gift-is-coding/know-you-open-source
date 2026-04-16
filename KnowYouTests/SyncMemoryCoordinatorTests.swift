import XCTest
@testable import KnowYou

final class SyncMemoryCoordinatorTests: XCTestCase {
    func testSyncDiariesCopiesAllMarkdownIntoObsidianAndOpenClawTargets() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sourceVault = root.appendingPathComponent("source", isDirectory: true)
        let obsidianTarget = root.appendingPathComponent("obsidian/Know You/Daily Memories", isDirectory: true)
        let openClawTarget = root.appendingPathComponent("openclaw/know-you-memory", isDirectory: true)

        try FileManager.default.createDirectory(at: sourceVault, withIntermediateDirectories: true)
        try "# Older".write(
            to: sourceVault.appendingPathComponent("2026-04-13.md"),
            atomically: true,
            encoding: .utf8
        )
        try "# Newer".write(
            to: sourceVault.appendingPathComponent("2026-04-14.md"),
            atomically: true,
            encoding: .utf8
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let coordinator = SyncMemoryCoordinator(fileManager: .default)
        let result = try coordinator.syncDiaries(
            sourceVault: sourceVault,
            destinations: [
                .obsidian: obsidianTarget,
                .openClaw: openClawTarget,
            ]
        )

        XCTAssertEqual(result[.obsidian]?.copiedFileNames, ["2026-04-14.md", "2026-04-13.md"])
        XCTAssertEqual(result[.openClaw]?.copiedFileNames, ["2026-04-14.md", "2026-04-13.md"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: obsidianTarget.appendingPathComponent("2026-04-13.md").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: obsidianTarget.appendingPathComponent("2026-04-14.md").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: openClawTarget.appendingPathComponent("2026-04-13.md").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: openClawTarget.appendingPathComponent("2026-04-14.md").path))
    }

    func testSyncDiariesOverwritesPreviouslySyncedFileWithSameName() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sourceVault = root.appendingPathComponent("source", isDirectory: true)
        let obsidianTarget = root.appendingPathComponent("obsidian/Know You/Daily Memories", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceVault, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: obsidianTarget, withIntermediateDirectories: true)
        try "# Fresh".write(
            to: sourceVault.appendingPathComponent("2026-04-14.md"),
            atomically: true,
            encoding: .utf8
        )
        try "# Stale".write(
            to: obsidianTarget.appendingPathComponent("2026-04-14.md"),
            atomically: true,
            encoding: .utf8
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let coordinator = SyncMemoryCoordinator(fileManager: .default)
        _ = try coordinator.syncDiaries(
            sourceVault: sourceVault,
            destinations: [.obsidian: obsidianTarget]
        )

        XCTAssertEqual(
            try String(contentsOf: obsidianTarget.appendingPathComponent("2026-04-14.md"), encoding: .utf8),
            "# Fresh"
        )
    }

    func testSyncDiariesThrowsWhenNoMarkdownExists() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let coordinator = SyncMemoryCoordinator(fileManager: .default)

        XCTAssertThrowsError(try coordinator.syncDiaries(sourceVault: root, destinations: [:]))
    }
}
