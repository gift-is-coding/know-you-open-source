import Foundation

struct NotificationSnapshot {
    let appName: String
    let deliveredAt: Date
    let body: String
}

struct NotificationImportResult {
    let importedCount: Int
    let importedAt: Date
}

final class NotificationCollector {
    private let privacyFilter: PrivacyFilter
    private let databaseWriter: EventWriting
    private let databaseReader: NotificationDatabaseReading?

    init(
        privacyFilter: PrivacyFilter,
        databaseWriter: EventWriting,
        databaseReader: NotificationDatabaseReading? = nil
    ) {
        self.privacyFilter = privacyFilter
        self.databaseWriter = databaseWriter
        self.databaseReader = databaseReader
    }

    @discardableResult
    func ingest(_ snapshots: [NotificationSnapshot]) -> Int {
        var ingestedCount = 0
        for snapshot in snapshots {
            let filtered = privacyFilter.classify(snapshot.body)
            let payload = filtered.persistedText ?? filtered.auditText ?? ""
            let dayKey = ISO8601DayKey.format(snapshot.deliveredAt)
            let event = EventRecord(
                id: UUID(),
                sourceType: .notification,
                sourceApp: snapshot.appName,
                capturedAt: snapshot.deliveredAt,
                dayKey: dayKey,
                text: filtered.persistedText,
                auditText: filtered.auditText,
                privacyAction: filtered.action,
                contentHash: SHA256Hasher.hash(snapshot.appName + payload + dayKey)
            )

            do {
                try databaseWriter.insert(event)
                ingestedCount += 1
            } catch {
                print("NotificationCollector: failed to insert event: \(error)")
            }
        }

        return ingestedCount
    }

    func importDeliveredNotifications(since: Date) throws -> NotificationImportResult {
        guard let databaseReader else {
            return NotificationImportResult(importedCount: 0, importedAt: Date())
        }

        let snapshots = try databaseReader.fetchDeliveredNotifications(since: since)
        return NotificationImportResult(
            importedCount: ingest(snapshots),
            importedAt: Date()
        )
    }
}
