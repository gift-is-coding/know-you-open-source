import XCTest
import GRDB
@testable import KnowYou

private struct StubNotificationReader: NotificationDatabaseReading {
    func fetchDeliveredNotifications(since: Date) throws -> [NotificationSnapshot] { [] }
}

private struct FailingEventWriter: EventWriting {
    func insert(_ event: EventRecord) throws {
        throw CocoaError(.fileWriteUnknown)
    }
}

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

    func testInsertIgnoresDuplicateNotificationContentHash() throws {
        let writer = try DatabaseWriter.inMemory()
        let capturedAt = Date(timeIntervalSince1970: 1_776_000_000)
        let first = EventRecord(
            id: UUID(),
            sourceType: .notification,
            sourceApp: "com.apple.MobileSMS",
            capturedAt: capturedAt,
            dayKey: "2026-04-11",
            text: "hello",
            auditText: nil,
            privacyAction: .keep,
            contentHash: "same-notification-hash"
        )
        let second = EventRecord(
            id: UUID(),
            sourceType: .notification,
            sourceApp: "com.apple.MobileSMS",
            capturedAt: capturedAt,
            dayKey: "2026-04-11",
            text: "hello",
            auditText: nil,
            privacyAction: .keep,
            contentHash: "same-notification-hash"
        )

        try writer.insert(first)
        try writer.insert(second)

        let rows = try writer.fetchEvents(dayKey: "2026-04-11")
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.contentHash, "same-notification-hash")
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

    func testRunLifecyclePersistsDayKeyAndStatus() throws {
        let writer = try DatabaseWriter.inMemory()

        let runID = try writer.startRun(runType: "daily-note", dayKey: "2026-04-07")
        try writer.finishRun(id: runID, status: "succeeded")

        let runs = try writer.fetchRuns(runType: "daily-note")
        XCTAssertEqual(runs.count, 1)
        XCTAssertEqual(runs[0].id, runID)
        XCTAssertEqual(runs[0].dayKey, "2026-04-07")
        XCTAssertEqual(runs[0].status, "succeeded")
        XCTAssertNotNil(runs[0].finishedAt)
    }

    func testFetchLatestSuccessfulRunDayReturnsMostRecentSucceededDay() throws {
        let writer = try DatabaseWriter.inMemory()

        let first = try writer.startRun(runType: "daily-note", dayKey: "2026-04-06")
        try writer.finishRun(id: first, status: "succeeded")

        let failed = try writer.startRun(runType: "daily-note", dayKey: "2026-04-07")
        try writer.finishRun(id: failed, status: "failed")

        let second = try writer.startRun(runType: "daily-note", dayKey: "2026-04-08")
        try writer.finishRun(id: second, status: "succeeded")

        XCTAssertEqual(try writer.fetchLatestSuccessfulRunDay(runType: "daily-note"), "2026-04-08")
    }

    func testTodoItemsPersistAndFetchOpenBeforeCompleted() throws {
        let writer = try DatabaseWriter.inMemory()
        let openEventID = UUID()
        let doneEventID = UUID()
        let open = try writer.createTodo(
            title: "Send the investor recap",
            sourceDayKey: "2026-05-27",
            sourceEventIDs: [openEventID],
            createdAt: Date(timeIntervalSince1970: 1_778_000_000),
            promotionKind: .auto
        )
        let completed = try writer.createTodo(
            title: "Confirm Friday meeting time",
            sourceDayKey: "2026-05-27",
            sourceEventIDs: [doneEventID],
            createdAt: Date(timeIntervalSince1970: 1_778_000_100),
            promotionKind: .manual
        )

        try writer.completeTodo(
            id: completed.id,
            completedAt: Date(timeIntervalSince1970: 1_778_000_200),
            completionKind: .manual,
            evidenceEventIDs: []
        )

        let items = try writer.fetchTodoItems()

        XCTAssertEqual(items.map(\.id), [open.id, completed.id])
        XCTAssertEqual(items.map(\.status), [.open, .completed])
        XCTAssertEqual(items.first?.sourceEventIDs, [openEventID])
        XCTAssertEqual(items.last?.completedAt, Date(timeIntervalSince1970: 1_778_000_200))
        XCTAssertEqual(items.last?.completionKind, .manual)
    }

    func testTodoCreationMergesDuplicateNormalizedTitles() throws {
        let writer = try DatabaseWriter.inMemory()
        let firstEventID = UUID()
        let secondEventID = UUID()

        let first = try writer.createTodo(
            title: "Send the investor recap",
            sourceDayKey: "2026-05-27",
            sourceEventIDs: [firstEventID],
            createdAt: Date(timeIntervalSince1970: 1_778_000_000),
            promotionKind: .auto
        )
        let duplicate = try writer.createTodo(
            title: "  send the investor recap.  ",
            sourceDayKey: "2026-05-28",
            sourceEventIDs: [secondEventID],
            createdAt: Date(timeIntervalSince1970: 1_778_000_300),
            promotionKind: .manual
        )

        let items = try writer.fetchTodoItems()

        XCTAssertEqual(first.id, duplicate.id)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.title, "Send the investor recap")
        XCTAssertEqual(Set(items.first?.sourceEventIDs ?? []), Set([firstEventID, secondEventID]))
        XCTAssertEqual(items.first?.promotionKind, .auto)
    }

    func testTodoEvidenceCompletionRecordsEvidenceAndKeepsCompletedAtBottom() throws {
        let writer = try DatabaseWriter.inMemory()
        let sourceEventID = UUID()
        let evidenceEventID = UUID()
        let todo = try writer.createTodo(
            title: "Submit the launch checklist",
            sourceDayKey: "2026-05-27",
            sourceEventIDs: [sourceEventID],
            createdAt: Date(timeIntervalSince1970: 1_778_000_000),
            promotionKind: .auto
        )

        try writer.completeTodo(
            id: todo.id,
            completedAt: Date(timeIntervalSince1970: 1_778_000_500),
            completionKind: .evidenceSweep,
            evidenceEventIDs: [evidenceEventID]
        )

        let item = try XCTUnwrap(writer.fetchTodoItems().first)

        XCTAssertEqual(item.status, .completed)
        XCTAssertEqual(item.completedAt, Date(timeIntervalSince1970: 1_778_000_500))
        XCTAssertEqual(item.completionKind, .evidenceSweep)
        XCTAssertEqual(item.completionEvidenceEventIDs, [evidenceEventID])
    }

    func testTodoTitleUpdateRewritesTitleAndNormalizedTitle() throws {
        let writer = try DatabaseWriter.inMemory()
        let todo = try writer.createTodo(
            title: "Send the investor recap",
            sourceDayKey: "2026-05-28",
            sourceEventIDs: [],
            createdAt: Date(timeIntervalSince1970: 1_778_000_000),
            promotionKind: .manual
        )

        try writer.updateTodoTitle(id: todo.id, title: "  Send the updated investor recap.  ")

        let item = try XCTUnwrap(writer.fetchTodoItems().first)

        XCTAssertEqual(item.title, "Send the updated investor recap.")
        XCTAssertEqual(item.normalizedTitle, "send the updated investor recap")
    }

    func testTodoTitleUpdateRejectsEmptyAndDuplicateNormalizedTitle() throws {
        let writer = try DatabaseWriter.inMemory()
        let first = try writer.createTodo(
            title: "Send the investor recap",
            sourceDayKey: "2026-05-28",
            sourceEventIDs: [],
            createdAt: Date(timeIntervalSince1970: 1_778_000_000),
            promotionKind: .manual
        )
        _ = try writer.createTodo(
            title: "Confirm Friday meeting time",
            sourceDayKey: "2026-05-28",
            sourceEventIDs: [],
            createdAt: Date(timeIntervalSince1970: 1_778_000_100),
            promotionKind: .manual
        )

        XCTAssertThrowsError(try writer.updateTodoTitle(id: first.id, title: " "))
        XCTAssertThrowsError(try writer.updateTodoTitle(id: first.id, title: "confirm friday meeting time."))

        XCTAssertEqual(try writer.fetchTodoItems().map(\.title), [
            "Send the investor recap",
            "Confirm Friday meeting time",
        ])
    }

    func testTodoReopenClearsCompletionMetadataAndSortsWithOpenItems() throws {
        let writer = try DatabaseWriter.inMemory()
        let evidenceEventID = UUID()
        let todo = try writer.createTodo(
            title: "Send the investor recap",
            sourceDayKey: "2026-05-28",
            sourceEventIDs: [],
            createdAt: Date(timeIntervalSince1970: 1_778_000_000),
            promotionKind: .manual
        )
        let laterOpen = try writer.createTodo(
            title: "Confirm Friday meeting time",
            sourceDayKey: "2026-05-28",
            sourceEventIDs: [],
            createdAt: Date(timeIntervalSince1970: 1_778_000_100),
            promotionKind: .manual
        )
        try writer.completeTodo(
            id: todo.id,
            completedAt: Date(timeIntervalSince1970: 1_778_000_500),
            completionKind: .evidenceSweep,
            evidenceEventIDs: [evidenceEventID]
        )

        try writer.reopenTodo(id: todo.id)

        let items = try writer.fetchTodoItems()

        XCTAssertEqual(items.map(\.id), [todo.id, laterOpen.id])
        XCTAssertEqual(items.first?.status, .open)
        XCTAssertNil(items.first?.completedAt)
        XCTAssertNil(items.first?.completionKind)
        XCTAssertEqual(items.first?.completionEvidenceEventIDs, [])
    }

    func testTodoDeleteRemovesOnlyMatchingItem() throws {
        let writer = try DatabaseWriter.inMemory()
        let first = try writer.createTodo(
            title: "Send the investor recap",
            sourceDayKey: "2026-05-28",
            sourceEventIDs: [],
            createdAt: Date(timeIntervalSince1970: 1_778_000_000),
            promotionKind: .manual
        )
        _ = try writer.createTodo(
            title: "Confirm Friday meeting time",
            sourceDayKey: "2026-05-28",
            sourceEventIDs: [],
            createdAt: Date(timeIntervalSince1970: 1_778_000_100),
            promotionKind: .manual
        )

        try writer.deleteTodo(id: first.id)

        XCTAssertEqual(try writer.fetchTodoItems().map(\.title), ["Confirm Friday meeting time"])
    }

    func testNotificationCollectorIngestsSnapshot() throws {
        let writer = try DatabaseWriter.inMemory()
        let filter = PrivacyFilter()
        let collector = NotificationCollector(
            privacyFilter: filter,
            databaseWriter: writer,
            databaseReader: StubNotificationReader()
        )

        let deliveredAt = Date(timeIntervalSince1970: 1_775_000_000)
        let snapshot = NotificationSnapshot(
            appName: "Calendar",
            deliveredAt: deliveredAt,
            body: "Meeting in 10 minutes"
        )

        collector.ingest([snapshot])

        // dayKey is derived from local timezone so we compute it the same way
        let dayKey = ISO8601DayKey.format(deliveredAt)
        let events = try writer.fetchEvents(dayKey: dayKey)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.sourceType, .notification)
        XCTAssertEqual(events.first?.sourceApp, "Calendar")
    }

    func testNotificationCollectorKeepsDistinctSameDayNotificationsWithMatchingBody() throws {
        let writer = try DatabaseWriter.inMemory()
        let collector = NotificationCollector(
            privacyFilter: PrivacyFilter(),
            databaseWriter: writer,
            databaseReader: StubNotificationReader()
        )

        let firstDeliveredAt = Date(timeIntervalSince1970: 1_776_000_000)
        let secondDeliveredAt = Date(timeIntervalSince1970: 1_776_000_060)
        let snapshots = [
            NotificationSnapshot(
                appName: "Calendar",
                deliveredAt: firstDeliveredAt,
                body: "Standup in 5"
            ),
            NotificationSnapshot(
                appName: "Calendar",
                deliveredAt: secondDeliveredAt,
                body: "Standup in 5"
            ),
        ]

        XCTAssertEqual(collector.ingest(snapshots), 2)

        let events = try writer.fetchEvents(dayKey: ISO8601DayKey.format(firstDeliveredAt))
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(
            events.map(\.capturedAt),
            [firstDeliveredAt, secondDeliveredAt]
        )
    }

    func testNotificationCollectorDedupesRescannedNotificationWithSameDeliveredAt() throws {
        let writer = try DatabaseWriter.inMemory()
        let collector = NotificationCollector(
            privacyFilter: PrivacyFilter(),
            databaseWriter: writer,
            databaseReader: StubNotificationReader()
        )

        let deliveredAt = Date(timeIntervalSince1970: 1_776_100_000)
        let snapshot = NotificationSnapshot(
            appName: "Calendar",
            deliveredAt: deliveredAt,
            body: "Standup in 5"
        )

        XCTAssertEqual(collector.ingest([snapshot]), 1)
        XCTAssertEqual(collector.ingest([snapshot]), 1)

        let events = try writer.fetchEvents(dayKey: ISO8601DayKey.format(deliveredAt))
        XCTAssertEqual(events.count, 1)
    }

    func testClipboardHashesIncludeDayKeySoCrossDayCopiesPersistSeparately() {
        let first = ClipboardWatcher.contentHash(for: "same payload", dayKey: "2026-04-07")
        let second = ClipboardWatcher.contentHash(for: "same payload", dayKey: "2026-04-08")

        XCTAssertNotEqual(first, second)
    }

    func testNotificationCollectorCountsOnlySuccessfulInserts() {
        let collector = NotificationCollector(
            privacyFilter: PrivacyFilter(),
            databaseWriter: FailingEventWriter(),
            databaseReader: StubNotificationReader()
        )

        let count = collector.ingest([
            NotificationSnapshot(
                appName: "Calendar",
                deliveredAt: Date(timeIntervalSince1970: 1_775_000_000),
                body: "Meeting in 10 minutes"
            )
        ])

        XCTAssertEqual(count, 0)
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
