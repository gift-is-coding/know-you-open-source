import XCTest
@testable import KnowYou

final class DatabaseWriterTests: XCTestCase {
    func testInsertFilteredEventPersistsPrivacyAction() throws {
        let writer = try DatabaseWriter.inMemory()
        let event = EventRecord(
            id: UUID(),
            sourceType: .clipboard,
            sourceApp: "Taio",
            capturedAt: Date(timeIntervalSince1970: 1_775_000_000),
            dayKey: "2026-04-07",
            text: "Draft message",
            auditText: nil,
            privacyAction: .keep,
            contentHash: "hash-1"
        )

        try writer.insert(event)

        let rows = try writer.fetchEvents(dayKey: "2026-04-07")
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.privacyAction, .keep)
    }
}
