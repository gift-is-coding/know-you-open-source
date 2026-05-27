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

    func createTodo(
        title: String,
        sourceDayKey: String,
        sourceEventIDs: [UUID],
        createdAt: Date,
        promotionKind: UnifiedTodoItem.PromotionKind
    ) throws -> UnifiedTodoItem {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedTitle = UnifiedTodoItem.normalizeTitle(cleanTitle)
        let item = UnifiedTodoItem(
            id: UUID().uuidString,
            title: cleanTitle,
            normalizedTitle: normalizedTitle,
            status: .open,
            sourceDayKey: sourceDayKey,
            sourceEventIDs: Self.uniqueUUIDs(sourceEventIDs),
            createdAt: createdAt,
            completedAt: nil,
            completionEvidenceEventIDs: [],
            promotionKind: promotionKind,
            completionKind: nil
        )

        return try dbQueue.write { db in
            if let existing = try Self.fetchTodo(normalizedTitle: normalizedTitle, from: db) {
                let mergedSourceIDs = Self.uniqueUUIDs(existing.sourceEventIDs + sourceEventIDs)
                try db.execute(
                    sql: """
                    UPDATE todo_items
                    SET sourceEventIDsJSON = ?
                    WHERE id = ?
                    """,
                    arguments: [
                        try Self.uuidJSON(mergedSourceIDs),
                        existing.id,
                    ]
                )
                var updated = existing
                updated.sourceEventIDs = mergedSourceIDs
                return updated
            }

            try Self.insertTodo(item, into: db)
            return item
        }
    }

    func fetchTodoItems() throws -> [UnifiedTodoItem] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT *
                FROM todo_items
                ORDER BY
                    CASE status WHEN 'open' THEN 0 ELSE 1 END ASC,
                    createdAt ASC,
                    completedAt ASC
                """
            )
            return try rows.map(Self.todoItem(from:))
        }
    }

    func completeTodo(
        id: String,
        completedAt: Date,
        completionKind: UnifiedTodoItem.CompletionKind,
        evidenceEventIDs: [UUID]
    ) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                UPDATE todo_items
                SET status = ?, completedAt = ?, completionKind = ?, completionEvidenceEventIDsJSON = ?
                WHERE id = ?
                """,
                arguments: [
                    UnifiedTodoItem.Status.completed.rawValue,
                    completedAt,
                    completionKind.rawValue,
                    try Self.uuidJSON(Self.uniqueUUIDs(evidenceEventIDs)),
                    id,
                ]
            )
        }
    }

    func mergeTodoEvidence(id: String, sourceEventIDs: [UUID]) throws {
        try dbQueue.write { db in
            guard let existing = try Self.fetchTodo(id: id, from: db) else { return }
            let mergedSourceIDs = Self.uniqueUUIDs(existing.sourceEventIDs + sourceEventIDs)
            try db.execute(
                sql: "UPDATE todo_items SET sourceEventIDsJSON = ? WHERE id = ?",
                arguments: [try Self.uuidJSON(mergedSourceIDs), id]
            )
        }
    }

    func upsertImportedKnowledgeDocument(_ document: ImportedKnowledgeDocument) throws {
        try upsertImportedKnowledgeDocuments([document])
    }

    func upsertImportedKnowledgeDocuments(_ documents: [ImportedKnowledgeDocument]) throws {
        try dbQueue.inTransaction { db in
            for document in documents {
                try Self.upsertImportedKnowledgeDocument(document, into: db)
            }
            return .commit
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

    private static func upsertImportedKnowledgeDocument(
        _ document: ImportedKnowledgeDocument,
        into db: Database
    ) throws {
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

    private static func insertTodo(_ item: UnifiedTodoItem, into db: Database) throws {
        try db.execute(
            sql: """
            INSERT INTO todo_items
            (id, title, normalizedTitle, status, sourceDayKey, sourceEventIDsJSON, createdAt,
             completedAt, completionEvidenceEventIDsJSON, promotionKind, completionKind)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            arguments: [
                item.id,
                item.title,
                item.normalizedTitle,
                item.status.rawValue,
                item.sourceDayKey,
                try uuidJSON(item.sourceEventIDs),
                item.createdAt,
                item.completedAt,
                try uuidJSON(item.completionEvidenceEventIDs),
                item.promotionKind.rawValue,
                item.completionKind?.rawValue,
            ]
        )
    }

    private static func fetchTodo(normalizedTitle: String, from db: Database) throws -> UnifiedTodoItem? {
        guard let row = try Row.fetchOne(
            db,
            sql: "SELECT * FROM todo_items WHERE normalizedTitle = ? LIMIT 1",
            arguments: [normalizedTitle]
        ) else {
            return nil
        }
        return try todoItem(from: row)
    }

    private static func fetchTodo(id: String, from db: Database) throws -> UnifiedTodoItem? {
        guard let row = try Row.fetchOne(
            db,
            sql: "SELECT * FROM todo_items WHERE id = ? LIMIT 1",
            arguments: [id]
        ) else {
            return nil
        }
        return try todoItem(from: row)
    }

    private static func todoItem(from row: Row) throws -> UnifiedTodoItem {
        let statusString: String = row["status"]
        guard let status = UnifiedTodoItem.Status(rawValue: statusString) else {
            throw DatabaseWriterRowError.invalidValue(field: "todo_items.status", value: statusString)
        }
        let promotionKindString: String = row["promotionKind"]
        guard let promotionKind = UnifiedTodoItem.PromotionKind(rawValue: promotionKindString) else {
            throw DatabaseWriterRowError.invalidValue(field: "todo_items.promotionKind", value: promotionKindString)
        }
        let completionKindString: String? = row["completionKind"]
        let completionKind = try completionKindString.map { value in
            guard let kind = UnifiedTodoItem.CompletionKind(rawValue: value) else {
                throw DatabaseWriterRowError.invalidValue(field: "todo_items.completionKind", value: value)
            }
            return kind
        }

        return UnifiedTodoItem(
            id: row["id"],
            title: row["title"],
            normalizedTitle: row["normalizedTitle"],
            status: status,
            sourceDayKey: row["sourceDayKey"],
            sourceEventIDs: try uuidArray(fromJSON: row["sourceEventIDsJSON"], field: "todo_items.sourceEventIDsJSON"),
            createdAt: row["createdAt"],
            completedAt: row["completedAt"],
            completionEvidenceEventIDs: try uuidArray(
                fromJSON: row["completionEvidenceEventIDsJSON"],
                field: "todo_items.completionEvidenceEventIDsJSON"
            ),
            promotionKind: promotionKind,
            completionKind: completionKind
        )
    }

    private static func uuidJSON(_ ids: [UUID]) throws -> String {
        let values = ids.map(\.uuidString)
        let data = try JSONEncoder().encode(values)
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    private static func uuidArray(fromJSON json: String, field: String) throws -> [UUID] {
        guard let data = json.data(using: .utf8),
              let values = try? JSONDecoder().decode([String].self, from: data)
        else {
            throw DatabaseWriterRowError.invalidValue(field: field, value: json)
        }
        var ids: [UUID] = []
        ids.reserveCapacity(values.count)
        for value in values {
            guard let id = UUID(uuidString: value) else {
                throw DatabaseWriterRowError.invalidValue(field: field, value: value)
            }
            ids.append(id)
        }
        return ids
    }

    private static func uniqueUUIDs(_ ids: [UUID]) -> [UUID] {
        var seen = Set<UUID>()
        var unique: [UUID] = []
        for id in ids where seen.insert(id).inserted {
            unique.append(id)
        }
        return unique
    }
}
