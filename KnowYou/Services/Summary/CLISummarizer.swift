import Foundation

protocol ProcessRunning: Sendable {
    func run(executable: String, arguments: [String]) async throws -> String
}

final class ContinuationGate<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var hasResumed = false

    func resume(returning value: T) -> Bool {
        lock.withLock {
            guard !hasResumed else { return false }
            hasResumed = true
            return true
        }
    }

    func resume(throwing error: Error) -> Bool {
        lock.withLock {
            guard !hasResumed else { return false }
            hasResumed = true
            return true
        }
    }
}

struct SystemProcessRunner: ProcessRunning {
    static let timeoutSeconds: Double = 120

    func run(executable: String, arguments: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                let gate = ContinuationGate<String>()
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments

                let outputPipe = Pipe()
                process.standardOutput = outputPipe
                process.standardError = Pipe()

                let timeoutItem = DispatchWorkItem {
                    process.terminate()
                    let error = CocoaError(
                        .executableLoad,
                        userInfo: [NSLocalizedDescriptionKey: "Summarizer CLI timed out after \(Int(Self.timeoutSeconds))s"]
                    )
                    guard gate.resume(throwing: error) else { return }
                    continuation.resume(throwing: error)
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + Self.timeoutSeconds, execute: timeoutItem)

                do {
                    try process.run()
                    process.waitUntilExit()
                    timeoutItem.cancel()
                    let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(decoding: data, as: UTF8.self)
                    guard gate.resume(returning: output) else { return }
                    continuation.resume(returning: output)
                } catch {
                    timeoutItem.cancel()
                    guard gate.resume(throwing: error) else { return }
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

struct CLISummarizer: SummaryGenerating {
    enum Tool: String, Sendable {
        case claude
        case codex
        case gemini
    }

    let tool: Tool
    let executablePath: String
    let runner: ProcessRunning

    init(tool: Tool, executablePath: String, runner: ProcessRunning = SystemProcessRunner()) {
        self.tool = tool
        self.executablePath = executablePath
        self.runner = runner
    }

    func summarize(dayKey: String, markdown: String) async throws -> String {
        let prompt = "Summarize this day as a concise diary entry for \(dayKey):\n\n\(markdown)"
        let arguments: [String]
        switch tool {
        case .claude, .gemini:
            arguments = ["-p", prompt]
        case .codex:
            arguments = [prompt]
        }
        let raw = try await runner.run(executable: executablePath, arguments: arguments)
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Summary unavailable." : trimmed
    }
}
