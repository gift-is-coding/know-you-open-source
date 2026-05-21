import Foundation
import GRDB

enum Migrations {
    static func migrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("createEvents") { db in
            try db.create(table: "events") { table in
                table.column("id", .text).primaryKey()
                table.column("sourceType", .text).notNull()
                table.column("sourceApp", .text).notNull()
                table.column("capturedAt", .datetime).notNull()
                table.column("dayKey", .text).notNull()
                table.column("text", .text)
                table.column("auditText", .text)
                table.column("privacyAction", .text).notNull()
                table.column("contentHash", .text).notNull().unique()
            }
        }

        migrator.registerMigration("createRuns") { db in
            try db.create(table: "runs") { table in
                table.column("id", .text).primaryKey()
                table.column("runType", .text).notNull()
                table.column("dayKey", .text)
                table.column("startedAt", .datetime).notNull()
                table.column("finishedAt", .datetime)
                table.column("status", .text).notNull()
            }
        }

        migrator.registerMigration("addDayKeyToRuns") { db in
            guard try db.tableExists("runs") else {
                return
            }

            let columns = try db.columns(in: "runs").map(\.name)
            if !columns.contains("dayKey") {
                try db.alter(table: "runs") { table in
                    table.add(column: "dayKey", .text)
                }
            }
        }

        migrator.registerMigration("createKnowledgeImports") { db in
            try db.create(table: "knowledge_import_documents", ifNotExists: true) { table in
                table.column("id", .text).primaryKey()
                table.column("connectorInstanceID", .text).notNull()
                table.column("connectorID", .text).notNull()
                table.column("remoteID", .text).notNull()
                table.column("title", .text).notNull()
                table.column("sourcePath", .text)
                table.column("remoteURL", .text)
                table.column("mimeType", .text).notNull()
                table.column("contentHash", .text).notNull()
                table.column("remoteUpdatedAt", .datetime)
                table.column("firstImportedAt", .datetime).notNull()
                table.column("lastSyncedAt", .datetime).notNull()
                table.column("deletedAt", .datetime)
                table.column("localContentPath", .text).notNull()
                table.column("localMetadataPath", .text).notNull()
                table.column("normalizationVersion", .integer).notNull()
                table.column("originKind", .text).notNull()
                table.uniqueKey(["connectorInstanceID", "remoteID"])
            }

            try db.create(table: "knowledge_import_status", ifNotExists: true) { table in
                table.column("connectorInstanceID", .text).primaryKey()
                table.column("lastStartedAt", .datetime)
                table.column("lastSucceededAt", .datetime)
                table.column("lastFailedAt", .datetime)
                table.column("lastErrorMessage", .text)
                table.column("lastChangedDocumentCount", .integer).notNull().defaults(to: 0)
            }
        }

        return migrator
    }
}
