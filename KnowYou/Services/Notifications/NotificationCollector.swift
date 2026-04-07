import Foundation

struct NotificationSnapshot {
    let appName: String
    let deliveredAt: Date
    let body: String
}

final class NotificationCollector {
    private let privacyFilter: PrivacyFilter
    private let databaseWriter: DatabaseWriter

    init(privacyFilter: PrivacyFilter, databaseWriter: DatabaseWriter) {
        self.privacyFilter = privacyFilter
        self.databaseWriter = databaseWriter
    }

    func ingest(_ snapshots: [NotificationSnapshot]) {
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
        }
    }
}
