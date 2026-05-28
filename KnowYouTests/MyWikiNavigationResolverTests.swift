import XCTest
@testable import KnowYou

final class MyWikiNavigationResolverTests: XCTestCase {
    func testResolveSourcePrefersWikiSourceSummaryForMarkdown() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        let wikiSources = root.appending(path: "wiki/sources", directoryHint: .isDirectory)
        let rawSources = root.appending(path: "raw/sources", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: wikiSources, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: rawSources, withIntermediateDirectories: true)
        try "# Source summary".write(to: wikiSources.appending(path: "knowyou-diary-2026-05-06.md"), atomically: true, encoding: .utf8)
        try "# Raw source".write(to: rawSources.appending(path: "knowyou-diary-2026-05-06.md"), atomically: true, encoding: .utf8)

        let url = MyWikiNavigationResolver().resolveSourceURL("knowyou-diary-2026-05-06.md", projectRoot: root)

        XCTAssertEqual(url?.path, wikiSources.appending(path: "knowyou-diary-2026-05-06.md").path)
    }

    func testResolveSourceFallsBackToRawSources() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        let rawSources = root.appending(path: "raw/sources", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: rawSources, withIntermediateDirectories: true)
        try "# Raw source".write(to: rawSources.appending(path: "meeting-notes.txt"), atomically: true, encoding: .utf8)

        let url = MyWikiNavigationResolver().resolveSourceURL("meeting-notes.txt", projectRoot: root)

        XCTAssertEqual(url?.path, rawSources.appending(path: "meeting-notes.txt").path)
    }

    func testResolveRelatedEntryFindsEntryByID() throws {
        let entry = MyWikiEntry(
            id: "adam-wu",
            title: "Adam Wu",
            category: .entity,
            summary: "Summary",
            sourceNames: []
        )
        let snapshot = MyWikiDashboardSnapshot(
            sources: [],
            entities: [entry],
            concepts: []
        )

        let resolved = MyWikiNavigationResolver().resolveRelatedEntry("adam-wu", snapshot: snapshot)

        XCTAssertEqual(resolved?.id, "adam-wu")
    }

    func testResolveRelatedEntryFindsEntryByTitleSlug() throws {
        let entry = MyWikiEntry(
            id: "adam",
            title: "Adam Wu",
            category: .entity,
            summary: "Summary",
            sourceNames: []
        )
        let snapshot = MyWikiDashboardSnapshot(
            sources: [],
            entities: [entry],
            concepts: []
        )

        let resolved = MyWikiNavigationResolver().resolveRelatedEntry("[[adam-wu|Adam]]", snapshot: snapshot)

        XCTAssertEqual(resolved?.id, "adam")
    }
}
