import XCTest
@testable import KnowYou

final class GlobalSearchServiceTests: XCTestCase {
    func testSearchFindsDiarySourceAndTodo() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        let diaryURL = root.appending(path: "Vault/2026-04-24.md")
        let sourceURL = root.appending(path: "KnowledgeSources/local/main/content.md")
        try write("今天反复提到啥玩意这个表达。", to: diaryURL)
        try write("Imported source also says 啥玩意 in a project note.", to: sourceURL)

        let sourceDocument = ImportedKnowledgeDocument(
            id: "source-1",
            connectorInstanceID: "local-main",
            connectorID: .localFolderImport,
            remoteID: "Projects/source.md",
            title: "Project Source",
            sourcePath: "/Users/example/Projects/source.md",
            remoteURL: nil,
            mimeType: "text/markdown",
            contentHash: "hash",
            remoteUpdatedAt: nil,
            firstImportedAt: Date(timeIntervalSince1970: 1),
            lastSyncedAt: Date(timeIntervalSince1970: 2),
            deletedAt: nil,
            localContentPath: sourceURL.path,
            localMetadataPath: sourceURL.deletingLastPathComponent().appending(path: "metadata.json").path,
            normalizationVersion: 1,
            originKind: "local-folder"
        )
        let todo = UnifiedTodoItem(
            id: "todo-1",
            title: "Follow up on 啥玩意 taxonomy",
            normalizedTitle: "follow up on 啥玩意 taxonomy",
            status: .open,
            sourceDayKey: "2026-04-24",
            sourceEventIDs: [],
            createdAt: Date(timeIntervalSince1970: 3),
            completedAt: nil,
            completionEvidenceEventIDs: [],
            promotionKind: .manual,
            completionKind: nil
        )

        let response = GlobalSearchService().search(
            GlobalSearchRequest(
                query: "啥玩意",
                diaryNotes: ["2026-04-24": diaryURL],
                sourceDocuments: [sourceDocument],
                todoItems: [todo],
                maxResults: 10
            )
        )

        XCTAssertEqual(response.results.map(\.kind), [.todo, .diary, .source])
        XCTAssertEqual(response.groups.map(\.title), ["Todo", "Diary", "Sources"])
        XCTAssertTrue(response.results.allSatisfy { $0.snippet.contains("啥玩意") })
        XCTAssertEqual(response.results[0].todoID, "todo-1")
        XCTAssertEqual(response.results[1].dayKey, "2026-04-24")
        XCTAssertEqual(response.results[2].connectorInstanceID, "local-main")
        XCTAssertEqual(response.results[2].documentID, "source-1")
    }

    func testSearchFindsMyWikiEntitiesAndConcepts() {
        let entity = MyWikiEntry(
            id: "huang-shan",
            title: "Huang Shan",
            category: .entity,
            summary: "Huang Shan coordinates hardware acceleration boundaries.",
            sourceNames: ["Diary 2026-05-14"],
            aliases: ["黄山"],
            related: ["Agentic Engineering"],
            tags: ["hardware"],
            markdownBody: "Huang Shan appears across project planning notes."
        )
        let concept = MyWikiEntry(
            id: "agentic-engineering",
            title: "Agentic Engineering",
            category: .concept,
            summary: "Agentic engineering is a recurring working pattern.",
            sourceNames: ["Diary 2026-05-15"],
            aliases: ["agent workflow"],
            related: ["Huang Shan"],
            tags: ["workflow"],
            markdownBody: "Agentic Engineering connects plans, tests, and verification."
        )

        let response = GlobalSearchService().search(
            GlobalSearchRequest(
                query: "Agentic Engineering",
                diaryNotes: [:],
                sourceDocuments: [],
                todoItems: [],
                myWikiEntries: [entity, concept],
                maxResults: 10
            )
        )

        XCTAssertEqual(response.results.map(\.kind), [.myWiki, .myWiki])
        XCTAssertEqual(response.groups.map(\.title), ["My Wiki"])
        XCTAssertEqual(response.results.first?.title, "Agentic Engineering")
        XCTAssertEqual(response.results.first?.myWikiEntryID, "agentic-engineering")
        XCTAssertEqual(response.results.first?.myWikiCategoryID, MyWikiCategory.concept.id)
        XCTAssertTrue(response.results.first?.snippet.contains("Agentic Engineering") == true)
    }

    func testSearchReturnsEmptyForBlankQuery() {
        let response = GlobalSearchService().search(
            GlobalSearchRequest(query: "   ", diaryNotes: [:], sourceDocuments: [], todoItems: [])
        )

        XCTAssertTrue(response.results.isEmpty)
        XCTAssertTrue(response.groups.isEmpty)
    }

    private func write(_ contents: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }
}
