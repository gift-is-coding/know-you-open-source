import XCTest
@testable import KnowYou

final class TodoStoreTests: XCTestCase {
    func testTodoStorePersistsToMarkdownDocument() throws {
        let writer = try DatabaseWriter.inMemory()
        let todoDocumentURL = URL.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
            .appending(path: "Todo.md")
        let store = TodoStore(databaseWriter: writer, documentURL: todoDocumentURL)
        let sourceEventID = UUID()

        let todo = try store.createTodo(
            title: "  Draft the provider config spec. ",
            sourceDayKey: "2026-05-28",
            sourceEventIDs: [sourceEventID],
            createdAt: Date(timeIntervalSince1970: 1_778_000_000),
            promotionKind: .manual
        )
        try store.completeTodo(
            id: todo.id,
            completedAt: Date(timeIntervalSince1970: 1_778_000_500),
            completionKind: .manual,
            evidenceEventIDs: []
        )

        let markdown = try String(contentsOf: todoDocumentURL, encoding: .utf8)
        XCTAssertTrue(markdown.contains("# Todo"), markdown)
        XCTAssertTrue(markdown.contains("## Completed"), markdown)
        XCTAssertTrue(markdown.contains("- [x] Draft the provider config spec."), markdown)
        XCTAssertTrue(markdown.contains("knowyou:todo"), markdown)

        let reloadedStore = TodoStore(databaseWriter: writer, documentURL: todoDocumentURL)
        let items = try reloadedStore.fetchTodoItems()

        XCTAssertEqual(items.map(\.id), [todo.id])
        XCTAssertEqual(items.first?.status, .completed)
        XCTAssertEqual(items.first?.sourceEventIDs, [sourceEventID])
    }

    func testTodoStoreSeedsMarkdownFromExistingDatabaseItems() throws {
        let writer = try DatabaseWriter.inMemory()
        let seeded = try writer.createTodo(
            title: "Follow up the SkillHub architecture discussion",
            sourceDayKey: "2026-05-27",
            sourceEventIDs: [],
            createdAt: Date(timeIntervalSince1970: 1_778_000_000),
            promotionKind: .manual
        )
        let todoDocumentURL = URL.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
            .appending(path: "Todo.md")
        let store = TodoStore(databaseWriter: writer, documentURL: todoDocumentURL)

        let items = try store.fetchTodoItems()
        let markdown = try String(contentsOf: todoDocumentURL, encoding: .utf8)

        XCTAssertEqual(items.map(\.id), [seeded.id])
        XCTAssertTrue(markdown.contains("- [ ] Follow up the SkillHub architecture discussion"), markdown)
    }

    func testTodoStoreCreatesMergesCompletesAndFetchesCompletedAtBottom() throws {
        let writer = try DatabaseWriter.inMemory()
        let store = TodoStore(databaseWriter: writer)
        let firstEventID = UUID()
        let secondEventID = UUID()
        let evidenceEventID = UUID()

        let todo = try store.createTodo(
            title: "Send the investor recap",
            sourceDayKey: "2026-05-27",
            sourceEventIDs: [firstEventID],
            createdAt: Date(timeIntervalSince1970: 1_778_000_000),
            promotionKind: .auto
        )
        let duplicate = try store.createTodo(
            title: "send the investor recap",
            sourceDayKey: "2026-05-28",
            sourceEventIDs: [secondEventID],
            createdAt: Date(timeIntervalSince1970: 1_778_000_200),
            promotionKind: .manual
        )
        let open = try store.createTodo(
            title: "Confirm Friday meeting time",
            sourceDayKey: "2026-05-28",
            sourceEventIDs: [],
            createdAt: Date(timeIntervalSince1970: 1_778_000_300),
            promotionKind: .manual
        )

        try store.completeTodo(
            id: todo.id,
            completedAt: Date(timeIntervalSince1970: 1_778_000_500),
            completionKind: .evidenceSweep,
            evidenceEventIDs: [evidenceEventID]
        )

        let items = try store.fetchTodoItems()

        XCTAssertEqual(todo.id, duplicate.id)
        XCTAssertEqual(items.map(\.id), [open.id, todo.id])
        XCTAssertEqual(items.first?.status, .open)
        XCTAssertEqual(items.last?.status, .completed)
        XCTAssertEqual(Set(items.last?.sourceEventIDs ?? []), Set([firstEventID, secondEventID]))
        XCTAssertEqual(items.last?.completionKind, .evidenceSweep)
        XCTAssertEqual(items.last?.completionEvidenceEventIDs, [evidenceEventID])
    }
}
