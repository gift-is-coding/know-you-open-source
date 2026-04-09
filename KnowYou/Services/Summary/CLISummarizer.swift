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
    private let environment: [String: String]

    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.environment = environment
    }

    func run(executable: String, arguments: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                let gate = ContinuationGate<String>()
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
                process.environment = processEnvironment(for: executable)

                let outputPipe = Pipe()
                let errorPipe = Pipe()
                process.standardOutput = outputPipe
                process.standardError = errorPipe

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
                    let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(decoding: outputData, as: UTF8.self)
                    let errorOutput = String(decoding: errorData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                    if process.terminationStatus != 0 {
                        let description = errorOutput.isEmpty
                            ? "Summarizer CLI exited with status \(process.terminationStatus)"
                            : errorOutput
                        let error = CocoaError(.executableLoad, userInfo: [NSLocalizedDescriptionKey: description])
                        guard gate.resume(throwing: error) else { return }
                        continuation.resume(throwing: error)
                        return
                    }
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

    func processEnvironment(for executable: String) -> [String: String] {
        var mergedEnvironment = environment
        let executableDirectory = URL(fileURLWithPath: executable).deletingLastPathComponent().path
        let existingPath = mergedEnvironment["PATH"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let pathEntries = existingPath
            .split(separator: ":")
            .map(String.init)
        let newPathEntries = [executableDirectory] + pathEntries.filter { $0 != executableDirectory }
        mergedEnvironment["PATH"] = newPathEntries.joined(separator: ":")
        return mergedEnvironment
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
    private static let dailyStorySchema = """
    {"type":"object","additionalProperties":false,"required":["sections"],"properties":{"sections":{"type":"array","items":{"type":"object","additionalProperties":false,"required":["id","paragraphs"],"properties":{"id":{"type":"string","const":"daily-journal"},"paragraphs":{"type":"array","minItems":1,"maxItems":4,"items":{"type":"object","additionalProperties":false,"required":["text","sourceEventIDs"],"properties":{"text":{"type":"string"},"sourceEventIDs":{"type":"array","minItems":1,"items":{"type":"string","pattern":"^[0-9A-Fa-f-]{36}$"}}}}}}}}}}
    """

    init(tool: Tool, executablePath: String, runner: ProcessRunning = SystemProcessRunner()) {
        self.tool = tool
        self.executablePath = executablePath
        self.runner = runner
    }

    func summarize(dayKey: String, markdown: String) async throws -> String {
        let arguments: [String]
        switch tool {
        case .claude:
            arguments = [
                "-p", markdown,
                "--output-format", "json",
                "--json-schema", Self.dailyStorySchema,
            ]
        case .gemini:
            arguments = [
                "-p", markdown,
                "--output-format", "text",
            ]
        case .codex:
            arguments = [markdown]
        }
        let raw = try await runner.run(executable: executablePath, arguments: arguments)
        let trimmed: String
        if tool == .claude, let structuredOutput = extractClaudeStructuredOutput(from: raw) {
            trimmed = structuredOutput
        } else {
            trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed.isEmpty ? "Summary unavailable." : trimmed
    }

    private func extractClaudeStructuredOutput(from raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8),
              let envelope = try? JSONDecoder().decode(ClaudeStructuredEnvelope.self, from: data),
              let structuredOutput = envelope.structuredOutput,
              let structuredData = try? JSONSerialization.data(withJSONObject: structuredOutput, options: []),
              let structuredText = String(data: structuredData, encoding: .utf8)
        else {
            return nil
        }

        return structuredText
    }
}

private struct ClaudeStructuredEnvelope: Decodable {
    let structuredOutput: JSONObjectValue?

    enum CodingKeys: String, CodingKey {
        case structuredOutput = "structured_output"
    }
}

private enum JSONObjectValue: Decodable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([JSONObjectValue])
    case object([String: JSONObjectValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONObjectValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([JSONObjectValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.typeMismatch(
                JSONObjectValue.self,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unsupported JSON value")
            )
        }
    }

    var foundationValue: Any {
        switch self {
        case .string(let value):
            return value
        case .number(let value):
            return value
        case .bool(let value):
            return value
        case .array(let values):
            return values.map(\.foundationValue)
        case .object(let values):
            return values.mapValues(\.foundationValue)
        case .null:
            return NSNull()
        }
    }
}

private extension JSONSerialization {
    static func data(withJSONObject value: JSONObjectValue, options: WritingOptions = []) throws -> Data {
        try data(withJSONObject: value.foundationValue, options: options)
    }
}
