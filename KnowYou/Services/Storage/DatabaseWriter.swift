import Foundation
import GRDB

private enum DatabaseWriterRowError: Error {
    case invalidValue(field: String, value: String)
}

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
        do {
            try dbQueue.write { db in
                try db.execute(
                    sql: """
                    INSERT INTO events
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
        } catch let error as DatabaseError
            where error.extendedResultCode == .SQLITE_CONSTRAINT_UNIQUE &&
                error.message?.contains("events.contentHash") == true
        {
            return
        }
    }

    func fetchEvents(dayKey: String) throws -> [EventRecord] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT * FROM events WHERE dayKey = ? ORDER BY capturedAt ASC",
                arguments: [dayKey]
            )

            return try rows.map { row in
                let idString: String = row["id"]
                guard let id = UUID(uuidString: idString) else {
                    throw DatabaseWriterRowError.invalidValue(field: "id", value: idString)
                }

                let sourceTypeString: String = row["sourceType"]
                guard let sourceType = EventSourceType(rawValue: sourceTypeString) else {
                    throw DatabaseWriterRowError.invalidValue(field: "sourceType", value: sourceTypeString)
                }

                let sourceApp: String = row["sourceApp"]
                let capturedAt: Date = row["capturedAt"]
                let storedDayKey: String = row["dayKey"]
                let text: String? = row["text"]
                let auditText: String? = row["auditText"]
                let privacyActionString: String = row["privacyAction"]
                guard let privacyAction = PrivacyAction(rawValue: privacyActionString) else {
                    throw DatabaseWriterRowError.invalidValue(field: "privacyAction", value: privacyActionString)
                }
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
