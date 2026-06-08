import Foundation

enum MyWikiPipelineTarget: Equatable {
    case bundledRunner(MyWikiRunnerBundle)
    case invalidBundledRunner(String)
    case missing

    var statusDescription: String {
        switch self {
        case .bundledRunner(let bundle):
            return "Using bundled MyWiki runner: \(bundle.rootURL.path)"
        case .invalidBundledRunner(let message):
            return message
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
            return "MyWiki runner is not available."
        case .pipelineExecutionFailed(let detail):
            return detail
        }
    }
}

struct MyWikiPipelineBridge {
    private let runnerProcess: MyWikiRunnerProcessRunning
    private let llmBridge: MyWikiLLMBridge?

    init(
        runnerProcess: MyWikiRunnerProcessRunning = DefaultMyWikiRunnerProcess(),
        llmBridge: MyWikiLLMBridge? = nil
    ) {
        self.runnerProcess = runnerProcess
        self.llmBridge = llmBridge
    }

    static func resolveTarget(
        bundledRunner: MyWikiRunnerBundle?,
        fileManager: FileManager = .default
    ) -> MyWikiPipelineTarget {
        if let bundledRunner {
            return .bundledRunner(bundledRunner)
        }
        return .missing
    }

    static func resolveTarget(
        bundledRunner: Result<MyWikiRunnerBundle?, Error>,
        fileManager: FileManager = .default
    ) -> MyWikiPipelineTarget {
        switch bundledRunner {
        case .success(let bundle):
            return resolveTarget(
                bundledRunner: bundle,
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
        case .missing:
            let message = "MyWiki runner is not available."
            try writeFailureStatus(message: message, projectRoot: projectRoot)
            throw MyWikiPipelineBridgeError.missingPipeline
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
        try preserveOrWriteSuccessStatus(message: "My Wiki pipeline completed.", projectRoot: projectRoot)
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

    private func preserveOrWriteSuccessStatus(message: String, projectRoot: URL) throws {
        let statusURL = projectRoot.appending(path: ".llm-wiki/last-ingest-status.json")
        if let data = try? Data(contentsOf: statusURL),
           let status = try? JSONDecoder().decode(MyWikiIngestStatusFile.self, from: data),
           status.status == "succeeded" {
            return
        }
        try writeSuccessStatus(message: message, projectRoot: projectRoot)
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
    ) async -> MyWikiDigestRunResult {
        await Task.detached(priority: .userInitiated) {
            do {
                let resolvedLLMBridge = (summarizer as? any MyWikiLLMCompleting).map(MyWikiLLMBridge.init(engine:))
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

private struct MyWikiIngestStatusFile: Decodable {
    let status: String
}

private struct MyWikiBridgeEventHeader: Decodable {
    let type: String
}

struct MyWikiPipelineProcessResult: Equatable {
    let stdout: String
    let stderr: String
    let terminationStatus: Int32
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
