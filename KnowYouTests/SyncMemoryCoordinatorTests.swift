import XCTest
@testable import KnowYou

final class SyncMemoryCoordinatorTests: XCTestCase {
    func testSyncDiariesCopiesAllMarkdownIntoObsidianAndOpenClawTargets() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sourceVault = root.appendingPathComponent("source", isDirectory: true)
        let obsidianTarget = root.appendingPathComponent("obsidian/KnowYou/Daily Memories", isDirectory: true)
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
        XCTAssertEqual(
            try String(contentsOf: obsidianTarget.appendingPathComponent("2026-04-14.md"), encoding: .utf8),
            """
            ---
            knowyou_export: daily_memory
            ---
            # Newer
            """
        )
        XCTAssertEqual(
            try String(contentsOf: openClawTarget.appendingPathComponent("2026-04-14.md"), encoding: .utf8),
            """
            ---
            knowyou_export: daily_memory
            ---
            # Newer
            """
        )
    }

    func testSyncDiariesOverwritesPreviouslySyncedFileWithSameName() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sourceVault = root.appendingPathComponent("source", isDirectory: true)
        let obsidianTarget = root.appendingPathComponent("obsidian/KnowYou/Daily Memories", isDirectory: true)
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
            """
            ---
            knowyou_export: daily_memory
            ---
            # Fresh
            """
        )
    }

    func testSyncDiariesDoesNotDuplicateExistingDailyMemoryExportMarkerInFrontmatter() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sourceVault = root.appendingPathComponent("source", isDirectory: true)
        let obsidianTarget = root.appendingPathComponent("obsidian/KnowYou/Daily Memories", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceVault, withIntermediateDirectories: true)
        try """
        ---
        knowyou_export: daily_memory
        ---
        # Already Exported
        """.write(
            to: sourceVault.appendingPathComponent("2026-04-14.md"),
            atomically: true,
            encoding: .utf8
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let coordinator = SyncMemoryCoordinator(fileManager: .default)
        _ = try coordinator.syncDiaries(
            sourceVault: sourceVault,
            destinations: [.obsidian: obsidianTarget]
        )

        let exportedMarkdown = try String(
            contentsOf: obsidianTarget.appendingPathComponent("2026-04-14.md"),
            encoding: .utf8
        )
        XCTAssertEqual(
            exportedMarkdown,
            """
            ---
            knowyou_export: daily_memory
            ---
            # Already Exported
            """
        )
        XCTAssertEqual(
            exportedMarkdown.components(separatedBy: "knowyou_export: daily_memory").count - 1,
            1
        )
    }

    func testSyncDiariesDoesNotDuplicateSpacingAndCaseVariantExportMarkerInFrontmatter() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sourceVault = root.appendingPathComponent("source", isDirectory: true)
        let obsidianTarget = root.appendingPathComponent("obsidian/KnowYou/Daily Memories", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceVault, withIntermediateDirectories: true)
        try """
        ---
        KnowYou_Export : Daily_Memory
        title: Already Exported
        ---
        # Already Exported
        """.write(
            to: sourceVault.appendingPathComponent("2026-04-14.md"),
            atomically: true,
            encoding: .utf8
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let coordinator = SyncMemoryCoordinator(fileManager: .default)
        _ = try coordinator.syncDiaries(
            sourceVault: sourceVault,
            destinations: [.obsidian: obsidianTarget]
        )

        let exportedMarkdown = try String(
            contentsOf: obsidianTarget.appendingPathComponent("2026-04-14.md"),
            encoding: .utf8
        )
        XCTAssertEqual(
            exportedMarkdown,
            """
            ---
            KnowYou_Export : Daily_Memory
            title: Already Exported
            ---
            # Already Exported
            """
        )
        XCTAssertEqual(
            exportedMarkdown.localizedCaseInsensitiveContains("knowyou_export: daily_memory"),
            false
        )
    }

    func testSyncDiariesPrependsExportMarkerWhenMarkerAppearsOnlyInBody() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sourceVault = root.appendingPathComponent("source", isDirectory: true)
        let obsidianTarget = root.appendingPathComponent("obsidian/KnowYou/Daily Memories", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceVault, withIntermediateDirectories: true)
        try """
        # Body Marker
        knowyou_export: daily_memory

        Original body.
        """.write(
            to: sourceVault.appendingPathComponent("2026-04-14.md"),
            atomically: true,
            encoding: .utf8
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let coordinator = SyncMemoryCoordinator(fileManager: .default)
        _ = try coordinator.syncDiaries(
            sourceVault: sourceVault,
            destinations: [.obsidian: obsidianTarget]
        )

        let exportedMarkdownWithContentMarker = try String(
            contentsOf: obsidianTarget.appendingPathComponent("2026-04-14.md"),
            encoding: .utf8
        )
        XCTAssertEqual(
            exportedMarkdownWithContentMarker,
            """
            ---
            knowyou_export: daily_memory
            ---
            # Body Marker
            knowyou_export: daily_memory

            Original body.
            """
        )
        XCTAssertEqual(
            exportedMarkdownWithContentMarker.components(separatedBy: "knowyou_export: daily_memory").count - 1,
            2
        )
    }

    func testSyncDiariesMergesExportMarkerIntoExistingFrontmatter() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sourceVault = root.appendingPathComponent("source", isDirectory: true)
        let obsidianTarget = root.appendingPathComponent("obsidian/KnowYou/Daily Memories", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceVault, withIntermediateDirectories: true)
        try """
        ---
        title: Existing Metadata
        tags:
          - daily
        ---
        # With Metadata
        """.write(
            to: sourceVault.appendingPathComponent("2026-04-14.md"),
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
            """
            ---
            knowyou_export: daily_memory
            title: Existing Metadata
            tags:
              - daily
            ---
            # With Metadata
            """
        )
    }

    func testSyncDiariesMergesExportMarkerWhenBodyAlsoContainsMarkerText() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sourceVault = root.appendingPathComponent("source", isDirectory: true)
        let obsidianTarget = root.appendingPathComponent("obsidian/KnowYou/Daily Memories", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceVault, withIntermediateDirectories: true)
        try """
        ---
        title: Existing Metadata
        ---
        # Body Marker
        knowyou_export: daily_memory
        """.write(
            to: sourceVault.appendingPathComponent("2026-04-14.md"),
            atomically: true,
            encoding: .utf8
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let coordinator = SyncMemoryCoordinator(fileManager: .default)
        _ = try coordinator.syncDiaries(
            sourceVault: sourceVault,
            destinations: [.obsidian: obsidianTarget]
        )

        let exportedMarkdown = try String(
            contentsOf: obsidianTarget.appendingPathComponent("2026-04-14.md"),
            encoding: .utf8
        )
        XCTAssertEqual(
            exportedMarkdown,
            """
            ---
            knowyou_export: daily_memory
            title: Existing Metadata
            ---
            # Body Marker
            knowyou_export: daily_memory
            """
        )
        XCTAssertEqual(exportedMarkdown.components(separatedBy: "knowyou_export: daily_memory").count - 1, 2)
    }

    func testSyncDiariesMergesExportMarkerIntoCustomKeyFrontmatter() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sourceVault = root.appendingPathComponent("source", isDirectory: true)
        let obsidianTarget = root.appendingPathComponent("obsidian/KnowYou/Daily Memories", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceVault, withIntermediateDirectories: true)
        try """
        ---
        summary: Existing Metadata
        ---
        # With Custom Metadata
        """.write(
            to: sourceVault.appendingPathComponent("2026-04-14.md"),
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
            """
            ---
            knowyou_export: daily_memory
            summary: Existing Metadata
            ---
            # With Custom Metadata
            """
        )
    }

    func testSyncDiariesMergesExportMarkerIntoCommonExternalFrontmatterKeys() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sourceVault = root.appendingPathComponent("source", isDirectory: true)
        let obsidianTarget = root.appendingPathComponent("obsidian/KnowYou/Daily Memories", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceVault, withIntermediateDirectories: true)
        try """
        ---
        layout: post
        cssclass: daily
        ---
        # With External Metadata
        """.write(
            to: sourceVault.appendingPathComponent("2026-04-14.md"),
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
            """
            ---
            knowyou_export: daily_memory
            layout: post
            cssclass: daily
            ---
            # With External Metadata
            """
        )
    }

    func testSyncDiariesMergesExportMarkerIntoFrontmatterWithPunctuationInScalar() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sourceVault = root.appendingPathComponent("source", isDirectory: true)
        let obsidianTarget = root.appendingPathComponent("obsidian/KnowYou/Daily Memories", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceVault, withIntermediateDirectories: true)
        try """
        ---
        title: Hello, world
        ---
        # Body
        """.write(
            to: sourceVault.appendingPathComponent("2026-04-14.md"),
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
            """
            ---
            knowyou_export: daily_memory
            title: Hello, world
            ---
            # Body
            """
        )
    }

    func testSyncDiariesDoesNotTreatThematicBreakBlockAsFrontmatter() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sourceVault = root.appendingPathComponent("source", isDirectory: true)
        let obsidianTarget = root.appendingPathComponent("obsidian/KnowYou/Daily Memories", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceVault, withIntermediateDirectories: true)
        try """
        ---
        Intro paragraph without YAML.
        ---
        # Body
        """.write(
            to: sourceVault.appendingPathComponent("2026-04-14.md"),
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
            """
            ---
            knowyou_export: daily_memory
            ---
            ---
            Intro paragraph without YAML.
            ---
            # Body
            """
        )
    }

    func testSyncDiariesDoesNotTreatThematicBreakBlockWithColonProseAsFrontmatter() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sourceVault = root.appendingPathComponent("source", isDirectory: true)
        let obsidianTarget = root.appendingPathComponent("obsidian/KnowYou/Daily Memories", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceVault, withIntermediateDirectories: true)
        try """
        ---
        Note: plain text, not YAML frontmatter
        ---
        # Body
        """.write(
            to: sourceVault.appendingPathComponent("2026-04-14.md"),
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
            """
            ---
            knowyou_export: daily_memory
            ---
            ---
            Note: plain text, not YAML frontmatter
            ---
            # Body
            """
        )
    }

    func testSyncDiariesDoesNotTreatLowercaseColonProseAsFrontmatter() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sourceVault = root.appendingPathComponent("source", isDirectory: true)
        let obsidianTarget = root.appendingPathComponent("obsidian/KnowYou/Daily Memories", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceVault, withIntermediateDirectories: true)
        try """
        ---
        note: plain text, not metadata
        ---
        # Body
        """.write(
            to: sourceVault.appendingPathComponent("2026-04-14.md"),
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
            """
            ---
            knowyou_export: daily_memory
            ---
            ---
            note: plain text, not metadata
            ---
            # Body
            """
        )
    }

    func testSyncDiariesMergesExportMarkerIntoFrontmatterWithBlockScalar() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sourceVault = root.appendingPathComponent("source", isDirectory: true)
        let obsidianTarget = root.appendingPathComponent("obsidian/KnowYou/Daily Memories", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceVault, withIntermediateDirectories: true)
        try """
        ---
        summary: |
          First line
          Second line
        ---
        # Body
        """.write(
            to: sourceVault.appendingPathComponent("2026-04-14.md"),
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
            """
            ---
            knowyou_export: daily_memory
            summary: |
              First line
              Second line
            ---
            # Body
            """
        )
    }

    func testSyncDiariesAddsTopLevelMarkerWhenBlockScalarMentionsMarker() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sourceVault = root.appendingPathComponent("source", isDirectory: true)
        let obsidianTarget = root.appendingPathComponent("obsidian/KnowYou/Daily Memories", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceVault, withIntermediateDirectories: true)
        try """
        ---
        summary: |
          Example export marker:
          knowyou_export: daily_memory
        ---
        # Body
        """.write(
            to: sourceVault.appendingPathComponent("2026-04-14.md"),
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
            """
            ---
            knowyou_export: daily_memory
            summary: |
              Example export marker:
              knowyou_export: daily_memory
            ---
            # Body
            """
        )
    }

    func testSyncDiariesMergesExportMarkerIntoFrontmatterWithUppercaseAndCamelCaseKeys() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sourceVault = root.appendingPathComponent("source", isDirectory: true)
        let obsidianTarget = root.appendingPathComponent("obsidian/KnowYou/Daily Memories", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceVault, withIntermediateDirectories: true)
        try """
        ---
        Title: Existing Metadata
        createdAt: 2026-04-14
        ---
        # Body
        """.write(
            to: sourceVault.appendingPathComponent("2026-04-14.md"),
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
            """
            ---
            knowyou_export: daily_memory
            Title: Existing Metadata
            createdAt: 2026-04-14
            ---
            # Body
            """
        )
    }

    func testSyncDiariesThrowsWhenNoMarkdownExists() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let coordinator = SyncMemoryCoordinator(fileManager: .default)

        XCTAssertThrowsError(try coordinator.syncDiaries(sourceVault: root, destinations: [:])) { error in
            XCTAssertEqual(error as? SyncMemoryCoordinatorError, .noDiaryMarkdownFound)
        }
    }
}
