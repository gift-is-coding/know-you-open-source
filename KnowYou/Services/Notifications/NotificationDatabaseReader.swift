import Foundation
import GRDB

enum NotificationFetchUpperBound: Equatable {
    case exclusive(Date)
    case inclusive(Date)
}

protocol NotificationDatabaseReading {
    func accessStatus() -> NotificationDatabaseAccessStatus
    func fetchDeliveredNotifications(since: Date) throws -> [NotificationSnapshot]
    func fetchDeliveredNotifications(from startDate: Date, upperBound: NotificationFetchUpperBound?) throws -> [NotificationSnapshot]
}

extension NotificationDatabaseReading {
    func accessStatus() -> NotificationDatabaseAccessStatus {
        NotificationDatabaseAccessStatus(state: .available, databaseURL: nil)
    }

    var isAvailable: Bool {
        accessStatus().isAvailable
    }

    func fetchDeliveredNotifications(since: Date) throws -> [NotificationSnapshot] {
        try fetchDeliveredNotifications(from: since, upperBound: nil)
    }

    func fetchDeliveredNotifications(from startDate: Date, upperBound: NotificationFetchUpperBound?) throws -> [NotificationSnapshot] {
        let snapshots = try fetchDeliveredNotifications(since: startDate)
        guard let upperBound else {
            return snapshots
        }

        switch upperBound {
        case .exclusive(let endDate):
            return snapshots.filter { $0.deliveredAt < endDate }
        case .inclusive(let endDate):
            return snapshots.filter { $0.deliveredAt <= endDate }
        }
    }
}

struct NotificationDatabaseAccessStatus: Equatable {
    enum State: Equatable {
        case available
        case permissionDenied
        case missing
    }

    let state: State
    let databaseURL: URL?

    var isAvailable: Bool {
        state == .available
    }

    var message: String {
        switch state {
        case .available:
            if let databaseURL {
                return "Notification Center database available at \(databaseURL.path)"
            }
            return "Notification Center database available"
        case .permissionDenied:
            if let databaseURL {
                return "Notification Center database exists at \(databaseURL.path) but is not readable. Grant Full Disk Access."
            }
            return "Notification Center database exists but is not readable. Grant Full Disk Access."
        case .missing:
            return "Notification Center database not found on this Mac."
        }
    }
}

struct NotificationDatabaseReader: NotificationDatabaseReading {
    let candidateDatabaseURLs: [URL]
    private let fileManager: FileManager

    init(candidateDatabaseURLs: [URL] = Self.defaultCandidateDatabaseURLs(), fileManager: FileManager = .default) {
        self.candidateDatabaseURLs = candidateDatabaseURLs
        self.fileManager = fileManager
    }

    func fetchDeliveredNotifications(since: Date) throws -> [NotificationSnapshot] {
        try fetchDeliveredNotifications(from: since, upperBound: nil)
    }

    func fetchDeliveredNotifications(from startDate: Date, upperBound: NotificationFetchUpperBound?) throws -> [NotificationSnapshot] {
        let accessStatus = accessStatus()
        guard let databaseURL = accessStatus.databaseURL else {
            return []
        }
        guard accessStatus.isAvailable else {
            throw NotificationDatabaseReaderError.permissionDenied(path: databaseURL.path)
        }

        let snapshotURL = try makeReadableSnapshot(from: databaseURL)
        defer { try? fileManager.removeItem(at: snapshotURL.deletingLastPathComponent()) }

        let dbQueue = try DatabaseQueue(path: snapshotURL.path, configuration: snapshotConfiguration())
        return try dbQueue.read { db in
            let query = try databaseQuery(in: db, startDate: startDate, upperBound: upperBound)
            let rows = try Row.fetchAll(
                db,
                sql: query.sql,
                arguments: StatementArguments(query.arguments)
            )

            return rows.compactMap(Self.makeSnapshot)
        }
    }

    var isAvailable: Bool {
        accessStatus().isAvailable
    }

    func accessStatus() -> NotificationDatabaseAccessStatus {
        for candidateURL in candidateDatabaseURLs {
            guard fileManager.fileExists(atPath: candidateURL.path) else {
                continue
            }

            if fileManager.isReadableFile(atPath: candidateURL.path) {
                return NotificationDatabaseAccessStatus(state: .available, databaseURL: candidateURL)
            }

            return NotificationDatabaseAccessStatus(state: .permissionDenied, databaseURL: candidateURL)
        }

        return NotificationDatabaseAccessStatus(state: .missing, databaseURL: nil)
    }

    private func makeReadableSnapshot(from liveDatabaseURL: URL) throws -> URL {
        let snapshotDirectory = fileManager.temporaryDirectory
            .appending(path: "know-you-notification-snapshot-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: snapshotDirectory, withIntermediateDirectories: true)

        let snapshotDatabaseURL = snapshotDirectory.appending(path: liveDatabaseURL.lastPathComponent)
        try fileManager.copyItem(at: liveDatabaseURL, to: snapshotDatabaseURL)

        for suffix in ["-wal", "-shm"] {
            let liveSidecarURL = URL(fileURLWithPath: liveDatabaseURL.path + suffix)
            let snapshotSidecarURL = URL(fileURLWithPath: snapshotDatabaseURL.path + suffix)
            if fileManager.fileExists(atPath: liveSidecarURL.path) {
                try? fileManager.copyItem(at: liveSidecarURL, to: snapshotSidecarURL)
            }
        }

        return snapshotDatabaseURL
    }

    private func snapshotConfiguration() -> Configuration {
        var configuration = Configuration()
        configuration.readonly = true
        return configuration
    }

    private func databaseQuery(
        in db: Database,
        startDate: Date,
        upperBound: NotificationFetchUpperBound?
    ) throws -> NotificationQuery {
        let tables = try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table'")

        if tables.contains("record"), tables.contains("app") {
            return NotificationQuery(
                sql: makeQuerySQL(
                    appIdentifierColumn: "app.identifier",
                    deliveredDateColumn: "record.delivered_date",
                    dataColumn: "record.data",
                    fromClause: "FROM record LEFT JOIN app ON app.app_id = record.app_id",
                    upperBound: upperBound
                ),
                arguments: queryArguments(startDate: startDate, upperBound: upperBound)
            )
        }

        if tables.contains("notifications"), tables.contains("app_info") {
            return NotificationQuery(
                sql: makeQuerySQL(
                    appIdentifierColumn: "app_info.bundleid",
                    deliveredDateColumn: "notifications.delivered_date",
                    dataColumn: "notifications.data",
                    fromClause: "FROM notifications LEFT JOIN app_info ON app_info.app_id = notifications.app_id",
                    upperBound: upperBound
                ),
                arguments: queryArguments(startDate: startDate, upperBound: upperBound)
            )
        }

        throw NotificationDatabaseReaderError.unsupportedSchema(tables: tables.sorted())
    }

    private func makeQuerySQL(
        appIdentifierColumn: String,
        deliveredDateColumn: String,
        dataColumn: String,
        fromClause: String,
        upperBound: NotificationFetchUpperBound?
    ) -> String {
        let upperBoundClause: String
        switch upperBound {
        case .exclusive:
            upperBoundClause = " AND \(deliveredDateColumn) < ?"
        case .inclusive:
            upperBoundClause = " AND \(deliveredDateColumn) <= ?"
        case nil:
            upperBoundClause = ""
        }

        return (
            """
            SELECT app.identifier AS appIdentifier, record.delivered_date AS deliveredDate, record.data AS data
            \(fromClause)
            WHERE \(deliveredDateColumn) >= ?\(upperBoundClause)
            ORDER BY \(deliveredDateColumn) ASC
            """
        )
            .replacingOccurrences(of: "app.identifier", with: appIdentifierColumn)
            .replacingOccurrences(of: "record.delivered_date", with: deliveredDateColumn)
            .replacingOccurrences(of: "record.data", with: dataColumn)
    }

    private func queryArguments(
        startDate: Date,
        upperBound: NotificationFetchUpperBound?
    ) -> [Double] {
        var arguments = [startDate.timeIntervalSinceReferenceDate]
        switch upperBound {
        case .exclusive(let endDate), .inclusive(let endDate):
            arguments.append(endDate.timeIntervalSinceReferenceDate)
        case nil:
            break
        }
        return arguments
    }

    private static func makeSnapshot(from row: Row) -> NotificationSnapshot? {
        let appIdentifier: String = row["appIdentifier"]
        let deliveredDate: Double = row["deliveredDate"]
        let payload: Data = row["data"]

        guard let body = extractBody(from: payload), !body.isEmpty else {
            return nil
        }

        return NotificationSnapshot(
            appName: appIdentifier.isEmpty ? "Unknown" : appIdentifier,
            deliveredAt: Date(timeIntervalSinceReferenceDate: deliveredDate),
            body: body
        )
    }

    private static func extractBody(from payload: Data) -> String? {
        guard
            let propertyList = try? PropertyListSerialization.propertyList(
                from: payload,
                options: [],
                format: nil
            )
        else {
            return nil
        }

        var components: [String] = []
        appendTextComponents(from: propertyList, into: &components)
        let cleanedComponents = components
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var seenComponents = Set<String>()
        let uniqueComponents = cleanedComponents.filter { seenComponents.insert($0).inserted }

        return uniqueComponents.isEmpty ? nil : uniqueComponents.joined(separator: "\n")
    }

    private static func appendTextComponents(from value: Any, into components: inout [String]) {
        if let dictionary = value as? [String: Any] {
            if let request = dictionary["req"] as? [String: Any] {
                for key in ["titl", "subt", "body"] {
                    if let text = request[key] as? String {
                        components.append(text)
                    }
                }
            }

            for key in ["title", "subtitle", "body", "text", "message"] {
                if let text = dictionary[key] as? String {
                    components.append(text)
                }
            }

            for nestedValue in dictionary.values {
                appendTextComponents(from: nestedValue, into: &components)
            }
            return
        }

        if let array = value as? [Any] {
            for nestedValue in array {
                appendTextComponents(from: nestedValue, into: &components)
            }
        }
    }

    static func defaultCandidateDatabaseURLs() -> [URL] {
        var urls: [URL] = []
        let homeURL = FileManager.default.homeDirectoryForCurrentUser

        let darwinUserDirectoryBytes = confstrDarwinUserDir()
        if let nullTerminatorIndex = darwinUserDirectoryBytes.firstIndex(of: 0) {
            let utf8Bytes = darwinUserDirectoryBytes[..<nullTerminatorIndex].map { UInt8(bitPattern: $0) }
            let darwinUserDirectory = String(
                decoding: utf8Bytes,
                as: UTF8.self
            )
            let darwinURL = URL(filePath: darwinUserDirectory, directoryHint: .isDirectory)
            urls.append(darwinURL.appending(path: "com.apple.notificationcenter/db2/db"))
            urls.append(darwinURL.appending(path: "com.apple.notificationcenter/db/db"))
        }

        urls.append(homeURL.appending(path: "Library/Application Support/NotificationCenter/db2/db"))
        urls.append(homeURL.appending(path: "Library/Application Support/NotificationCenter/db/db"))
        urls.append(homeURL.appending(path: "Library/Group Containers/group.com.apple.usernoted/db2/db"))
        urls.append(homeURL.appending(path: "Library/Group Containers/group.com.apple.usernoted/db/db"))

        return urls
    }
}

private struct NotificationQuery {
    let sql: String
    let arguments: [Double]
}

private enum NotificationDatabaseReaderError: Error {
    case unsupportedSchema(tables: [String])
    case permissionDenied(path: String)
}

extension NotificationDatabaseReaderError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .unsupportedSchema(let tables):
            return "Unsupported Notification Center schema: \(tables.joined(separator: ", "))"
        case .permissionDenied(let path):
            return "Notification Center database exists at \(path) but is not readable. Grant Full Disk Access."
        }
    }
}

private func confstrDarwinUserDir() -> [CChar] {
    let size = confstr(_CS_DARWIN_USER_DIR, nil, 0)
    var buffer = [CChar](repeating: 0, count: Int(size))
    confstr(_CS_DARWIN_USER_DIR, &buffer, size)
    return buffer
}
