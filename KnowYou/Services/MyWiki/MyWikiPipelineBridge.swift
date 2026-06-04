import Foundation

enum MyWikiPipelineTarget: Equatable {
    case bundledRunner(MyWikiRunnerBundle)
    case invalidBundledRunner(String)
    case developmentSource(URL)
    case missing

    var statusDescription: String {
        switch self {
        case .bundledRunner(let bundle):
            return "Using bundled MyWiki runner: \(bundle.rootURL.path)"
        case .invalidBundledRunner(let message):
            return message
        case .developmentSource(let url):
            return "Using development llm_wiki pipeline: \(url.path)"
        case .missing:
            return "MyWiki runner is not available."
        }
    }
}

enum MyWikiIngestBatchPolicy {
    static let maxSourcesPerRun = 3
}

enum MyWikiPipelineBridgeError: LocalizedError {
    case missingPipeline
    case pipelineExecutionFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingPipeline:
            return "Could not find the bundled MyWiki runner or ThirdParty/llm_wiki source."
        case .pipelineExecutionFailed(let detail):
            return detail
        }
    }
}

struct MyWikiPipelineBridge {
    private let processRunner: MyWikiPipelineProcessRunning
    private let runnerProcess: MyWikiRunnerProcessRunning
    private let npmInvocation: MyWikiProcessInvocation
    private let llmInvocation: MyWikiLLMInvocation
    private let llmBridge: MyWikiLLMBridge?

    init(
        processRunner: MyWikiPipelineProcessRunning = DefaultMyWikiPipelineProcessRunner(),
        runnerProcess: MyWikiRunnerProcessRunning = DefaultMyWikiRunnerProcess(),
        npmInvocation: MyWikiProcessInvocation = MyWikiNPMResolver().resolve(),
        llmInvocation: MyWikiLLMInvocation = .codexCLIDefault,
        llmBridge: MyWikiLLMBridge? = nil
    ) {
        self.processRunner = processRunner
        self.runnerProcess = runnerProcess
        self.npmInvocation = npmInvocation
        self.llmInvocation = llmInvocation
        self.llmBridge = llmBridge
    }

    static func resolveTarget(
        bundledRunner: MyWikiRunnerBundle?,
        developmentSourceURL: URL?,
        fileManager: FileManager = .default
    ) -> MyWikiPipelineTarget {
        if let bundledRunner {
            return .bundledRunner(bundledRunner)
        }
        if let developmentSourceURL,
           fileManager.fileExists(atPath: developmentSourceURL.path) {
            return .developmentSource(developmentSourceURL)
        }
        return .missing
    }

    static func resolveTarget(
        bundledRunner: Result<MyWikiRunnerBundle?, Error>,
        developmentSourceURL: URL?,
        fileManager: FileManager = .default
    ) -> MyWikiPipelineTarget {
        switch bundledRunner {
        case .success(let bundle):
            return resolveTarget(
                bundledRunner: bundle,
                developmentSourceURL: developmentSourceURL,
                fileManager: fileManager
            )
        case .failure(let error):
            return .invalidBundledRunner(error.localizedDescription)
        }
    }

    func runIngest(target: MyWikiPipelineTarget, projectRoot: URL, manifestURL: URL? = nil) async throws {
        try FileManager.default.createDirectory(
            at: projectRoot.appending(path: ".llm-wiki", directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )

        switch target {
        case .bundledRunner(let bundle):
            try await runBundledRunner(bundle: bundle, projectRoot: projectRoot, manifestURL: manifestURL)
        case .invalidBundledRunner(let message):
            try writeFailureStatus(message: message, projectRoot: projectRoot)
            throw MyWikiPipelineBridgeError.pipelineExecutionFailed(message)
        case .developmentSource(let sourceURL):
            try runDevelopmentPipeline(sourceURL: sourceURL, projectRoot: projectRoot, manifestURL: manifestURL)
        case .missing:
            let message = "MyWiki runner is not available."
            try writeFailureStatus(message: message, projectRoot: projectRoot)
            throw MyWikiPipelineBridgeError.missingPipeline
        }
    }

    @MainActor
    func openAdvancedWorkspace(target: MyWikiPipelineTarget, projectRoot: URL) throws {
        if case .bundledRunner = target {
            throw MyWikiPipelineBridgeError.pipelineExecutionFailed(
                "Advanced My Wiki workspace is not available for bundled runner builds yet."
            )
        }
        if case .invalidBundledRunner(let message) = target {
            throw MyWikiPipelineBridgeError.pipelineExecutionFailed(message)
        }
        try KnowledgeOntologyLauncher().launch(
            target: knowledgeOntologyTarget(from: target),
            projectRoot: projectRoot
        )
    }

    private func knowledgeOntologyTarget(from target: MyWikiPipelineTarget) -> KnowledgeOntologyLaunchTarget {
        switch target {
        case .bundledRunner:
            return .missing
        case .invalidBundledRunner:
            return .missing
        case .developmentSource(let url):
            return .developmentSource(url)
        case .missing:
            return .missing
        }
    }

    private func writeFailureStatus(message: String, projectRoot: URL) throws {
        let status = MyWikiIngestStatus(
            status: "failed",
            message: message,
            updatedAt: ISO8601DateFormatter().string(from: Date()),
            sourcesProcessed: 0,
            filesWritten: []
        )
        let data = try JSONEncoder().encode(status)
        try data.write(to: projectRoot.appending(path: ".llm-wiki/last-ingest-status.json"))
    }

    private func writeSuccessStatus(message: String, projectRoot: URL) throws {
        let status = MyWikiIngestStatus(
            status: "succeeded",
            message: message,
            updatedAt: ISO8601DateFormatter().string(from: Date()),
            sourcesProcessed: nil,
            filesWritten: nil
        )
        let data = try JSONEncoder().encode(status)
        try data.write(to: projectRoot.appending(path: ".llm-wiki/last-ingest-status.json"))
    }

    private func runBundledRunner(bundle: MyWikiRunnerBundle, projectRoot: URL, manifestURL: URL?) async throws {
        guard let llmBridge else {
            let message = "My Wiki Diary Engine bridge is not configured."
            try writeFailureStatus(message: message, projectRoot: projectRoot)
            throw MyWikiPipelineBridgeError.pipelineExecutionFailed(message)
        }

        var arguments = [
            bundle.scriptURL.path,
            "--project",
            projectRoot.path,
            "--provider",
            "knowyou-bridge",
            "--max-sources",
            "\(MyWikiIngestBatchPolicy.maxSourcesPerRun)"
        ]
        if let manifestURL {
            arguments.append(contentsOf: ["--manifest", manifestURL.path])
        }

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let result: MyWikiPipelineProcessResult
        do {
            result = try await runnerProcess.run(
                executable: bundle.nodeURL.path,
                arguments: arguments,
                workingDirectory: bundle.rootURL,
                environment: [:],
                timeoutSeconds: 30 * 60
            ) { line in
                try await Self.bridgeResponseJSONL(
                    for: line,
                    decoder: decoder,
                    encoder: encoder,
                    llmBridge: llmBridge
                )
            }
        } catch {
            try writeFailureStatus(message: error.localizedDescription, projectRoot: projectRoot)
            throw error
        }

        guard result.terminationStatus == 0 else {
            let detail = [result.stderr, result.stdout]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { $0.isEmpty == false }
                .joined(separator: "\n")
            let message = detail.isEmpty
                ? "MyWiki bundled runner exited with status \(result.terminationStatus)."
                : detail
            try writeFailureStatus(message: message, projectRoot: projectRoot)
            throw MyWikiPipelineBridgeError.pipelineExecutionFailed(message)
        }

        try writeSuccessStatus(message: "My Wiki pipeline completed.", projectRoot: projectRoot)
    }

    private static func bridgeResponseJSONL(
        for line: String,
        decoder: JSONDecoder,
        encoder: JSONEncoder,
        llmBridge: MyWikiLLMBridge
    ) async throws -> String? {
        guard let data = line.data(using: .utf8),
              let header = try? decoder.decode(MyWikiBridgeEventHeader.self, from: data),
              header.type.hasPrefix("llm.")
        else {
            return nil
        }

        let envelope = try decoder.decode(MyWikiBridgeEnvelope.self, from: data)
        let response = try await llmBridge.handle(envelope)
        let responseData = try encoder.encode(response)
        return String(data: responseData, encoding: .utf8)
    }

    private func runDevelopmentPipeline(sourceURL: URL, projectRoot: URL, manifestURL: URL?) throws {
        let packageURL = sourceURL.appending(path: "package.json")
        guard FileManager.default.fileExists(atPath: packageURL.path) else {
            let message = "headless llm_wiki runner is not available for development source yet."
            try writeFailureStatus(message: message, projectRoot: projectRoot)
            throw MyWikiPipelineBridgeError.pipelineExecutionFailed(message)
        }

        try ensureDevelopmentDependencies(sourceURL: sourceURL, projectRoot: projectRoot)

        var arguments = [
            "run",
            "knowyou:ingest",
            "--",
            "--project",
            projectRoot.path
        ]
        arguments.append(contentsOf: llmInvocation.arguments)
        arguments.append(contentsOf: [
            "--max-sources",
            "\(MyWikiIngestBatchPolicy.maxSourcesPerRun)"
        ])
        if let manifestURL {
            arguments.append(contentsOf: ["--manifest", manifestURL.path])
        }

        let result = try processRunner.run(
            executable: npmInvocation.executable,
            arguments: npmInvocation.argumentPrefix + arguments,
            workingDirectory: sourceURL,
            environment: llmInvocation.environment,
            timeoutSeconds: 30 * 60
        )

        guard result.terminationStatus == 0 else {
            let detail = [result.stderr, result.stdout]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { $0.isEmpty == false }
                .joined(separator: "\n")
            let message = detail.isEmpty
                ? "llm_wiki headless runner exited with status \(result.terminationStatus)."
                : detail
            try writeFailureStatus(message: message, projectRoot: projectRoot)
            throw MyWikiPipelineBridgeError.pipelineExecutionFailed(message)
        }

        try writeSuccessStatus(message: "My Wiki pipeline completed.", projectRoot: projectRoot)
    }

    private func ensureDevelopmentDependencies(sourceURL: URL, projectRoot: URL) throws {
        let viteDependencyURL = sourceURL.appending(path: "node_modules/vite", directoryHint: .isDirectory)
        guard FileManager.default.fileExists(atPath: viteDependencyURL.path) == false else {
            return
        }

        let result = try processRunner.run(
            executable: npmInvocation.executable,
            arguments: npmInvocation.argumentPrefix + ["install"],
            workingDirectory: sourceURL,
            environment: [:],
            timeoutSeconds: 10 * 60
        )
        guard result.terminationStatus == 0 else {
            let detail = [result.stderr, result.stdout]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { $0.isEmpty == false }
                .joined(separator: "\n")
            let message = detail.isEmpty
                ? "Could not install llm_wiki dependencies."
                : "Could not install llm_wiki dependencies:\n\(detail)"
            try writeFailureStatus(message: message, projectRoot: projectRoot)
            throw MyWikiPipelineBridgeError.pipelineExecutionFailed(message)
        }
    }
}

struct MyWikiLLMInvocation: Equatable {
    let arguments: [String]
    let environment: [String: String]

    static let codexCLIDefault = MyWikiLLMInvocation(
        arguments: ["--provider", "codex-cli", "--model", "gpt-5.5"],
        environment: [:]
    )

    static func resolve(
        from config: SummarizerConfig,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> MyWikiLLMInvocation {
        switch config.defaultEngine {
        case .llmAPI:
            return try llmAPIInvocation(from: config.activeLLMAPIProviderConfig)
        case .claudeCLI:
            return MyWikiLLMInvocation(
                arguments: ["--provider", "claude-code", "--model", "claude-sonnet-4-5"],
                environment: cliEnvironment(
                    executablePath: config.claudeCLIPath,
                    commandName: "claude",
                    environment: environment
                )
            )
        case .codexCLI:
            return MyWikiLLMInvocation(
                arguments: ["--provider", "codex-cli", "--model", "gpt-5.5"],
                environment: cliEnvironment(
                    executablePath: config.codexCLIPath,
                    commandName: "codex",
                    environment: environment
                )
            )
        case .none, .codexAuth, .geminiCLI, .openclawCLI:
            let message = "My Wiki LLM needs a configured LLM API, Claude CLI, or Codex CLI engine."
            throw MyWikiPipelineBridgeError.pipelineExecutionFailed(message)
        }
    }

    private static func llmAPIInvocation(from providerConfig: LLMAPIProviderConfig) throws -> MyWikiLLMInvocation {
        let token = providerConfig.apiToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = providerConfig.model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty, !model.isEmpty, providerConfig.validatedBaseURL() != nil else {
            throw MyWikiPipelineBridgeError.pipelineExecutionFailed("My Wiki LLM API configuration is incomplete.")
        }

        let provider: String
        let extraArguments: [String]
        switch providerConfig.id {
        case .openAI:
            provider = "openai"
            extraArguments = []
        case .anthropic:
            provider = "anthropic"
            extraArguments = []
        case .gemini:
            provider = "google"
            extraArguments = []
        case .deepSeek, .openRouter, .qwen, .kimi, .zhipu, .customOpenAICompatible:
            provider = "custom"
            extraArguments = [
                "--custom-endpoint",
                providerConfig.baseURL,
                "--api-mode",
                apiMode(for: providerConfig.wireFormat)
            ]
        }

        return MyWikiLLMInvocation(
            arguments: ["--provider", provider, "--model", model] + extraArguments,
            environment: ["KNOWYOU_MYWIKI_LLM_API_KEY": token]
        )
    }

    private static func apiMode(for wireFormat: LLMAPIWireFormat) -> String {
        switch wireFormat {
        case .anthropicMessages:
            return "anthropic_messages"
        case .openAIResponses, .openAIChat, .geminiGenerateContent:
            return "chat_completions"
        }
    }

    private static func cliEnvironment(
        executablePath: String,
        commandName: String,
        environment: [String: String]
    ) -> [String: String] {
        guard
            let resolvedPath = SummarizerConfig.resolvedExecutablePath(
                configuredPath: executablePath,
                commandName: commandName,
                environment: environment
            )
        else {
            return [:]
        }
        let directory = URL(fileURLWithPath: resolvedPath).deletingLastPathComponent().path
        let currentPath = environment["PATH"] ?? ""
        return [
            "PATH": currentPath.isEmpty ? directory : "\(directory):\(currentPath)"
        ]
    }
}

struct MyWikiProcessInvocation: Equatable {
    let executable: String
    let argumentPrefix: [String]

    static let environmentNPM = MyWikiProcessInvocation(
        executable: "/usr/bin/env",
        argumentPrefix: ["npm"]
    )
}

struct MyWikiNPMResolver {
    private let environment: [String: String]
    private let homeDirectory: URL
    private let fileManager: FileManager

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) {
        self.environment = environment
        self.homeDirectory = homeDirectory
        self.fileManager = fileManager
    }

    func resolve() -> MyWikiProcessInvocation {
        if let npm = npmFromPATH() {
            return MyWikiProcessInvocation(executable: npm.path, argumentPrefix: [])
        }
        for candidate in nvmCandidates() + fixedCandidates() where fileManager.isExecutableFile(atPath: candidate.path) {
            return MyWikiProcessInvocation(executable: candidate.path, argumentPrefix: [])
        }
        return .environmentNPM
    }

    private func npmFromPATH() -> URL? {
        guard let path = environment["PATH"] else { return nil }
        for directory in path.split(separator: ":").map(String.init) where directory.isEmpty == false {
            let candidate = URL(fileURLWithPath: directory).appending(path: "npm")
            if fileManager.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    private func fixedCandidates() -> [URL] {
        [
            URL(fileURLWithPath: "/opt/homebrew/bin/npm"),
            URL(fileURLWithPath: "/usr/local/bin/npm")
        ]
    }

    private func nvmCandidates() -> [URL] {
        let nodeVersionsDirectory = homeDirectory
            .appending(path: ".nvm/versions/node", directoryHint: .isDirectory)
        guard let entries = try? fileManager.contentsOfDirectory(
            at: nodeVersionsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return entries
            .filter { url in
                (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedDescending }
            .map { $0.appending(path: "bin/npm") }
    }
}

struct MyWikiDigestRunResult: Equatable {
    let message: String
    let didSucceed: Bool
}

struct MyWikiDigestRunner {
    func run(
        projectRoot: URL,
        sourceVault: URL?,
        importedDocuments: [ImportedKnowledgeDocument],
        target: MyWikiPipelineTarget,
        summarizer: SummaryGenerating? = nil,
        llmInvocation: MyWikiLLMInvocation? = nil
    ) async -> MyWikiDigestRunResult {
        await Task.detached(priority: .userInitiated) {
            do {
                let resolvedLLMBridge = (summarizer as? any MyWikiLLMCompleting).map(MyWikiLLMBridge.init(engine:))
                let resolvedLLMInvocation: MyWikiLLMInvocation?
                if case .developmentSource = target {
                    resolvedLLMInvocation = try llmInvocation ?? MyWikiLLMInvocation.resolve(
                        from: SummarizerConfig.load()
                    )
                } else {
                    resolvedLLMInvocation = llmInvocation
                }
                try MyWikiProjectExporter().ensureProject(at: projectRoot)

                let builder = MyWikiSourceCatalogBuilder()
                var snapshot = try builder.refreshCatalog(
                    projectRoot: projectRoot,
                    sourceVault: sourceVault,
                    importedDocuments: importedDocuments
                )
                let plan = builder.ingestPlan(
                    snapshot: snapshot,
                    maxSources: MyWikiIngestBatchPolicy.maxSourcesPerRun
                )

                guard plan.sources.isEmpty == false else {
                    return MyWikiDigestRunResult(
                        message: "My Wiki sources are already up to date.",
                        didSucceed: true
                    )
                }

                let materialized = try builder.materialize(
                    plan: plan,
                    from: snapshot,
                    projectRoot: projectRoot
                )

                do {
                    let pipelineBridge = MyWikiPipelineBridge(
                        llmInvocation: resolvedLLMInvocation ?? .codexCLIDefault,
                        llmBridge: resolvedLLMBridge
                    )
                    try await pipelineBridge.runIngest(
                        target: target,
                        projectRoot: projectRoot,
                        manifestURL: materialized.manifestURL
                    )
                    snapshot = builder.mark(plan: plan, succeededIn: snapshot, at: Date())
                    try MyWikiSourceCatalogStore(projectRoot: projectRoot).save(snapshot)
                    return MyWikiDigestRunResult(
                        message: "Updated \(materialized.materializedCount) My Wiki source(s).",
                        didSucceed: true
                    )
                } catch {
                    snapshot = builder.mark(plan: plan, failedWith: error.localizedDescription, in: snapshot)
                    try? MyWikiSourceCatalogStore(projectRoot: projectRoot).save(snapshot)
                    return MyWikiDigestRunResult(
                        message: "My Wiki source update failed: \(error.localizedDescription)",
                        didSucceed: false
                    )
                }
            } catch {
                return MyWikiDigestRunResult(
                    message: error.localizedDescription,
                    didSucceed: false
                )
            }
        }.value
    }
}

private struct MyWikiIngestStatus: Encodable {
    let status: String
    let message: String
    let updatedAt: String
    let sourcesProcessed: Int?
    let filesWritten: [String]?
}

private struct MyWikiBridgeEventHeader: Decodable {
    let type: String
}

struct MyWikiPipelineProcessResult: Equatable {
    let stdout: String
    let stderr: String
    let terminationStatus: Int32
}

protocol MyWikiPipelineProcessRunning: Sendable {
    func run(
        executable: String,
        arguments: [String],
        workingDirectory: URL,
        environment: [String: String],
        timeoutSeconds: TimeInterval
    ) throws -> MyWikiPipelineProcessResult
}

protocol MyWikiRunnerProcessRunning: Sendable {
    func run(
        executable: String,
        arguments: [String],
        workingDirectory: URL,
        environment: [String: String],
        timeoutSeconds: TimeInterval,
        onEvent: @escaping @Sendable (String) async throws -> String?
    ) async throws -> MyWikiPipelineProcessResult
}

struct DefaultMyWikiPipelineProcessRunner: MyWikiPipelineProcessRunning {
    func run(
        executable: String,
        arguments: [String],
        workingDirectory: URL,
        environment: [String: String],
        timeoutSeconds: TimeInterval
    ) throws -> MyWikiPipelineProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory
        if environment.isEmpty == false {
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        }

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()

        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while process.isRunning && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        if process.isRunning {
            process.terminate()
            throw MyWikiPipelineBridgeError.pipelineExecutionFailed("llm_wiki headless runner timed out.")
        }

        let stdoutData = stdout.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()
        return MyWikiPipelineProcessResult(
            stdout: String(data: stdoutData, encoding: .utf8) ?? "",
            stderr: String(data: stderrData, encoding: .utf8) ?? "",
            terminationStatus: process.terminationStatus
        )
    }
}

struct DefaultMyWikiRunnerProcess: MyWikiRunnerProcessRunning {
    func run(
        executable: String,
        arguments: [String],
        workingDirectory: URL,
        environment: [String: String],
        timeoutSeconds: TimeInterval,
        onEvent: @escaping @Sendable (String) async throws -> String?
    ) async throws -> MyWikiPipelineProcessResult {
        let controller = MyWikiRunnerProcessController()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global().async {
                    let gate = ContinuationGate<MyWikiPipelineProcessResult>()
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: executable)
                    process.arguments = arguments
                    process.currentDirectoryURL = workingDirectory
                    process.environment = environment

                    let stdin = Pipe()
                    let stdout = Pipe()
                    let stderr = Pipe()
                    let inputWriter = MyWikiRunnerInputWriter(handle: stdin.fileHandleForWriting)
                    let outputState = MyWikiRunnerProcessOutputState()
                    let eventGroup = DispatchGroup()

                    process.standardInput = stdin
                    process.standardOutput = stdout
                    process.standardError = stderr
                    controller.attach(process)

                    let processLine: @Sendable (String) -> Void = { line in
                        eventGroup.enter()
                        Task {
                            do {
                                if let response = try await onEvent(line) {
                                    inputWriter.write(line: response)
                                }
                            } catch {
                                outputState.record(error: error)
                                controller.terminate()
                            }
                            eventGroup.leave()
                        }
                    }

                    stdout.fileHandleForReading.readabilityHandler = { handle in
                        let data = handle.availableData
                        guard data.isEmpty == false else { return }
                        for line in outputState.appendStdout(data) {
                            processLine(line)
                        }
                    }
                    stderr.fileHandleForReading.readabilityHandler = { handle in
                        let data = handle.availableData
                        guard data.isEmpty == false else { return }
                        outputState.appendStderr(data)
                    }

                    let timeoutItem = DispatchWorkItem {
                        controller.terminate()
                        let error = MyWikiPipelineBridgeError.pipelineExecutionFailed("MyWiki bundled runner timed out.")
                        guard gate.resume(throwing: error) else { return }
                        continuation.resume(throwing: error)
                    }
                    DispatchQueue.global().asyncAfter(deadline: .now() + timeoutSeconds, execute: timeoutItem)

                    do {
                        guard controller.shouldLaunch else {
                            throw CancellationError()
                        }
                        try process.run()
                        controller.didLaunch()
                        process.waitUntilExit()
                        timeoutItem.cancel()

                        stdout.fileHandleForReading.readabilityHandler = nil
                        stderr.fileHandleForReading.readabilityHandler = nil

                        let remainingStdout = stdout.fileHandleForReading.readDataToEndOfFile()
                        if remainingStdout.isEmpty == false {
                            for line in outputState.appendStdout(remainingStdout) {
                                processLine(line)
                            }
                        }
                        let remainingStderr = stderr.fileHandleForReading.readDataToEndOfFile()
                        if remainingStderr.isEmpty == false {
                            outputState.appendStderr(remainingStderr)
                        }
                        for line in outputState.flushStdoutLineBuffer() {
                            processLine(line)
                        }

                        eventGroup.wait()
                        inputWriter.close()

                        if let error = outputState.recordedError() {
                            let result = outputState.result(terminationStatus: process.terminationStatus)
                            let enrichedError = Self.bridgeFailureError(error: error, result: result)
                            guard gate.resume(throwing: enrichedError) else { return }
                            continuation.resume(throwing: enrichedError)
                            return
                        }

                        let result = outputState.result(terminationStatus: process.terminationStatus)
                        guard gate.resume(returning: result) else { return }
                        continuation.resume(returning: result)
                    } catch {
                        timeoutItem.cancel()
                        inputWriter.close()
                        guard gate.resume(throwing: error) else { return }
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            controller.terminate()
        }
    }

    private static func bridgeFailureError(
        error: Error,
        result: MyWikiPipelineProcessResult
    ) -> MyWikiPipelineBridgeError {
        let parts = [
            error.localizedDescription,
            result.stderr,
            result.stdout
        ]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
        let message = parts.isEmpty
            ? "MyWiki bundled runner bridge failed."
            : parts.joined(separator: "\n")
        return .pipelineExecutionFailed(message)
    }
}

final class MyWikiRunnerProcessController: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var terminateRequested = false
    private var hasLaunched = false

    var shouldLaunch: Bool {
        lock.withLock {
            terminateRequested == false
        }
    }

    func attach(_ process: Process) {
        lock.withLock {
            self.process = process
        }
    }

    func didLaunch() {
        let processToTerminate = lock.withLock {
            hasLaunched = true
            guard terminateRequested, let process, process.isRunning else {
                return nil as Process?
            }
            return process
        }
        processToTerminate?.terminate()
    }

    func terminate() {
        let processToTerminate = lock.withLock {
            terminateRequested = true
            guard hasLaunched, let process, process.isRunning else {
                return nil as Process?
            }
            return process
        }
        processToTerminate?.terminate()
    }
}

private final class MyWikiRunnerInputWriter: @unchecked Sendable {
    private let handle: FileHandle
    private let lock = NSLock()

    init(handle: FileHandle) {
        self.handle = handle
    }

    func write(line: String) {
        lock.withLock {
            handle.write(Data((line + "\n").utf8))
        }
    }

    func close() {
        lock.withLock {
            try? handle.close()
        }
    }
}

private final class MyWikiRunnerProcessOutputState: @unchecked Sendable {
    private let lock = NSLock()
    private var stdoutData = Data()
    private var stderrData = Data()
    private var stdoutLineBuffer = Data()
    private var firstError: Error?

    func appendStdout(_ data: Data) -> [String] {
        lock.withLock {
            stdoutData.append(data)
            stdoutLineBuffer.append(data)
            return drainStdoutLinesLocked()
        }
    }

    func flushStdoutLineBuffer() -> [String] {
        lock.withLock {
            guard stdoutLineBuffer.isEmpty == false else { return [] }
            let line = Self.lineString(from: stdoutLineBuffer)
            stdoutLineBuffer.removeAll(keepingCapacity: true)
            return line.map { [$0] } ?? []
        }
    }

    func appendStderr(_ data: Data) {
        lock.withLock {
            stderrData.append(data)
        }
    }

    func record(error: Error) {
        lock.withLock {
            if firstError == nil {
                firstError = error
            }
        }
    }

    func recordedError() -> Error? {
        lock.withLock { firstError }
    }

    func result(terminationStatus: Int32) -> MyWikiPipelineProcessResult {
        lock.withLock {
            MyWikiPipelineProcessResult(
                stdout: String(decoding: stdoutData, as: UTF8.self),
                stderr: String(decoding: stderrData, as: UTF8.self),
                terminationStatus: terminationStatus
            )
        }
    }

    private func drainStdoutLinesLocked() -> [String] {
        var lines: [String] = []
        while let newlineIndex = stdoutLineBuffer.firstIndex(of: 0x0A) {
            let lineData = stdoutLineBuffer[..<newlineIndex]
            stdoutLineBuffer.removeSubrange(...newlineIndex)
            if let line = Self.lineString(from: Data(lineData)) {
                lines.append(line)
            }
        }
        return lines
    }

    private static func lineString(from data: Data) -> String? {
        var lineData = data
        if lineData.last == 0x0D {
            lineData.removeLast()
        }
        guard lineData.isEmpty == false else {
            return nil
        }
        return String(data: lineData, encoding: .utf8)
    }
}
