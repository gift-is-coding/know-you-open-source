import XCTest
@testable import KnowYou

@MainActor
final class ManualDiaryRefreshTests: XCTestCase {
    func testRefreshesApril8AndApril9IntoRealVault() async throws {
        guard ProcessInfo.processInfo.environment["KNOWYOU_REAL_REFRESH"] == "1" else {
            throw XCTSkip("Set KNOWYOU_REAL_REFRESH=1 to run this manual refresh test.")
        }

        let apiKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        XCTAssertFalse(apiKey.isEmpty, "OPENAI_API_KEY must be set for manual diary refresh.")

        let databasePath = NSHomeDirectory() + "/Library/Application Support/KnowYou/events.sqlite"
        let vaultURL = URL(
            fileURLWithPath: NSHomeDirectory() + "/Library/Application Support/KnowYou/Vault",
            isDirectory: true
        )
        let environment = try AppEnvironment(
            databasePath: databasePath,
            vaultURL: vaultURL,
            summarizer: CloudSummarizer(apiKey: apiKey)
        )
        let appState = AppState(environment: environment)

        for dayKey in ["2026-04-08", "2026-04-09"] {
            await appState.generateDailyNote(for: dayKey)

            let markdownURL = vaultURL.appending(path: "\(dayKey).md")
            let storyURL = vaultURL.appending(path: "\(dayKey).story.json")
            XCTAssertTrue(FileManager.default.fileExists(atPath: markdownURL.path), "Missing markdown for \(dayKey)")
            XCTAssertTrue(FileManager.default.fileExists(atPath: storyURL.path), "Missing story JSON for \(dayKey)")

            let markdown = try String(contentsOf: markdownURL, encoding: .utf8)
            XCTAssertTrue(markdown.contains("# 你今天做得很棒"), markdown)
            XCTAssertTrue(markdown.contains("# 今日总结"), markdown)
            XCTAssertTrue(markdown.contains("# 详情"), markdown)
            XCTAssertTrue(markdown.contains("# 待办事项"), markdown)
            XCTAssertFalse(markdown.contains("# 今日节奏"), markdown)
            XCTAssertFalse(markdown.localizedCaseInsensitiveContains("The day mostly revolved around"), markdown)
        }
    }
}
