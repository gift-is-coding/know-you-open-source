import XCTest
@testable import KnowYou

final class TodoStoreTests: XCTestCase {
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
