import XCTest
@testable import KnowYou

@MainActor
final class ManualDiaryRefreshTests: XCTestCase {
    private let sentinelPath = "/tmp/knowyou-real-refresh-enabled"

    private func shouldRunRealRefresh() -> Bool {
        let environmentFlag = ProcessInfo.processInfo.environment["KNOWYOU_REAL_REFRESH"] == "1"
        let sentinelExists = FileManager.default.fileExists(atPath: sentinelPath)
        return environmentFlag || sentinelExists
    }

    private final class RefreshLog {
        var entries: [String] = []

        @MainActor
        func record(_ job: DayRefreshJob) {
            let detail = job.detail ?? job.stage.detail
            entries.append("[\(job.dayKey)] \(job.stage): \(detail)")
        }
    }

    func testRefreshesApril8AndApril9IntoRealVault() async throws {
        guard shouldRunRealRefresh() else {
            throw XCTSkip("Set KNOWYOU_REAL_REFRESH=1 or create /tmp/knowyou-real-refresh-enabled to run this manual refresh test.")
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

    func testRefreshesApril11ThroughRealRefreshPathIntoRealVault() async throws {
        guard shouldRunRealRefresh() else {
            throw XCTSkip("Set KNOWYOU_REAL_REFRESH=1 or create /tmp/knowyou-real-refresh-enabled to run this manual refresh test.")
        }

        let dayKey = "2026-04-11"
        let databasePath = NSHomeDirectory() + "/Library/Application Support/KnowYou/events.sqlite"
        let vaultURL = URL(
            fileURLWithPath: NSHomeDirectory() + "/Library/Application Support/KnowYou/Vault",
            isDirectory: true
        )
        let markdownURL = vaultURL.appending(path: "\(dayKey).md")
        let storyURL = vaultURL.appending(path: "\(dayKey).story.json")
        let originalMarkdown = try String(contentsOf: markdownURL, encoding: .utf8)
        let originalStoryData = try Data(contentsOf: storyURL)
        let originalStory = try JSONDecoder().decode(DailyStory.self, from: originalStoryData)
        XCTAssertEqual(originalStory.provenance?.generationMode, .fallback, "Expected \(dayKey) to start in fallback mode for this recovery test.")

        let config = SummarizerConfig.load()
        let environment = try AppEnvironment(
            databasePath: databasePath,
            vaultURL: vaultURL
        )
        let refreshLog = RefreshLog()
        let appState = AppState(
            environment: environment,
            bootstrapServices: false,
            summarizerConfig: config,
            onRefreshStageChange: { @MainActor @Sendable job in
                refreshLog.record(job)
            }
        )
        let processPath = ProcessInfo.processInfo.environment["PATH"] ?? ""

        let resolvedPaths = [
            DiaryEngine.codexCLI: SummarizerConfig.resolvedExecutablePath(
                configuredPath: config.codexCLIPath,
                commandName: "codex",
                environment: ProcessInfo.processInfo.environment
            ),
            DiaryEngine.claudeCLI: SummarizerConfig.resolvedExecutablePath(
                configuredPath: config.claudeCLIPath,
                commandName: "claude",
                environment: ProcessInfo.processInfo.environment
            ),
            DiaryEngine.geminiCLI: SummarizerConfig.resolvedExecutablePath(
                configuredPath: config.geminiCLIPath,
                commandName: "gemini",
                environment: ProcessInfo.processInfo.environment
            ),
            DiaryEngine.openclawCLI: SummarizerConfig.resolvedExecutablePath(
                configuredPath: config.openclawCLIPath,
                commandName: "openclaw",
                environment: ProcessInfo.processInfo.environment
            ),
        ]
        for (engine, path) in resolvedPaths {
            appState.engineStatuses[engine] = EngineRuntimeStatus(
                state: path == nil ? .gray : .green,
                detail: path == nil ? "Executable not found." : "Resolved for manual refresh test.",
                lastVerifiedAt: path == nil ? nil : Date(),
                configurationSignature: path ?? ""
            )
        }
        let engineSummary = DiaryEngine.allCases
            .map { engine in
                let status = appState.engineStatuses[engine] ?? EngineRuntimeStatus()
                return "\(engine.rawValue)=\(String(describing: status.state)):\(status.detail)"
            }
            .joined(separator: " | ")
        let resolvedPathSummary = [
            "codex=\(resolvedPaths[.codexCLI].flatMap { $0 } ?? "<nil>")",
            "claude=\(resolvedPaths[.claudeCLI].flatMap { $0 } ?? "<nil>")",
            "gemini=\(resolvedPaths[.geminiCLI].flatMap { $0 } ?? "<nil>")",
            "openclaw=\(resolvedPaths[.openclawCLI].flatMap { $0 } ?? "<nil>")",
        ].joined(separator: " | ")
        try? """
        phase=before-refresh
        defaultEngine=\(appState.defaultEngine.rawValue)
        hasSummarizer=\(environment.summarizer != nil)
        PATH=\(processPath)
        configuredCodexPath=\(config.codexCLIPath)
        configuredClaudePath=\(config.claudeCLIPath)
        configuredGeminiPath=\(config.geminiCLIPath)
        configuredOpenclawPath=\(config.openclawCLIPath)
        resolvedPaths=\(resolvedPathSummary)
        engineSummary=\(engineSummary)
        """.write(to: URL(fileURLWithPath: "/tmp/knowyou-real-refresh-debug.txt"), atomically: true, encoding: .utf8)

        appState.selectDate(dayKey)
        XCTAssertEqual(appState.selectedDate, dayKey)
        let now = DateComponents(
            calendar: Calendar(identifier: .gregorian),
            year: 2026,
            month: 4,
            day: 11,
            hour: 23,
            minute: 59
        ).date ?? Date()

        await appState.refreshSelectedDay(now: now)

        let refreshJob: DayRefreshJob = try XCTUnwrap(
            appState.refreshJob(for: dayKey),
            "Missing refresh job for \(dayKey)"
        )
        try? """
        phase=after-refresh
        defaultEngine=\(appState.defaultEngine.rawValue)
        hasSummarizer=\(environment.summarizer != nil)
        statusMessage=\(appState.statusMessage ?? "<none>")
        refreshStage=\(String(describing: refreshJob.stage))
        refreshDetail=\(refreshJob.detail ?? "<none>")
        refreshError=\(refreshJob.error ?? "<none>")
        refreshLog=\(refreshLog.entries.joined(separator: " || "))
        """.write(to: URL(fileURLWithPath: "/tmp/knowyou-real-refresh-debug-after.txt"), atomically: true, encoding: .utf8)

        if refreshJob.stage != DayRefreshStage.completed {
            let currentMarkdown = try String(contentsOf: markdownURL, encoding: .utf8)
            let currentStoryData = try Data(contentsOf: storyURL)
            XCTAssertEqual(currentMarkdown, originalMarkdown, "Failed real refresh must not modify markdown.")
            XCTAssertEqual(currentStoryData, originalStoryData, "Failed real refresh must not modify story JSON.")
        }

        XCTAssertEqual(
            refreshJob.stage,
            DayRefreshStage.completed,
            "Real \(dayKey) refresh failed. Detail: \(refreshJob.detail ?? "<none>"), error: \(refreshJob.error ?? "<none>"), status: \(appState.statusMessage ?? "<none>"), engines: \(engineSummary)"
        )

        let refreshedStoryData = try Data(contentsOf: storyURL)
        let refreshedStory = try JSONDecoder().decode(DailyStory.self, from: refreshedStoryData)
        XCTAssertEqual(refreshedStory.provenance?.generationMode, .model, "Expected \(dayKey) to be upgraded from fallback to model after successful recovery.")
        XCTAssertFalse(refreshedStory.sections.flatMap(\.paragraphs).isEmpty)
        XCTAssertNotEqual(refreshedStoryData, originalStoryData, "Successful real refresh should update story JSON.")
    }
}
