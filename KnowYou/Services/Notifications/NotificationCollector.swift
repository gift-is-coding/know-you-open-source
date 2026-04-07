import Foundation

struct NotificationSnapshot {
    let appName: String
    let deliveredAt: Date
    let body: String
}

final class NotificationCollector {
    private let privacyFilter: PrivacyFilter
    private let databaseWriter: DatabaseWriter
    private let databaseReader: NotificationDatabaseReading?

    init(
        privacyFilter: PrivacyFilter,
        databaseWriter: DatabaseWriter,
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

            try? databaseWriter.insert(event)
            ingestedCount += 1
        }

        return ingestedCount
    }

    @discardableResult
    func importDeliveredNotifications(since: Date) throws -> Int {
        guard let databaseReader else {
            return 0
        }

        let snapshots = try databaseReader.fetchDeliveredNotifications(since: since)
        return ingest(snapshots)
    }
}
