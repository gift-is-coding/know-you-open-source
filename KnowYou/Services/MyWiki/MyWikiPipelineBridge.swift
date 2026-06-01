import Foundation

enum MyWikiPipelineTarget: Equatable {
    case bundledHelperApp(URL)
    case developmentSource(URL)
    case missing

    var statusDescription: String {
        switch self {
        case .bundledHelperApp(let url):
            return "Using bundled llm_wiki pipeline: \(url.path)"
        case .developmentSource(let url):
            return "Using development llm_wiki pipeline: \(url.path)"
        case .missing:
            return "llm_wiki pipeline is not available."
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
            return "Could not find the bundled llm_wiki helper or ThirdParty/llm_wiki source."
        case .pipelineExecutionFailed(let detail):
            return detail
        }
    }
}

struct MyWikiPipelineBridge {
    private let processRunner: MyWikiPipelineProcessRunning
    private let npmExecutable: String

    init(
        processRunner: MyWikiPipelineProcessRunning = DefaultMyWikiPipelineProcessRunner(),
        npmExecutable: String = "/usr/bin/env"
    ) {
        self.processRunner = processRunner
        self.npmExecutable = npmExecutable
    }

    static func resolveTarget(
        bundledHelperAppURL: URL?,
        developmentSourceURL: URL,
        fileManager: FileManager = .default
    ) -> MyWikiPipelineTarget {
        let legacyTarget = KnowledgeOntologyLauncher.resolveLaunchTarget(
            bundledHelperAppURL: bundledHelperAppURL,
            developmentSourceURL: developmentSourceURL,
            fileManager: fileManager
        )

        switch legacyTarget {
        case .bundledHelperApp(let url):
            return .bundledHelperApp(url)
        case .developmentSource(let url):
            return .developmentSource(url)
        case .missing:
            return .missing
        }
    }

    func runIngest(target: MyWikiPipelineTarget, projectRoot: URL, manifestURL: URL? = nil) throws {
        try FileManager.default.createDirectory(
            at: projectRoot.appending(path: ".llm-wiki", directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )

        switch target {
        case .bundledHelperApp:
            let message = "headless llm_wiki runner is not available for bundled helper apps yet."
            try writeFailureStatus(message: message, projectRoot: projectRoot)
            throw MyWikiPipelineBridgeError.pipelineExecutionFailed(message)
        case .developmentSource(let sourceURL):
            try runDevelopmentPipeline(sourceURL: sourceURL, projectRoot: projectRoot, manifestURL: manifestURL)
        case .missing:
            let message = "llm_wiki pipeline is not available."
            try writeFailureStatus(message: message, projectRoot: projectRoot)
            throw MyWikiPipelineBridgeError.missingPipeline
        }
    }

    @MainActor
    func openAdvancedWorkspace(target: MyWikiPipelineTarget, projectRoot: URL) throws {
        try KnowledgeOntologyLauncher().launch(
            target: knowledgeOntologyTarget(from: target),
            projectRoot: projectRoot
        )
    }

    private func knowledgeOntologyTarget(from target: MyWikiPipelineTarget) -> KnowledgeOntologyLaunchTarget {
        switch target {
        case .bundledHelperApp(let url):
            return .bundledHelperApp(url)
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
            "npm",
            "run",
            "knowyou:ingest",
            "--",
            "--project",
            projectRoot.path,
            "--provider",
            "codex-cli",
            "--model",
            "gpt-5.5",
            "--max-sources",
            "\(MyWikiIngestBatchPolicy.maxSourcesPerRun)"
        ]
        if let manifestURL {
            arguments.append(contentsOf: ["--manifest", manifestURL.path])
        }

        let result = try processRunner.run(
            executable: npmExecutable,
            arguments: arguments,
            workingDirectory: sourceURL,
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
            executable: npmExecutable,
            arguments: ["npm", "install"],
            workingDirectory: sourceURL,
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

struct MyWikiDigestRunResult: Equatable {
    let message: String
    let didSucceed: Bool
}

struct MyWikiDigestRunner {
    func run(
        projectRoot: URL,
        sourceVault: URL?,
        importedDocuments: [ImportedKnowledgeDocument],
        target: MyWikiPipelineTarget
    ) async -> MyWikiDigestRunResult {
        await Task.detached(priority: .userInitiated) {
            do {
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
                    try MyWikiPipelineBridge().runIngest(
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
        timeoutSeconds: TimeInterval
    ) throws -> MyWikiPipelineProcessResult
}

struct DefaultMyWikiPipelineProcessRunner: MyWikiPipelineProcessRunning {
    func run(
        executable: String,
        arguments: [String],
        workingDirectory: URL,
        timeoutSeconds: TimeInterval
    ) throws -> MyWikiPipelineProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory

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
