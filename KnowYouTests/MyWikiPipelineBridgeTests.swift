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
            bundledRunner: nil,
            developmentSourceURL: dev
        )

        XCTAssertEqual(target.statusDescription, "Using development llm_wiki pipeline: \(dev.path)")
    }

    func testResolvePipelineUsesBundledMyWikiRunnerAndIgnoresLLMWikiApp() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        let resources = root.appending(path: "Resources", directoryHint: .isDirectory)
        let runner = resources.appending(path: "MyWikiRunner", directoryHint: .isDirectory)
        let llmWikiApp = resources.appending(path: "KnowledgeOntology/LLM Wiki.app", directoryHint: .isDirectory)

        try FileManager.default.createDirectory(at: llmWikiApp, withIntermediateDirectories: true)
        try makeValidBundledRunner(at: runner)

        let bundle = try XCTUnwrap(
            MyWikiRunnerBundle.resolveDefault(resourceURL: resources)
        )
        let target = MyWikiPipelineBridge.resolveTarget(
            bundledRunner: bundle,
            developmentSourceURL: nil
        )

        XCTAssertEqual(target.statusDescription, "Using bundled MyWiki runner: \(runner.path)")
    }

    func testResolvePipelineDoesNotTreatLLMWikiAppAsValidRunner() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        let resources = root.appending(path: "Resources", directoryHint: .isDirectory)
        let llmWikiApp = resources.appending(path: "KnowledgeOntology/LLM Wiki.app", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: llmWikiApp, withIntermediateDirectories: true)

        XCTAssertNil(try MyWikiRunnerBundle.resolveDefault(resourceURL: resources))

        let target = MyWikiPipelineBridge.resolveTarget(
            bundledRunner: nil,
            developmentSourceURL: nil
        )

        XCTAssertEqual(target, .missing)
    }

    func testResolveDefaultThrowsWhenBundledRunnerNodeIsNotExecutable() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        let resources = root.appending(path: "Resources", directoryHint: .isDirectory)
        let runner = resources.appending(path: "MyWikiRunner", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: runner, withIntermediateDirectories: true)
        try "#!/usr/bin/env bash\n".write(
            to: runner.appending(path: "node"),
            atomically: true,
            encoding: .utf8
        )
        try "console.log('ok')\n".write(
            to: runner.appending(path: "mywiki-runner.js"),
            atomically: true,
            encoding: .utf8
        )

        XCTAssertThrowsError(try MyWikiRunnerBundle.resolveDefault(resourceURL: resources)) { error in
            guard case MyWikiPipelineBridgeError.pipelineExecutionFailed(let message) = error else {
                XCTFail("Expected pipelineExecutionFailed, got \(error)")
                return
            }
            XCTAssertEqual(message, "Bundled MyWiki runner node is missing or not executable.")
        }
    }

    func testResolveDefaultThrowsWhenBundledRunnerScriptIsMissing() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        let resources = root.appending(path: "Resources", directoryHint: .isDirectory)
        let runner = resources.appending(path: "MyWikiRunner", directoryHint: .isDirectory)
        let node = runner.appending(path: "node")
        try FileManager.default.createDirectory(at: runner, withIntermediateDirectories: true)
        try "#!/usr/bin/env bash\n".write(to: node, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: node.path)

        XCTAssertThrowsError(try MyWikiRunnerBundle.resolveDefault(resourceURL: resources)) { error in
            guard case MyWikiPipelineBridgeError.pipelineExecutionFailed(let message) = error else {
                XCTFail("Expected pipelineExecutionFailed, got \(error)")
                return
            }
            XCTAssertEqual(message, "Bundled MyWiki runner script is missing.")
        }
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

        try MyWikiPipelineBridge(
            processRunner: runner,
            npmInvocation: .environmentNPM
        ).runIngest(target: .developmentSource(dev), projectRoot: root)

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

    func testNPMResolverFindsNVMInstallWhenPathDoesNotContainNPM() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        let npmURL = root.appending(path: ".nvm/versions/node/v22.22.0/bin/npm")
        try FileManager.default.createDirectory(
            at: npmURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "#!/usr/bin/env bash\n".write(to: npmURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: npmURL.path)

        let resolver = MyWikiNPMResolver(
            environment: ["PATH": "/usr/bin:/bin"],
            homeDirectory: root
        )

        XCTAssertEqual(
            URL(fileURLWithPath: resolver.resolve().executable).standardizedFileURL.path,
            npmURL.standardizedFileURL.path
        )
        XCTAssertEqual(resolver.resolve().argumentPrefix, [])
    }

    func testRunIngestUsesResolvedAbsoluteNPMExecutable() throws {
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
                stdout: #"{"status":"succeeded","sourcesProcessed":1}"#,
                stderr: "",
                terminationStatus: 0
            )
        )
        let npmPath = root.appending(path: ".nvm/versions/node/v22.22.0/bin/npm").path

        try MyWikiPipelineBridge(
            processRunner: runner,
            npmInvocation: MyWikiProcessInvocation(executable: npmPath, argumentPrefix: [])
        ).runIngest(target: .developmentSource(dev), projectRoot: root)

        XCTAssertEqual(runner.calls.count, 1)
        XCTAssertEqual(runner.calls[0].executable, npmPath)
        XCTAssertEqual(Array(runner.calls[0].arguments.prefix(3)), ["run", "knowyou:ingest", "--"])
    }

    func testLLMInvocationUsesConfiguredOpenAICompatibleProviderWithoutCommandLineSecret() throws {
        var config = SummarizerConfig.default
        config.defaultEngine = .llmAPI
        config.activeLLMAPIProviderID = .deepSeek
        config.setLLMAPIProviderConfig(
            LLMAPIProviderConfig(
                id: .deepSeek,
                baseURL: "https://api.deepseek.com",
                model: "deepseek-v4-pro",
                wireFormat: .openAIChat,
                apiToken: "sk-secret"
            )
        )

        let invocation = try MyWikiLLMInvocation.resolve(from: config, environment: [:])

        XCTAssertEqual(
            invocation.arguments,
            [
                "--provider",
                "custom",
                "--model",
                "deepseek-v4-pro",
                "--custom-endpoint",
                "https://api.deepseek.com",
                "--api-mode",
                "chat_completions"
            ]
        )
        XCTAssertEqual(invocation.environment["KNOWYOU_MYWIKI_LLM_API_KEY"], "sk-secret")
        XCTAssertFalse(invocation.arguments.contains("sk-secret"))
    }

    func testRunIngestPassesConfiguredLLMInvocationToDevelopmentRunner() throws {
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
                stdout: #"{"status":"succeeded","sourcesProcessed":1}"#,
                stderr: "",
                terminationStatus: 0
            )
        )
        let invocation = MyWikiLLMInvocation(
            arguments: [
                "--provider",
                "custom",
                "--model",
                "deepseek-v4-pro",
                "--custom-endpoint",
                "https://api.deepseek.com",
                "--api-mode",
                "chat_completions"
            ],
            environment: ["KNOWYOU_MYWIKI_LLM_API_KEY": "sk-secret"]
        )

        try MyWikiPipelineBridge(
            processRunner: runner,
            npmInvocation: .environmentNPM,
            llmInvocation: invocation
        ).runIngest(target: .developmentSource(dev), projectRoot: root)

        XCTAssertEqual(runner.calls.count, 1)
        XCTAssertTrue(runner.calls[0].arguments.contains("--custom-endpoint"))
        XCTAssertTrue(runner.calls[0].arguments.contains("https://api.deepseek.com"))
        XCTAssertEqual(runner.calls[0].environment["KNOWYOU_MYWIKI_LLM_API_KEY"], "sk-secret")
        XCTAssertFalse(runner.calls[0].arguments.contains("sk-secret"))
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

        try MyWikiPipelineBridge(
            processRunner: runner,
            npmInvocation: .environmentNPM
        ).runIngest(target: .developmentSource(dev), projectRoot: root)

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

        try MyWikiPipelineBridge(
            processRunner: runner,
            npmInvocation: .environmentNPM
        ).runIngest(
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

        XCTAssertThrowsError(try MyWikiPipelineBridge(
            processRunner: runner,
            npmInvocation: .environmentNPM
        ).runIngest(target: .developmentSource(dev), projectRoot: root)) { error in
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
        XCTAssertTrue(statusText.contains("MyWiki runner is not available"), statusText)
    }
}

private func makeValidBundledRunner(at runner: URL) throws {
    let node = runner.appending(path: "node")
    let script = runner.appending(path: "mywiki-runner.js")
    try FileManager.default.createDirectory(at: runner, withIntermediateDirectories: true)
    try "#!/usr/bin/env bash\n".write(to: node, atomically: true, encoding: .utf8)
    try "console.log('ok')\n".write(to: script, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: node.path)
}

private final class RecordingMyWikiPipelineRunner: MyWikiPipelineProcessRunning {
    struct Call: Equatable {
        let executable: String
        let arguments: [String]
        let workingDirectory: URL
        let environment: [String: String]
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
        environment: [String: String],
        timeoutSeconds: TimeInterval
    ) throws -> MyWikiPipelineProcessResult {
        calls.append(
            Call(
                executable: executable,
                arguments: arguments,
                workingDirectory: workingDirectory,
                environment: environment,
                timeoutSeconds: timeoutSeconds
            )
        )
        return result
    }
}
