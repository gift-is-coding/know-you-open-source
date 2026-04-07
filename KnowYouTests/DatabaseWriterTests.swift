import XCTest
import GRDB
@testable import KnowYou

final class DatabaseWriterTests: XCTestCase {
    func testInsertFilteredEventPersistsPrivacyAction() throws {
        let writer = try DatabaseWriter.inMemory()
        let event = makeEvent(contentHash: "hash-1")

        try writer.insert(event)

        let rows = try writer.fetchEvents(dayKey: "2026-04-07")
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.privacyAction, .keep)
    }

    func testInsertIgnoresDuplicateContentHash() throws {
        let writer = try DatabaseWriter.inMemory()
        let first = makeEvent(contentHash: "shared-hash")
        let second = EventRecord(
            id: UUID(),
            sourceType: .notification,
            sourceApp: "Mail",
            capturedAt: Date(timeIntervalSince1970: 1_775_000_100),
            dayKey: "2026-04-07",
            text: "Second event",
            auditText: nil,
            privacyAction: .redact,
            contentHash: "shared-hash"
        )

        try writer.insert(first)
        XCTAssertNoThrow(try writer.insert(second))

        let rows = try writer.fetchEvents(dayKey: "2026-04-07")
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.id, first.id)
        XCTAssertEqual(rows.first?.contentHash, first.contentHash)
    }

    func testDuplicateHashesAreIgnored() throws {
        let writer = try DatabaseWriter.inMemory()
        let first = EventRecord(
            id: UUID(),
            sourceType: .clipboard,
            sourceApp: "Taio",
            capturedAt: Date(timeIntervalSince1970: 1_775_000_001),
            dayKey: "2026-04-07",
            text: "same payload",
            auditText: nil,
            privacyAction: .keep,
            contentHash: "same-hash"
        )

        let second = EventRecord(
            id: UUID(),
            sourceType: .clipboard,
            sourceApp: "Taio",
            capturedAt: Date(timeIntervalSince1970: 1_775_000_002),
            dayKey: "2026-04-07",
            text: "same payload",
            auditText: nil,
            privacyAction: .keep,
            contentHash: "same-hash"
        )

        try writer.insert(first)
        try writer.insert(second)

        XCTAssertEqual(try writer.fetchEvents(dayKey: "2026-04-07").count, 1)
    }

    func testFetchEventsThrowsWhenStoredRowHasInvalidUUID() throws {
        let databaseURL = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).sqlite")
        let writer = try DatabaseWriter(path: databaseURL.path)
        let dbQueue = try DatabaseQueue(path: databaseURL.path)

        try dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO events
                (id, sourceType, sourceApp, capturedAt, dayKey, text, auditText, privacyAction, contentHash)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    "not-a-uuid",
                    "clipboard",
                    "Taio",
                    Date(timeIntervalSince1970: 1_775_000_200),
                    "2026-04-07",
                    "Broken row",
                    nil,
                    "keep",
                    "invalid-uuid-hash",
                ]
            )
        }

        XCTAssertThrowsError(try writer.fetchEvents(dayKey: "2026-04-07"))
    }

    func testFetchEventsThrowsWhenStoredRowHasInvalidPrivacyAction() throws {
        let databaseURL = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).sqlite")
        let writer = try DatabaseWriter(path: databaseURL.path)
        let dbQueue = try DatabaseQueue(path: databaseURL.path)

        try dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO events
                (id, sourceType, sourceApp, capturedAt, dayKey, text, auditText, privacyAction, contentHash)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    UUID().uuidString,
                    "clipboard",
                    "Taio",
                    Date(timeIntervalSince1970: 1_775_000_300),
                    "2026-04-07",
                    "Broken action",
                    nil,
                    "invalid-action",
                    "invalid-action-hash",
                ]
            )
        }

        XCTAssertThrowsError(try writer.fetchEvents(dayKey: "2026-04-07"))
    }

    private func makeEvent(contentHash: String) -> EventRecord {
        EventRecord(
            id: UUID(),
            sourceType: .clipboard,
            sourceApp: "Taio",
            capturedAt: Date(timeIntervalSince1970: 1_775_000_000),
            dayKey: "2026-04-07",
            text: "Draft message",
            auditText: nil,
            privacyAction: .keep,
            contentHash: contentHash
        )
    }
}
