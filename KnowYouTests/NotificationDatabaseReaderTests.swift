import XCTest
import GRDB
@testable import KnowYou

final class NotificationDatabaseReaderTests: XCTestCase {
    func testFetchDeliveredNotificationsReadsDb2Schema() throws {
        let databaseURL = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).sqlite")
        let dbQueue = try DatabaseQueue(path: databaseURL.path)

        try dbQueue.write { db in
            try db.create(table: "app") { table in
                table.column("app_id", .integer).primaryKey()
                table.column("identifier", .text).notNull()
            }

            try db.create(table: "record") { table in
                table.column("rec_id", .integer).primaryKey()
                table.column("app_id", .integer).notNull()
                table.column("delivered_date", .double).notNull()
                table.column("data", .blob).notNull()
            }

            try db.execute(
                sql: "INSERT INTO app (app_id, identifier) VALUES (?, ?)",
                arguments: [1, "com.apple.mail"]
            )

            try db.execute(
                sql: "INSERT INTO record (rec_id, app_id, delivered_date, data) VALUES (?, ?, ?, ?)",
                arguments: [
                    1,
                    1,
                    Date(timeIntervalSince1970: 1_775_000_500).timeIntervalSinceReferenceDate,
                    makePayload(title: "Alice", subtitle: "Inbox", body: "Meet at 3 PM"),
                ]
            )
        }

        let reader = NotificationDatabaseReader(candidateDatabaseURLs: [databaseURL])
        let notifications = try reader.fetchDeliveredNotifications(since: Date(timeIntervalSince1970: 1_775_000_000))

        XCTAssertEqual(notifications.count, 1)
        XCTAssertEqual(notifications[0].appName, "com.apple.mail")
        XCTAssertEqual(notifications[0].body, "Alice\nInbox\nMeet at 3 PM")
    }

    func testFetchDeliveredNotificationsReturnsEmptyWhenDatabaseDoesNotExist() throws {
        let reader = NotificationDatabaseReader(
            candidateDatabaseURLs: [URL(fileURLWithPath: "/tmp/\(UUID().uuidString)-missing.sqlite")]
        )

        XCTAssertTrue(try reader.fetchDeliveredNotifications(since: .distantPast).isEmpty)
    }

    func testAccessStatusReportsPermissionDeniedForUnreadableDatabase() throws {
        let databaseURL = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).sqlite")
        FileManager.default.createFile(atPath: databaseURL.path, contents: Data(), attributes: nil)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: databaseURL.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: databaseURL.path)
            try? FileManager.default.removeItem(at: databaseURL)
        }

        let reader = NotificationDatabaseReader(candidateDatabaseURLs: [databaseURL])
        let accessStatus = reader.accessStatus()

        XCTAssertEqual(accessStatus.state, .permissionDenied)
        XCTAssertEqual(accessStatus.databaseURL, databaseURL)
        XCTAssertFalse(reader.isAvailable)
    }

    private func makePayload(title: String, subtitle: String, body: String) throws -> Data {
        let payload: [String: Any] = [
            "req": [
                "titl": title,
                "subt": subtitle,
                "body": body,
            ]
        ]

        return try PropertyListSerialization.data(fromPropertyList: payload, format: .binary, options: 0)
    }
}
