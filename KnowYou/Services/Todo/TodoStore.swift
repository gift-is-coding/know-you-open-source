import Foundation

struct TodoStore {
    private let databaseWriter: DatabaseWriter

    init(databaseWriter: DatabaseWriter) {
        self.databaseWriter = databaseWriter
    }

    func createTodo(
        title: String,
        sourceDayKey: String,
        sourceEventIDs: [UUID],
        createdAt: Date,
        promotionKind: UnifiedTodoItem.PromotionKind
    ) throws -> UnifiedTodoItem {
        try databaseWriter.createTodo(
            title: title,
            sourceDayKey: sourceDayKey,
            sourceEventIDs: sourceEventIDs,
            createdAt: createdAt,
            promotionKind: promotionKind
        )
    }

    func fetchTodoItems() throws -> [UnifiedTodoItem] {
        try databaseWriter.fetchTodoItems()
    }

    func completeTodo(
        id: String,
        completedAt: Date,
        completionKind: UnifiedTodoItem.CompletionKind,
        evidenceEventIDs: [UUID]
    ) throws {
        try databaseWriter.completeTodo(
            id: id,
            completedAt: completedAt,
            completionKind: completionKind,
            evidenceEventIDs: evidenceEventIDs
        )
    }

    func mergeTodoEvidence(id: String, sourceEventIDs: [UUID]) throws {
        try databaseWriter.mergeTodoEvidence(id: id, sourceEventIDs: sourceEventIDs)
    }
}
