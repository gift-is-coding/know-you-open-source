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

    func testResolvePipelineDoesNotFallBackToDevelopmentSourceWhenBundledRunnerIsInvalid() {
        let error = MyWikiPipelineBridgeError.pipelineExecutionFailed(
            "Bundled MyWiki runner script is missing."
        )

        let target = MyWikiPipelineBridge.resolveTarget(
            bundledRunner: .failure(error),
            developmentSourceURL: URL(fileURLWithPath: "/tmp/ThirdParty/llm_wiki")
        )

        XCTAssertEqual(target, .invalidBundledRunner("Bundled MyWiki runner script is missing."))
        XCTAssertEqual(target.statusDescription, "Bundled MyWiki runner script is missing.")
    }

    func testRunIngestDoesNotMaterializeLocalFallbackWhenHeadlessRunnerIsUnavailable() async throws {
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

        do {
            try await MyWikiPipelineBridge().runIngest(target: .developmentSource(dev), projectRoot: root)
            XCTFail("Expected pipelineExecutionFailed.")
        } catch {
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

    func testRunIngestInvokesDevelopmentHeadlessRunner() async throws {
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

        try await MyWikiPipelineBridge(
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

    func testBundledRunnerInvocationUsesNodeAndScriptWithoutAPISecret() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        let runnerRoot = root.appending(path: "MyWikiRunner", directoryHint: .isDirectory)
        try makeValidBundledRunner(at: runnerRoot)
        let bundle = try MyWikiRunnerBundle(rootURL: runnerRoot)
        let manifestURL = root.appending(path: ".knowyou/ingest-manifest.json")
        let process = RecordingMyWikiRunnerProcess(
            events: [
                #"{"type":"runner.done","status":"succeeded","filesWritten":["wiki/sources/2026-06-04.md"]}"#
            ],
            result: MyWikiPipelineProcessResult(stdout: "", stderr: "", terminationStatus: 0)
        )
        let bridge = MyWikiPipelineBridge(
            runnerProcess: process,
            npmInvocation: .environmentNPM,
            llmInvocation: MyWikiLLMInvocation(
                arguments: [
                    "--provider",
                    "custom",
                    "--model",
                    "deepseek-v4-pro",
                    "--custom-endpoint",
                    "https://api.deepseek.com",
                    "--cli-path",
                    "/usr/local/bin/codex"
                ],
                environment: ["KNOWYOU_MYWIKI_LLM_API_KEY": "sk-secret"]
            ),
            llmBridge: MyWikiLLMBridge(engine: PipelineStubMyWikiLLMEngine(result: "ok"))
        )

        try await bridge.runIngest(
            target: .bundledRunner(bundle),
            projectRoot: root,
            manifestURL: manifestURL
        )

        let call = try XCTUnwrap(process.calls.first)
        XCTAssertEqual(call.executable, bundle.nodeURL.path)
        XCTAssertEqual(
            call.arguments,
            [
                bundle.scriptURL.path,
                "--project",
                root.path,
                "--provider",
                "knowyou-bridge",
                "--max-sources",
                "3",
                "--manifest",
                manifestURL.path
            ]
        )
        XCTAssertEqual(call.workingDirectory, bundle.rootURL)
        XCTAssertEqual(call.environment, [:])

        let argumentText = call.arguments.joined(separator: " ")
        XCTAssertFalse(argumentText.contains("sk-secret"))
        XCTAssertFalse(argumentText.contains("deepseek-v4-pro"))
        XCTAssertFalse(argumentText.contains("https://api.deepseek.com"))
        XCTAssertFalse(argumentText.contains("/usr/local/bin/codex"))
        XCTAssertFalse(call.environment.values.contains("sk-secret"))
        XCTAssertFalse(call.environment.values.contains("deepseek-v4-pro"))
        XCTAssertFalse(call.environment.values.contains("https://api.deepseek.com"))
        XCTAssertFalse(call.environment.values.contains("/usr/local/bin/codex"))
    }

    func testBundledRunnerAnswersJSONLLMRequestUsingInjectedDiaryEngine() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        let runnerRoot = root.appending(path: "MyWikiRunner", directoryHint: .isDirectory)
        try makeValidBundledRunner(at: runnerRoot)
        let bundle = try MyWikiRunnerBundle(rootURL: runnerRoot)
        let requestJSONL = """
        {"type":"llm.request","id":"req-bridge","messages":[{"role":"system","content":"Extract ontology."},{"role":"user","content":"Diary text"}],"temperature":0.2}
        """
        let process = RecordingMyWikiRunnerProcess(
            events: [
                requestJSONL,
                #"{"type":"runner.done","status":"succeeded"}"#
            ],
            result: MyWikiPipelineProcessResult(stdout: "", stderr: "", terminationStatus: 0)
        )
        let engine = PipelineStubMyWikiLLMEngine(result: "Bridge completion")
        let bridge = MyWikiPipelineBridge(
            runnerProcess: process,
            llmBridge: MyWikiLLMBridge(engine: engine)
        )

        try await bridge.runIngest(target: .bundledRunner(bundle), projectRoot: root)

        XCTAssertEqual(process.responses.count, 1)
        let responseData = Data(process.responses[0].utf8)
        XCTAssertEqual(
            try JSONDecoder().decode(MyWikiBridgeEnvelope.self, from: responseData),
            .llmResponse(MyWikiLLMResponse(id: "req-bridge", content: "Bridge completion"))
        )
        let requests = await engine.recordedRequests()
        XCTAssertEqual(
            requests,
            [
                PipelineStubMyWikiLLMEngine.Request(
                    messages: [
                        MyWikiLLMMessage(role: "system", content: "Extract ontology."),
                        MyWikiLLMMessage(role: "user", content: "Diary text")
                    ],
                    temperature: 0.2
                )
            ]
        )
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

    func testRunIngestUsesResolvedAbsoluteNPMExecutable() async throws {
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

        try await MyWikiPipelineBridge(
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

    func testRunIngestPassesConfiguredLLMInvocationToDevelopmentRunner() async throws {
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

        try await MyWikiPipelineBridge(
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

    func testRunIngestInstallsDevelopmentDependenciesWhenViteIsMissing() async throws {
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

        try await MyWikiPipelineBridge(
            processRunner: runner,
            npmInvocation: .environmentNPM
        ).runIngest(target: .developmentSource(dev), projectRoot: root)

        XCTAssertEqual(runner.calls.count, 2)
        XCTAssertEqual(runner.calls[0].arguments, ["npm", "install"])
        XCTAssertEqual(runner.calls[0].workingDirectory, dev)
        XCTAssertEqual(Array(runner.calls[1].arguments.prefix(3)), ["npm", "run", "knowyou:ingest"])
    }

    func testRunIngestPassesManifestToDevelopmentHeadlessRunner() async throws {
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

        try await MyWikiPipelineBridge(
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

    func testRunIngestWritesFailureStatusWhenDevelopmentRunnerFails() async throws {
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

        do {
            try await MyWikiPipelineBridge(
                processRunner: runner,
                npmInvocation: .environmentNPM
            ).runIngest(target: .developmentSource(dev), projectRoot: root)
            XCTFail("Expected pipelineExecutionFailed.")
        } catch {
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

    func testRunIngestWritesFailureStatusWithoutLocalFallbackWhenPipelineIsMissing() async throws {
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

        do {
            try await MyWikiPipelineBridge().runIngest(target: .missing, projectRoot: root)
            XCTFail("Expected missingPipeline.")
        } catch {
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

private final class RecordingMyWikiPipelineRunner: MyWikiPipelineProcessRunning, @unchecked Sendable {
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

private final class RecordingMyWikiRunnerProcess: MyWikiRunnerProcessRunning, @unchecked Sendable {
    struct Call: Equatable {
        let executable: String
        let arguments: [String]
        let workingDirectory: URL
        let environment: [String: String]
        let timeoutSeconds: TimeInterval
    }

    private let events: [String]
    private let result: MyWikiPipelineProcessResult
    private let lock = NSLock()
    private var recordedCalls: [Call] = []
    private var recordedResponses: [String] = []

    var calls: [Call] {
        lock.withLock { recordedCalls }
    }

    var responses: [String] {
        lock.withLock { recordedResponses }
    }

    init(events: [String], result: MyWikiPipelineProcessResult) {
        self.events = events
        self.result = result
    }

    func run(
        executable: String,
        arguments: [String],
        workingDirectory: URL,
        environment: [String: String],
        timeoutSeconds: TimeInterval,
        onEvent: @escaping @Sendable (String) async throws -> String?
    ) async throws -> MyWikiPipelineProcessResult {
        lock.withLock {
            recordedCalls.append(
                Call(
                    executable: executable,
                    arguments: arguments,
                    workingDirectory: workingDirectory,
                    environment: environment,
                    timeoutSeconds: timeoutSeconds
                )
            )
        }

        for event in events {
            if let response = try await onEvent(event) {
                lock.withLock {
                    recordedResponses.append(response)
                }
            }
        }

        let stdout = result.stdout.isEmpty ? events.joined(separator: "\n") : result.stdout
        return MyWikiPipelineProcessResult(
            stdout: stdout,
            stderr: result.stderr,
            terminationStatus: result.terminationStatus
        )
    }
}

private actor PipelineStubMyWikiLLMEngine: MyWikiLLMCompleting {
    struct Request: Equatable {
        let messages: [MyWikiLLMMessage]
        let temperature: Double?
    }

    private let result: String
    private var requests: [Request] = []

    init(result: String) {
        self.result = result
    }

    func complete(messages: [MyWikiLLMMessage], temperature: Double?) async throws -> String {
        requests.append(Request(messages: messages, temperature: temperature))
        return result
    }

    func recordedRequests() -> [Request] {
        requests
    }
}
