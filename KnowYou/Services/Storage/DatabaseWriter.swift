import Foundation
import GRDB

final class DatabaseWriter {
    private let dbQueue: DatabaseQueue

    init(path: String) throws {
        dbQueue = try DatabaseQueue(path: path)
        try Migrations.migrator().migrate(dbQueue)
    }

    static func inMemory() throws -> DatabaseWriter {
        try DatabaseWriter(path: ":memory:")
    }

    func insert(_ event: EventRecord) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT OR IGNORE INTO events
                (id, sourceType, sourceApp, capturedAt, dayKey, text, auditText, privacyAction, contentHash)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    event.id.uuidString,
                    event.sourceType.rawValue,
                    event.sourceApp,
                    event.capturedAt,
                    event.dayKey,
                    event.text,
                    event.auditText,
                    event.privacyAction.rawValue,
                    event.contentHash,
                ]
            )
        }
    }

    func fetchEvents(dayKey: String) throws -> [EventRecord] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT * FROM events WHERE dayKey = ? ORDER BY capturedAt ASC",
                arguments: [dayKey]
            )

            return rows.map { row in
                let id = UUID(uuidString: row["id"]) ?? UUID()
                let sourceType = EventSourceType(rawValue: row["sourceType"]) ?? .clipboard
                let sourceApp: String = row["sourceApp"]
                let capturedAt: Date = row["capturedAt"]
                let storedDayKey: String = row["dayKey"]
                let text: String? = row["text"]
                let auditText: String? = row["auditText"]
                let privacyAction = PrivacyAction(rawValue: row["privacyAction"]) ?? .keep
                let contentHash: String = row["contentHash"]

                return EventRecord(
                    id: id,
                    sourceType: sourceType,
                    sourceApp: sourceApp,
                    capturedAt: capturedAt,
                    dayKey: storedDayKey,
                    text: text,
                    auditText: auditText,
                    privacyAction: privacyAction,
                    contentHash: contentHash
                )
            }
        }
    }
}
