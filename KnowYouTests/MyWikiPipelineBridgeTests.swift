import XCTest
@testable import KnowYou

final class MyWikiPipelineBridgeTests: XCTestCase {
    func testResolvePipelineUsesDevelopmentSourceWhenHelperMissing() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        let dev = root.appending(path: "ThirdParty/llm_wiki", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dev, withIntermediateDirectories: true)

        let target = MyWikiPipelineBridge.resolveTarget(
            bundledHelperAppURL: nil,
            developmentSourceURL: dev
        )

        XCTAssertEqual(target.statusDescription, "Using development llm_wiki pipeline: \(dev.path)")
    }

    func testRunIngestDoesNotMaterializeLocalFallbackWhenHeadlessRunnerIsUnavailable() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        let rawSources = root.appending(path: "raw/sources", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: rawSources, withIntermediateDirectories: true)
        try """
        # 2026-05-13

        KnowYou 的 My Wiki 需要更轻量，先展示总结和搜索。
        Codex agent 后续需要读取这些背景。
        """.write(
            to: rawSources.appending(path: "knowyou-diary-2026-05-13.md"),
            atomically: true,
            encoding: .utf8
        )

        let dev = root.appending(path: "ThirdParty/llm_wiki", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dev, withIntermediateDirectories: true)

        XCTAssertThrowsError(try MyWikiPipelineBridge().runIngest(target: .developmentSource(dev), projectRoot: root)) { error in
            guard case MyWikiPipelineBridgeError.pipelineExecutionFailed = error else {
                XCTFail("Expected pipelineExecutionFailed, got \(error)")
                return
            }
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appending(path: ".llm-wiki").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appending(path: "wiki/summaries/recent-diary-summary.md").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appending(path: "wiki/projects/knowyou.md").path))

        let statusURL = root.appending(path: ".llm-wiki/last-ingest-status.json")
        let statusText = try String(contentsOf: statusURL, encoding: .utf8)
        XCTAssertTrue(statusText.contains(#""status":"failed""#), statusText)
        XCTAssertTrue(statusText.contains("headless llm_wiki runner is not available"), statusText)
    }

    func testRunIngestInvokesDevelopmentHeadlessRunner() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        let rawSources = root.appending(path: "raw/sources", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: rawSources, withIntermediateDirectories: true)
        try "# 2026-05-14\n\nMet Huang Shan.".write(
            to: rawSources.appending(path: "knowyou-diary-2026-05-14.md"),
            atomically: true,
            encoding: .utf8
        )

        let dev = root.appending(path: "ThirdParty/llm_wiki", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dev, withIntermediateDirectories: true)
        try #"{"scripts":{"knowyou:ingest":"node scripts/knowyou-ingest-runner.mjs"}}"#.write(
            to: dev.appending(path: "package.json"),
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.createDirectory(
            at: dev.appending(path: "node_modules/vite", directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )

        let runner = RecordingMyWikiPipelineRunner(
            result: MyWikiPipelineProcessResult(
                stdout: #"{"status":"succeeded","sourcesProcessed":1}"#,
                stderr: "",
                terminationStatus: 0
            )
        )

        try MyWikiPipelineBridge(processRunner: runner).runIngest(target: .developmentSource(dev), projectRoot: root)

        XCTAssertEqual(runner.calls.count, 1)
        XCTAssertEqual(runner.calls[0].executable, "/usr/bin/env")
        XCTAssertEqual(runner.calls[0].workingDirectory, dev)
        XCTAssertEqual(
            runner.calls[0].arguments,
            [
                "npm",
                "run",
                "knowyou:ingest",
                "--",
                "--project",
                root.path,
                "--provider",
                "codex-cli",
                "--model",
                "gpt-5.5",
                "--max-sources",
                "3"
            ]
        )
        XCTAssertFalse(runner.calls[0].arguments.contains("--manifest"))

        let statusText = try String(contentsOf: root.appending(path: ".llm-wiki/last-ingest-status.json"), encoding: .utf8)
        XCTAssertTrue(statusText.contains(#""status":"succeeded""#), statusText)
    }

    func testRunIngestInstallsDevelopmentDependenciesWhenViteIsMissing() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        let dev = root.appending(path: "ThirdParty/llm_wiki", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dev, withIntermediateDirectories: true)
        try #"{"scripts":{"knowyou:ingest":"node scripts/knowyou-ingest-runner.mjs"}}"#.write(
            to: dev.appending(path: "package.json"),
            atomically: true,
            encoding: .utf8
        )

        let runner = RecordingMyWikiPipelineRunner(
            result: MyWikiPipelineProcessResult(
                stdout: #"{"status":"succeeded","sourcesProcessed":1}"#,
                stderr: "",
                terminationStatus: 0
            )
        )

        try MyWikiPipelineBridge(processRunner: runner).runIngest(target: .developmentSource(dev), projectRoot: root)

        XCTAssertEqual(runner.calls.count, 2)
        XCTAssertEqual(runner.calls[0].arguments, ["npm", "install"])
        XCTAssertEqual(runner.calls[0].workingDirectory, dev)
        XCTAssertEqual(Array(runner.calls[1].arguments.prefix(3)), ["npm", "run", "knowyou:ingest"])
    }

    func testRunIngestPassesManifestToDevelopmentHeadlessRunner() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        let dev = root.appending(path: "ThirdParty/llm_wiki", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dev, withIntermediateDirectories: true)
        try #"{"scripts":{"knowyou:ingest":"node scripts/knowyou-ingest-runner.mjs"}}"#.write(
            to: dev.appending(path: "package.json"),
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.createDirectory(
            at: dev.appending(path: "node_modules/vite", directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )

        let manifestURL = root.appending(path: "raw/source-selection-manifest.json")
        let runner = RecordingMyWikiPipelineRunner(
            result: MyWikiPipelineProcessResult(
                stdout: #"{"status":"succeeded","sourcesProcessed":1}"#,
                stderr: "",
                terminationStatus: 0
            )
        )

        try MyWikiPipelineBridge(processRunner: runner).runIngest(
            target: .developmentSource(dev),
            projectRoot: root,
            manifestURL: manifestURL
        )

        XCTAssertEqual(runner.calls.count, 1)
        XCTAssertEqual(
            runner.calls[0].arguments,
            [
                "npm",
                "run",
                "knowyou:ingest",
                "--",
                "--project",
                root.path,
                "--provider",
                "codex-cli",
                "--model",
                "gpt-5.5",
                "--max-sources",
                "3",
                "--manifest",
                manifestURL.path
            ]
        )
    }

    func testRunIngestWritesFailureStatusWhenDevelopmentRunnerFails() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        let dev = root.appending(path: "ThirdParty/llm_wiki", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dev, withIntermediateDirectories: true)
        try #"{"scripts":{"knowyou:ingest":"node scripts/knowyou-ingest-runner.mjs"}}"#.write(
            to: dev.appending(path: "package.json"),
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.createDirectory(
            at: dev.appending(path: "node_modules/vite", directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )

        let runner = RecordingMyWikiPipelineRunner(
            result: MyWikiPipelineProcessResult(
                stdout: "",
                stderr: "Codex CLI failed",
                terminationStatus: 1
            )
        )

        XCTAssertThrowsError(try MyWikiPipelineBridge(processRunner: runner).runIngest(target: .developmentSource(dev), projectRoot: root)) { error in
            guard case MyWikiPipelineBridgeError.pipelineExecutionFailed(let message) = error else {
                XCTFail("Expected pipelineExecutionFailed, got \(error)")
                return
            }
            XCTAssertTrue(message.contains("Codex CLI failed"), message)
        }

        let statusText = try String(contentsOf: root.appending(path: ".llm-wiki/last-ingest-status.json"), encoding: .utf8)
        XCTAssertTrue(statusText.contains(#""status":"failed""#), statusText)
        XCTAssertTrue(statusText.contains("Codex CLI failed"), statusText)
    }

    func testRunIngestWritesFailureStatusWithoutLocalFallbackWhenPipelineIsMissing() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        let rawSources = root.appending(path: "raw/sources", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: rawSources, withIntermediateDirectories: true)
        try """
        # 2026-05-13

        KnowYou needs My Wiki to show useful summaries and follow-ups even before the full pipeline is available.
        """.write(
            to: rawSources.appending(path: "knowyou-diary-2026-05-13.md"),
            atomically: true,
            encoding: .utf8
        )

        XCTAssertThrowsError(try MyWikiPipelineBridge().runIngest(target: .missing, projectRoot: root)) { error in
            guard case MyWikiPipelineBridgeError.missingPipeline = error else {
                XCTFail("Expected missingPipeline, got \(error)")
                return
            }
        }

        let summaryURL = root.appending(path: "wiki/summaries/recent-diary-summary.md")
        XCTAssertFalse(FileManager.default.fileExists(atPath: summaryURL.path))

        let statusURL = root.appending(path: ".llm-wiki/last-ingest-status.json")
        let statusText = try String(contentsOf: statusURL, encoding: .utf8)
        XCTAssertTrue(statusText.contains(#""status":"failed""#), statusText)
        XCTAssertTrue(statusText.contains("llm_wiki pipeline is not available"), statusText)
    }
}

private final class RecordingMyWikiPipelineRunner: MyWikiPipelineProcessRunning {
    struct Call: Equatable {
        let executable: String
        let arguments: [String]
        let workingDirectory: URL
        let timeoutSeconds: TimeInterval
    }

    private let result: MyWikiPipelineProcessResult
    private(set) var calls: [Call] = []

    init(result: MyWikiPipelineProcessResult) {
        self.result = result
    }

    func run(
        executable: String,
        arguments: [String],
        workingDirectory: URL,
        timeoutSeconds: TimeInterval
    ) throws -> MyWikiPipelineProcessResult {
        calls.append(
            Call(
                executable: executable,
                arguments: arguments,
                workingDirectory: workingDirectory,
                timeoutSeconds: timeoutSeconds
            )
        )
        return result
    }
}
