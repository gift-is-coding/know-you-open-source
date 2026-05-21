import Foundation
import GRDB

protocol EventWriting {
    func insert(_ event: EventRecord) throws
}

private enum DatabaseWriterRowError: Error {
    case invalidValue(field: String, value: String)
}

final class DatabaseWriter: EventWriting {
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

    func upsertImportedKnowledgeDocument(_ document: ImportedKnowledgeDocument) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO knowledge_import_documents
                (id, connectorInstanceID, connectorID, remoteID, title, sourcePath, remoteURL, mimeType, contentHash,
                 remoteUpdatedAt, firstImportedAt, lastSyncedAt, deletedAt, localContentPath, localMetadataPath,
                 normalizationVersion, originKind)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(connectorInstanceID, remoteID) DO UPDATE SET
                    title = excluded.title,
                    sourcePath = excluded.sourcePath,
                    remoteURL = excluded.remoteURL,
                    mimeType = excluded.mimeType,
                    contentHash = excluded.contentHash,
                    remoteUpdatedAt = excluded.remoteUpdatedAt,
                    lastSyncedAt = excluded.lastSyncedAt,
                    deletedAt = excluded.deletedAt,
                    localContentPath = excluded.localContentPath,
                    localMetadataPath = excluded.localMetadataPath,
                    normalizationVersion = excluded.normalizationVersion,
                    originKind = excluded.originKind
                """,
                arguments: [
                    document.id,
                    document.connectorInstanceID,
                    document.connectorID.rawValue,
                    document.remoteID,
                    document.title,
                    document.sourcePath,
                    document.remoteURL,
                    document.mimeType,
                    document.contentHash,
                    document.remoteUpdatedAt,
                    document.firstImportedAt,
                    document.lastSyncedAt,
                    document.deletedAt,
                    document.localContentPath,
                    document.localMetadataPath,
                    document.normalizationVersion,
                    document.originKind,
                ]
            )
        }
    }

    func fetchImportedKnowledgeDocuments(
        connectorInstanceID: String? = nil,
        includeDeleted: Bool = false
    ) throws -> [ImportedKnowledgeDocument] {
        try dbQueue.read { db in
            var clauses: [String] = []
            var arguments: [DatabaseValueConvertible?] = []
            if let connectorInstanceID {
                clauses.append("connectorInstanceID = ?")
                arguments.append(connectorInstanceID)
            }
            if !includeDeleted {
                clauses.append("deletedAt IS NULL")
            }

            let whereSQL = clauses.isEmpty ? "" : " WHERE " + clauses.joined(separator: " AND ")
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT * FROM knowledge_import_documents\(whereSQL) ORDER BY title ASC",
                arguments: StatementArguments(arguments)
            )
            return try rows.map(Self.importedKnowledgeDocument(from:))
        }
    }

    func markImportedKnowledgeDocumentDeleted(
        connectorInstanceID: String,
        remoteID: String,
        deletedAt: Date
    ) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                UPDATE knowledge_import_documents
                SET deletedAt = ?, lastSyncedAt = ?
                WHERE connectorInstanceID = ? AND remoteID = ?
                """,
                arguments: [deletedAt, deletedAt, connectorInstanceID, remoteID]
            )
        }
    }

    func startRun(runType: String, dayKey: String?) throws -> UUID {
        let runID = UUID()
        try dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO runs
                (id, runType, dayKey, startedAt, finishedAt, status)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    runID.uuidString,
                    runType,
                    dayKey,
                    Date(),
                    nil,
                    "running",
                ]
            )
        }

        return runID
    }

    func finishRun(id: UUID, status: String) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                UPDATE runs
                SET finishedAt = ?, status = ?
                WHERE id = ?
                """,
                arguments: [
                    Date(),
                    status,
                    id.uuidString,
                ]
            )
        }
    }

    func fetchLatestSuccessfulRunDay(runType: String) throws -> String? {
        try dbQueue.read { db in
            try String.fetchOne(
                db,
                sql: """
                SELECT dayKey
                FROM runs
                WHERE runType = ? AND status = 'succeeded' AND dayKey IS NOT NULL
                ORDER BY dayKey DESC, finishedAt DESC
                LIMIT 1
                """,
                arguments: [runType]
            )
        }
    }

    func markOrphanRunsAsFailed() throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE runs SET status = 'failed', finishedAt = ? WHERE status = 'running'",
                arguments: [Date()]
            )
        }
    }

    func fetchRuns(runType: String? = nil) throws -> [RunRecord] {
        try dbQueue.read { db in
            let rows: [Row]
            if let runType {
                rows = try Row.fetchAll(
                    db,
                    sql: "SELECT * FROM runs WHERE runType = ? ORDER BY startedAt ASC",
                    arguments: [runType]
                )
            } else {
                rows = try Row.fetchAll(
                    db,
                    sql: "SELECT * FROM runs ORDER BY startedAt ASC"
                )
            }

            return try rows.map { row in
                let idString: String = row["id"]
                guard let id = UUID(uuidString: idString) else {
                    throw DatabaseWriterRowError.invalidValue(field: "runs.id", value: idString)
                }

                return RunRecord(
                    id: id,
                    runType: row["runType"],
                    dayKey: row["dayKey"],
                    startedAt: row["startedAt"],
                    finishedAt: row["finishedAt"],
                    status: row["status"]
                )
            }
        }
    }

    private static func importedKnowledgeDocument(from row: Row) throws -> ImportedKnowledgeDocument {
        let connectorIDString: String = row["connectorID"]
        guard let connectorID = KnowledgeConnectorID(rawValue: connectorIDString) else {
            throw DatabaseWriterRowError.invalidValue(
                field: "knowledge_import_documents.connectorID",
                value: connectorIDString
            )
        }

        return ImportedKnowledgeDocument(
            id: row["id"],
            connectorInstanceID: row["connectorInstanceID"],
            connectorID: connectorID,
            remoteID: row["remoteID"],
            title: row["title"],
            sourcePath: row["sourcePath"],
            remoteURL: row["remoteURL"],
            mimeType: row["mimeType"],
            contentHash: row["contentHash"],
            remoteUpdatedAt: row["remoteUpdatedAt"],
            firstImportedAt: row["firstImportedAt"],
            lastSyncedAt: row["lastSyncedAt"],
            deletedAt: row["deletedAt"],
            localContentPath: row["localContentPath"],
            localMetadataPath: row["localMetadataPath"],
            normalizationVersion: row["normalizationVersion"],
            originKind: row["originKind"]
        )
    }
}
