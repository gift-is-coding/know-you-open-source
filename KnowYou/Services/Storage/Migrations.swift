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
                table.column("startedAt", .datetime).notNull()
                table.column("finishedAt", .datetime)
                table.column("status", .text).notNull()
            }
        }

        return migrator
    }
}
