import XCTest
@testable import KnowYou

@MainActor
final class MainWindowViewModelTests: XCTestCase {
    func testSelectingDateLoadsMatchingMarkdownPath() {
        let appState = AppState()
        appState.availableDates = ["2026-04-07", "2026-04-06"]
        appState.noteIndex = [
            "2026-04-07": URL(fileURLWithPath: "/tmp/2026-04-07.md"),
            "2026-04-06": URL(fileURLWithPath: "/tmp/2026-04-06.md"),
        ]

        appState.selectDate("2026-04-06")

        XCTAssertEqual(appState.selectedDate, "2026-04-06")
        XCTAssertEqual(appState.selectedMarkdownURL?.path, "/tmp/2026-04-06.md")
    }

    func testSelectingDateWithoutIndexedFileClearsMarkdownPath() {
        let appState = AppState()
        appState.selectedMarkdownURL = URL(fileURLWithPath: "/tmp/existing.md")

        appState.selectDate("2026-04-08")

        XCTAssertEqual(appState.selectedDate, "2026-04-08")
        XCTAssertNil(appState.selectedMarkdownURL)
    }

    func testStatusMessageCanReflectMissingSummary() {
        let appState = AppState()
        appState.statusMessage = "Summary pending for 2026-04-07"

        XCTAssertEqual(appState.statusMessage, "Summary pending for 2026-04-07")
    }

    func testAutomationStatusTextReflectsBackfillDays() {
        let appState = AppState()
        appState.lastImportedNotificationCount = 3
        appState.pendingBackfillDays = ["2026-04-06", "2026-04-07"]

        XCTAssertTrue(appState.automationStatusText.contains("Notifications: 3"))
        XCTAssertTrue(appState.automationStatusText.contains("2026-04-06"))
        XCTAssertTrue(appState.automationStatusText.contains("2026-04-07"))
    }
}
