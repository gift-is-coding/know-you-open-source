import Foundation

struct NotificationSnapshot {
    let appName: String
    let deliveredAt: Date
    let body: String
}

struct NotificationImportResult: Sendable {
    let importedCount: Int
    let importedAt: Date
    let accessStatus: NotificationDatabaseAccessStatus
}

final class NotificationCollector: @unchecked Sendable {
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
                contentHash: Self.contentHash(for: snapshot, payload: payload, dayKey: dayKey)
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

    private static func contentHash(for snapshot: NotificationSnapshot, payload: String, dayKey: String) -> String {
        SHA256Hasher.hash(
            [
                snapshot.appName,
                payload,
                dayKey,
                String(snapshot.deliveredAt.timeIntervalSinceReferenceDate.bitPattern),
            ].joined(separator: "|")
        )
    }

    func accessStatus() -> NotificationDatabaseAccessStatus {
        databaseReader?.accessStatus() ?? NotificationDatabaseAccessStatus(state: .missing, databaseURL: nil)
    }

    func importDeliveredNotifications(from startDate: Date, upperBound: NotificationFetchUpperBound? = nil) throws -> NotificationImportResult {
        guard let databaseReader else {
            return NotificationImportResult(
                importedCount: 0,
                importedAt: Date(),
                accessStatus: NotificationDatabaseAccessStatus(state: .missing, databaseURL: nil)
            )
        }

        let accessStatus = databaseReader.accessStatus()
        let snapshots = try databaseReader.fetchDeliveredNotifications(from: startDate, upperBound: upperBound)

        return NotificationImportResult(
            importedCount: ingest(snapshots),
            importedAt: Date(),
            accessStatus: accessStatus
        )
    }

    func importDeliveredNotificationsInBackground(
        from startDate: Date,
        upperBound: NotificationFetchUpperBound? = nil
    ) async throws -> NotificationImportResult {
        try await Task.detached(priority: .utility) { [self] in
            try importDeliveredNotifications(from: startDate, upperBound: upperBound)
        }.value
    }

    func importDeliveredNotifications(from startDate: Date, through endDate: Date) throws -> NotificationImportResult {
        try importDeliveredNotifications(
            from: startDate,
            upperBound: .inclusive(max(endDate, startDate))
        )
    }

    func importDeliveredNotifications(from startDate: Date, until endDate: Date) throws -> NotificationImportResult {
        try importDeliveredNotifications(
            from: startDate,
            upperBound: .exclusive(max(endDate, startDate))
        )
    }

    func importDeliveredNotifications(from startDate: Date) throws -> NotificationImportResult {
        try importDeliveredNotifications(from: startDate, upperBound: nil)
    }

    func importDeliveredNotifications(since: Date) throws -> NotificationImportResult {
        try importDeliveredNotifications(from: since)
    }
}
