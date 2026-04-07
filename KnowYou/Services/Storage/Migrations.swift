import Foundation
import SQLite3

enum Migrations {
    static func apply(to database: OpaquePointer?) throws {
        for statement in statements {
            guard sqlite3_exec(database, statement, nil, nil, nil) == SQLITE_OK else {
                throw DatabaseWriterError.execute(message: DatabaseWriterError.message(from: database))
            }
        }
    }

    private static let statements = [
        """
        CREATE TABLE IF NOT EXISTS events (
            id TEXT PRIMARY KEY,
            sourceType TEXT NOT NULL,
            sourceApp TEXT NOT NULL,
            capturedAt REAL NOT NULL,
            dayKey TEXT NOT NULL,
            text TEXT,
            auditText TEXT,
            privacyAction TEXT NOT NULL,
            contentHash TEXT NOT NULL UNIQUE
        );
        """,
        """
        CREATE TABLE IF NOT EXISTS runs (
            id TEXT PRIMARY KEY,
            runType TEXT NOT NULL,
            startedAt REAL NOT NULL,
            finishedAt REAL,
            status TEXT NOT NULL
        );
        """,
    ]
}
