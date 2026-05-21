import XCTest
@testable import KnowYou

final class ObsidianKnowledgeConnectorTests: XCTestCase {
    func testFetchSnapshotsSkipsKnowYouDailyMemoryExportDirectoryAndHiddenVaultMetadata() async throws {
        let vault = try makeObsidianTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: vault) }
        _ = try writeObsidianFile("# Daily mirror", at: "KnowYou/Daily Memories/2026-05-21.md", in: vault)
        _ = try writeObsidianFile("# Nested mirror", at: "KnowYou/Daily Memories/archive/2026-05-20.md", in: vault)
        _ = try writeObsidianFile("{}", at: ".obsidian/app.json", in: vault)
        _ = try writeObsidianFile("# Outside KnowYou export", at: "KnowYou/Project.md", in: vault)
        _ = try writeObsidianFile("# Legit note", at: "Inbox/Note.md", in: vault)

        let connector = ObsidianKnowledgeConnector(
            connectorInstanceID: "obsidian-main",
            vaultURL: vault
        )

        let snapshots = try await connector.fetchSnapshots()

        XCTAssertEqual(snapshots.map(\.remoteID), ["Inbox/Note.md", "KnowYou/Project.md"])
        XCTAssertTrue(snapshots.allSatisfy { $0.connectorInstanceID == "obsidian-main" })
        XCTAssertTrue(snapshots.allSatisfy { $0.connectorID == .obsidianImport })
        XCTAssertTrue(snapshots.allSatisfy { $0.originKind == "obsidian-vault" })

        let note = try XCTUnwrap(snapshots.first { $0.remoteID == "Inbox/Note.md" })
        XCTAssertEqual(note.title, "Note")
        XCTAssertEqual(note.mimeType, "text/markdown")
        XCTAssertEqual(note.contentMarkdown, "# Legit note")
        XCTAssertEqual(note.sourcePath, vault.appending(path: "Inbox/Note.md").path)
    }

    func testFetchSnapshotsSkipsKnowYouExportFrontmatterButKeepsLegitimateNotesOutsideExportDirectory() async throws {
        let vault = try makeObsidianTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: vault) }
        _ = try writeObsidianFile(
            """
            ---
            knowyou_export: daily_memory
            ---
            # Exported daily memory
            """,
            at: "Archive/FrontmatterExport.md",
            in: vault
        )
        _ = try writeObsidianFile(
            #"{"originKind":"daily_memory_export"}"#,
            at: "Archive/SidecarCompact.md",
            in: vault
        )
        _ = try writeObsidianFile(
            #"{"originKind": "daily_memory_export"}"#,
            at: "Archive/SidecarSpaced.md",
            in: vault
        )
        _ = try writeObsidianFile(
            "# Legitimate note\nThis is not a KnowYou export.",
            at: "Archive/Legitimate.md",
            in: vault
        )

        let connector = ObsidianKnowledgeConnector(
            connectorInstanceID: "obsidian-main",
            vaultURL: vault
        )

        let snapshots = try await connector.fetchSnapshots()

        XCTAssertEqual(
            snapshots.map(\.remoteID),
            ["Archive/Legitimate.md", "Archive/SidecarCompact.md", "Archive/SidecarSpaced.md"]
        )
        let legitimate = try XCTUnwrap(snapshots.first { $0.remoteID == "Archive/Legitimate.md" })
        XCTAssertEqual(legitimate.connectorID, .obsidianImport)
        XCTAssertEqual(legitimate.originKind, "obsidian-vault")
        XCTAssertEqual(legitimate.contentMarkdown, "# Legitimate note\nThis is not a KnowYou export.")
    }

    func testFetchSnapshotsSkipsKnowYouDailyMemoryExportDirectoryCaseInsensitively() async throws {
        let vault = try makeObsidianTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: vault) }
        _ = try writeObsidianFile("# Mixed case mirror", at: "knOwYoU/dAiLy MeMoRiEs/2026-05-22.md", in: vault)
        _ = try writeObsidianFile("# Legit note", at: "Notes/Legit.md", in: vault)

        let connector = ObsidianKnowledgeConnector(
            connectorInstanceID: "obsidian-main",
            vaultURL: vault
        )

        let snapshots = try await connector.fetchSnapshots()

        XCTAssertEqual(snapshots.map(\.remoteID), ["Notes/Legit.md"])
    }

    func testFetchSnapshotsSkipsKnowYouDailyMemoryExportDirectoryFromSymlinkedVaultRoot() async throws {
        let container = try makeObsidianTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: container) }
        let vault = container.appending(path: "ActualVault", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        let symlinkVault = container.appending(path: "LinkedVault", directoryHint: .isDirectory)
        try FileManager.default.createSymbolicLink(at: symlinkVault, withDestinationURL: vault)
        _ = try writeObsidianFile("# Mirror", at: "KnowYou/Daily Memories/2026-05-22.md", in: vault)
        _ = try writeObsidianFile("# Legit note", at: "Notes/Legit.md", in: vault)

        let connector = ObsidianKnowledgeConnector(
            connectorInstanceID: "obsidian-main",
            vaultURL: symlinkVault
        )

        let snapshots = try await connector.fetchSnapshots()

        XCTAssertEqual(snapshots.map(\.remoteID), ["Notes/Legit.md"])
    }

    func testFetchSnapshotsSkipsKnowYouExportMarkersCaseInsensitively() async throws {
        let vault = try makeObsidianTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: vault) }
        _ = try writeObsidianFile(
            """
            ---
            KnowYou_Export: Daily_Memory
            ---
            # Exported daily memory
            """,
            at: "Archive/MixedFrontmatter.md",
            in: vault
        )
        _ = try writeObsidianFile(
            #"{"ORIGINKIND":"daily_memory_export"}"#,
            at: "Archive/UppercaseJSONKey.md",
            in: vault
        )
        _ = try writeObsidianFile(
            #"{"originKind": "DAILY_MEMORY_EXPORT"}"#,
            at: "Archive/UppercaseJSONValue.md",
            in: vault
        )
        _ = try writeObsidianFile(
            "# Legitimate note",
            at: "Archive/Legitimate.md",
            in: vault
        )

        let connector = ObsidianKnowledgeConnector(
            connectorInstanceID: "obsidian-main",
            vaultURL: vault
        )

        let snapshots = try await connector.fetchSnapshots()

        XCTAssertEqual(
            snapshots.map(\.remoteID),
            ["Archive/Legitimate.md", "Archive/UppercaseJSONKey.md", "Archive/UppercaseJSONValue.md"]
        )
    }

    func testFetchSnapshotsKeepsLegitimateNoteWithBodyOnlyExportMarkerText() async throws {
        let vault = try makeObsidianTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: vault) }
        _ = try writeObsidianFile(
            """
            # Debugging note

            The exported files contain this line:
            knowyou_export: daily_memory
            """,
            at: "Archive/BodyMarkerReference.md",
            in: vault
        )
        _ = try writeObsidianFile(
            """
            ---
            knowyou_export: daily_memory
            ---
            # Exported daily memory
            """,
            at: "Archive/FrontmatterExport.md",
            in: vault
        )

        let connector = ObsidianKnowledgeConnector(
            connectorInstanceID: "obsidian-main",
            vaultURL: vault
        )

        let snapshots = try await connector.fetchSnapshots()

        XCTAssertEqual(snapshots.map(\.remoteID), ["Archive/BodyMarkerReference.md"])
    }

    func testFetchSnapshotsKeepsLegitimateNoteWithThematicBreakBodyExportMarkerText() async throws {
        let vault = try makeObsidianTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: vault) }
        _ = try writeObsidianFile(
            """
            ---
            This note is documenting the export marker:
            knowyou_export: daily_memory
            ---
            # Body
            """,
            at: "Archive/ThematicBodyMarkerReference.md",
            in: vault
        )

        let connector = ObsidianKnowledgeConnector(
            connectorInstanceID: "obsidian-main",
            vaultURL: vault
        )

        let snapshots = try await connector.fetchSnapshots()

        XCTAssertEqual(snapshots.map(\.remoteID), ["Archive/ThematicBodyMarkerReference.md"])
    }

    func testFetchSnapshotsKeepsLegitimateNoteWithNestedFrontmatterMarkerReference() async throws {
        let vault = try makeObsidianTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: vault) }
        _ = try writeObsidianFile(
            """
            ---
            summary: |
              Example export marker:
              knowyou_export: daily_memory
            ---
            # Legit note
            """,
            at: "Archive/NestedMarkerReference.md",
            in: vault
        )

        let connector = ObsidianKnowledgeConnector(
            connectorInstanceID: "obsidian-main",
            vaultURL: vault
        )

        let snapshots = try await connector.fetchSnapshots()

        XCTAssertEqual(snapshots.map(\.remoteID), ["Archive/NestedMarkerReference.md"])
    }

    func testFetchSnapshotsKeepsLegitimateNoteWhenOpeningFenceIsNotExactFrontmatterFence() async throws {
        let vault = try makeObsidianTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: vault) }
        _ = try writeObsidianFile(
            """
            ----
            knowyou_export: daily_memory
            ---
            # Legit note
            """,
            at: "Archive/LongDashOpening.md",
            in: vault
        )

        let connector = ObsidianKnowledgeConnector(
            connectorInstanceID: "obsidian-main",
            vaultURL: vault
        )

        let snapshots = try await connector.fetchSnapshots()

        XCTAssertEqual(snapshots.map(\.remoteID), ["Archive/LongDashOpening.md"])
    }

    func testFetchSnapshotsKeepsLegitimateNoteWithJsonMarkerReferenceInBody() async throws {
        let vault = try makeObsidianTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: vault) }
        _ = try writeObsidianFile(
            """
            {"originKind":"daily_memory_export"}
            # This is documentation, not a JSON sidecar
            """,
            at: "Archive/JsonMarkerReference.md",
            in: vault
        )
        _ = try writeObsidianFile(
            #"{"originKind":"daily_memory_export"}"#,
            at: "Archive/JsonOnlyDataNote.md",
            in: vault
        )

        let connector = ObsidianKnowledgeConnector(
            connectorInstanceID: "obsidian-main",
            vaultURL: vault
        )

        let snapshots = try await connector.fetchSnapshots()

        XCTAssertEqual(snapshots.map(\.remoteID), ["Archive/JsonMarkerReference.md", "Archive/JsonOnlyDataNote.md"])
    }
}

private func makeObsidianTemporaryDirectory() throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appending(path: "KnowYouObsidianTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

@discardableResult
private func writeObsidianFile(
    _ contents: String,
    at relativePath: String,
    in root: URL,
    modifiedAt: Date = Date(timeIntervalSince1970: 1_778_201_000)
) throws -> URL {
    let url = relativePath
        .split(separator: "/")
        .reduce(root) { $0.appending(path: String($1)) }
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try contents.write(to: url, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.modificationDate: modifiedAt], ofItemAtPath: url.path)
    return url
}
