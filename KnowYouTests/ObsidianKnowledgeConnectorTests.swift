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

    func testFetchSnapshotsSkipsKnowYouExportMarkersButKeepsLegitimateNotesOutsideExportDirectory() async throws {
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

        XCTAssertEqual(snapshots.map(\.remoteID), ["Archive/Legitimate.md"])
        let legitimate = try XCTUnwrap(snapshots.first)
        XCTAssertEqual(legitimate.connectorID, .obsidianImport)
        XCTAssertEqual(legitimate.originKind, "obsidian-vault")
        XCTAssertEqual(legitimate.contentMarkdown, "# Legitimate note\nThis is not a KnowYou export.")
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
