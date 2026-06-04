import Foundation

enum MyWikiPipelineTarget: Equatable {
    case bundledRunner(MyWikiRunnerBundle)
    case developmentSource(URL)
    case missing

    var statusDescription: String {
        switch self {
        case .bundledRunner(let bundle):
            return "Using bundled MyWiki runner: \(bundle.rootURL.path)"
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
    private let npmInvocation: MyWikiProcessInvocation
    private let llmInvocation: MyWikiLLMInvocation

    init(
        processRunner: MyWikiPipelineProcessRunning = DefaultMyWikiPipelineProcessRunner(),
        npmInvocation: MyWikiProcessInvocation = MyWikiNPMResolver().resolve(),
        llmInvocation: MyWikiLLMInvocation = .codexCLIDefault
    ) {
        self.processRunner = processRunner
        self.npmInvocation = npmInvocation
        self.llmInvocation = llmInvocation
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

    func runIngest(target: MyWikiPipelineTarget, projectRoot: URL, manifestURL: URL? = nil) throws {
        try FileManager.default.createDirectory(
            at: projectRoot.appending(path: ".llm-wiki", directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )

        switch target {
        case .bundledRunner:
            let message = "headless MyWiki runner execution is not available for bundled runner builds yet."
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
        try KnowledgeOntologyLauncher().launch(
            target: knowledgeOntologyTarget(from: target),
            projectRoot: projectRoot
        )
    }

    private func knowledgeOntologyTarget(from target: MyWikiPipelineTarget) -> KnowledgeOntologyLaunchTarget {
        switch target {
        case .bundledRunner:
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
        llmInvocation: MyWikiLLMInvocation? = nil
    ) async -> MyWikiDigestRunResult {
        await Task.detached(priority: .userInitiated) {
            do {
                let resolvedLLMInvocation = try llmInvocation ?? MyWikiLLMInvocation.resolve(
                    from: SummarizerConfig.load()
                )
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
                    try MyWikiPipelineBridge(llmInvocation: resolvedLLMInvocation).runIngest(
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

struct MyWikiPipelineProcessResult: Equatable {
    let stdout: String
    let stderr: String
    let terminationStatus: Int32
}

protocol MyWikiPipelineProcessRunning {
    func run(
        executable: String,
        arguments: [String],
        workingDirectory: URL,
        environment: [String: String],
        timeoutSeconds: TimeInterval
    ) throws -> MyWikiPipelineProcessResult
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
