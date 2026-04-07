import Foundation
import SQLite3

enum DatabaseWriterError: Error {
    case openDatabase(message: String)
    case prepare(message: String)
    case bind(message: String)
    case execute(message: String)

    static func message(from database: OpaquePointer?) -> String {
        guard let database, let cString = sqlite3_errmsg(database) else {
            return "Unknown SQLite error"
        }
        return String(cString: cString)
    }
}

final class DatabaseWriter {
    private let database: OpaquePointer?

    init(path: String) throws {
        var connection: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX

        guard sqlite3_open_v2(path, &connection, flags, nil) == SQLITE_OK else {
            let message = DatabaseWriterError.message(from: connection)
            if let connection {
                sqlite3_close(connection)
            }
            throw DatabaseWriterError.openDatabase(message: message)
        }

        database = connection
        try Migrations.apply(to: database)
    }

    deinit {
        sqlite3_close(database)
    }

    static func inMemory() throws -> DatabaseWriter {
        try DatabaseWriter(path: ":memory:")
    }

    func insert(_ event: EventRecord) throws {
        let statement = try prepare(
            sql: """
            INSERT OR IGNORE INTO events (
                id,
                sourceType,
                sourceApp,
                capturedAt,
                dayKey,
                text,
                auditText,
                privacyAction,
                contentHash
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
            """
        )
        defer { sqlite3_finalize(statement) }

        try bindText(event.id.uuidString, at: 1, in: statement)
        try bindText(event.sourceType.rawValue, at: 2, in: statement)
        try bindText(event.sourceApp, at: 3, in: statement)
        guard sqlite3_bind_double(statement, 4, event.capturedAt.timeIntervalSince1970) == SQLITE_OK else {
            throw DatabaseWriterError.bind(message: DatabaseWriterError.message(from: database))
        }
        try bindText(event.dayKey, at: 5, in: statement)
        try bindOptionalText(event.text, at: 6, in: statement)
        try bindOptionalText(event.auditText, at: 7, in: statement)
        try bindText(event.privacyAction.rawValue, at: 8, in: statement)
        try bindText(event.contentHash, at: 9, in: statement)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw DatabaseWriterError.execute(message: DatabaseWriterError.message(from: database))
        }
    }

    func fetchEvents(dayKey: String) throws -> [EventRecord] {
        let statement = try prepare(
            sql: """
            SELECT
                id,
                sourceType,
                sourceApp,
                capturedAt,
                dayKey,
                text,
                auditText,
                privacyAction,
                contentHash
            FROM events
            WHERE dayKey = ?
            ORDER BY capturedAt ASC;
            """
        )
        defer { sqlite3_finalize(statement) }

        try bindText(dayKey, at: 1, in: statement)

        var events: [EventRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard
                let id = UUID(uuidString: text(at: 0, in: statement)),
                let sourceType = EventSourceType(rawValue: text(at: 1, in: statement)),
                let privacyAction = PrivacyAction(rawValue: text(at: 7, in: statement))
            else {
                continue
            }

            events.append(
                EventRecord(
                    id: id,
                    sourceType: sourceType,
                    sourceApp: text(at: 2, in: statement),
                    capturedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 3)),
                    dayKey: text(at: 4, in: statement),
                    text: optionalText(at: 5, in: statement),
                    auditText: optionalText(at: 6, in: statement),
                    privacyAction: privacyAction,
                    contentHash: text(at: 8, in: statement)
                )
            )
        }

        return events
    }

    private func prepare(sql: String) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseWriterError.prepare(message: DatabaseWriterError.message(from: database))
        }
        return statement
    }

    private func bindText(_ value: String, at index: Int32, in statement: OpaquePointer?) throws {
        guard sqlite3_bind_text(statement, index, value, -1, sqliteTransient) == SQLITE_OK else {
            throw DatabaseWriterError.bind(message: DatabaseWriterError.message(from: database))
        }
    }

    private func bindOptionalText(_ value: String?, at index: Int32, in statement: OpaquePointer?) throws {
        guard let value else {
            guard sqlite3_bind_null(statement, index) == SQLITE_OK else {
                throw DatabaseWriterError.bind(message: DatabaseWriterError.message(from: database))
            }
            return
        }

        try bindText(value, at: index, in: statement)
    }

    private func text(at index: Int32, in statement: OpaquePointer?) -> String {
        guard let cString = sqlite3_column_text(statement, index) else {
            return ""
        }
        return String(cString: cString)
    }

    private func optionalText(at index: Int32, in statement: OpaquePointer?) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else {
            return nil
        }
        return text(at: index, in: statement)
    }
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
