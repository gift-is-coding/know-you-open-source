import XCTest
@testable import KnowYou

final class MyWikiPipelineBridgeTests: XCTestCase {
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
            bundledRunner: bundle
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
            bundledRunner: nil
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
            bundledRunner: .failure(error)
        )

        XCTAssertEqual(target, .invalidBundledRunner("Bundled MyWiki runner script is missing."))
        XCTAssertEqual(target.statusDescription, "Bundled MyWiki runner script is missing.")
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

        let commandText = ([call.executable] + call.arguments + Array(call.environment.values)).joined(separator: " ")
        XCTAssertFalse(commandText.localizedCaseInsensitiveContains("npm"))
        XCTAssertFalse(commandText.localizedCaseInsensitiveContains("node_modules"))
    }

    func testBundledRunnerAnswersJSONLLMRequestUsingInjectedDiaryEngine() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        let runnerRoot = root.appending(path: "MyWikiRunner", directoryHint: .isDirectory)
        try makeValidBundledRunner(at: runnerRoot)
        let bundle = try MyWikiRunnerBundle(rootURL: runnerRoot)
        let requestJSONL = """
        {"type":"llm.request","id":"req-bridge","messages":[{"role":"system","content":"Extract ontology."},{"role":"user","content":"Diary text"}],"temperature":0.2,"max_tokens":8192,"reasoning":{"mode":"off"}}
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
                    options: LLMCompletionOptions(
                        temperature: 0.2,
                        maxTokens: 8192,
                        reasoning: LLMReasoningOptions(mode: "off", budgetTokens: nil)
                    )
                )
            ]
        )
    }

    func testBundledRunnerPreservesDetailedRunnerStatusOnSuccess() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        let runnerRoot = root.appending(path: "MyWikiRunner", directoryHint: .isDirectory)
        try makeValidBundledRunner(at: runnerRoot)
        let bundle = try MyWikiRunnerBundle(rootURL: runnerRoot)
        let statusRoot = root.appending(path: ".llm-wiki", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: statusRoot, withIntermediateDirectories: true)
        try """
        {
          "status": "succeeded",
          "message": "Ingested 3 source file(s) into My Wiki.",
          "updatedAt": "2026-06-08T12:06:34.576Z",
          "sourcesProcessed": 3,
          "sourcesTotal": 3,
          "filesWritten": ["wiki/entities/knowyou.md"]
        }
        """.write(
            to: statusRoot.appending(path: "last-ingest-status.json"),
            atomically: true,
            encoding: .utf8
        )
        let process = RecordingMyWikiRunnerProcess(
            events: [],
            result: MyWikiPipelineProcessResult(stdout: "", stderr: "", terminationStatus: 0)
        )

        try await MyWikiPipelineBridge(
            runnerProcess: process,
            llmBridge: MyWikiLLMBridge(engine: PipelineStubMyWikiLLMEngine(result: "ok"))
        ).runIngest(target: .bundledRunner(bundle), projectRoot: root)

        let statusText = try String(
            contentsOf: statusRoot.appending(path: "last-ingest-status.json"),
            encoding: .utf8
        )
        XCTAssertTrue(statusText.contains(#""sourcesProcessed": 3"#), statusText)
        XCTAssertTrue(statusText.contains(#""sourcesTotal": 3"#), statusText)
        XCTAssertTrue(statusText.contains("wiki/entities/knowyou.md"), statusText)
    }

    func testRunnerProcessControllerDoesNotTerminateUnlaunchedProcess() {
        let controller = MyWikiRunnerProcessController()
        let process = Process()

        controller.attach(process)
        controller.terminate()

        XCTAssertFalse(controller.shouldLaunch)
    }

    func testDefaultRunnerProcessIncludesRunnerOutputWhenBridgeEventFails() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let script = """
        printf 'runner stdout diagnostic\\n'
        printf 'runner stderr diagnostic\\n' >&2
        printf '{"type":"llm.request","id":123}\\n'
        """

        do {
            _ = try await DefaultMyWikiRunnerProcess().run(
                executable: "/bin/sh",
                arguments: ["-c", script],
                workingDirectory: root,
                environment: [:],
                timeoutSeconds: 5
            ) { line in
                if line.contains(#""type":"llm.request""#) {
                    throw MyWikiPipelineBridgeError.pipelineExecutionFailed("Bridge decode failed.")
                }
                return nil
            }
            XCTFail("Expected bridge failure.")
        } catch {
            guard case MyWikiPipelineBridgeError.pipelineExecutionFailed(let message) = error else {
                XCTFail("Expected pipelineExecutionFailed, got \(error)")
                return
            }
            XCTAssertTrue(message.contains("Bridge decode failed."), message)
            XCTAssertTrue(message.contains("runner stdout diagnostic"), message)
            XCTAssertTrue(message.contains("runner stderr diagnostic"), message)
        }
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
        XCTAssertTrue(statusText.contains("This app is missing the built-in MyWiki runner"), statusText)
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
        let options: LLMCompletionOptions
    }

    private let result: String
    private var requests: [Request] = []

    init(result: String) {
        self.result = result
    }

    func complete(messages: [MyWikiLLMMessage], options: LLMCompletionOptions) async throws -> String {
        requests.append(Request(messages: messages, options: options))
        return result
    }

    func recordedRequests() -> [Request] {
        requests
    }
}
