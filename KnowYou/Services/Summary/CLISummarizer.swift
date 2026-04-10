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
        case openclaw
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
        let raw = try await runner.run(executable: executablePath, arguments: arguments(for: markdown))
        let trimmed: String
        if tool == .claude, let structuredOutput = validatedClaudeStoryJSON(from: raw) {
            trimmed = structuredOutput
        } else if let extractedText = extractedTextOutput(from: raw) {
            trimmed = extractedText
        } else {
            trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed.isEmpty ? "Summary unavailable." : trimmed
    }

    func smokeTest(prompt: String? = nil) async throws -> String {
        let probePrompt = prompt ?? smokeTestPrompt()
        let output = try await runner.run(executable: executablePath, arguments: arguments(for: probePrompt))
        let trimmed = extractedTextOutput(from: output) ?? output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw CocoaError(
                .executableLoad,
                userInfo: [NSLocalizedDescriptionKey: "Smoke test returned empty output"]
            )
        }
        if tool == .claude {
            if let validatedStructuredOutput = validatedClaudeStoryJSON(from: trimmed) {
                return validatedStructuredOutput
            }

            guard let validatedRawOutput = validatedDailyStoryJSON(from: trimmed) else {
                throw CocoaError(
                    .executableLoad,
                    userInfo: [NSLocalizedDescriptionKey: "Smoke test returned invalid Claude output"]
                )
            }
            return validatedRawOutput
        }
        if acceptsAcknowledgementSmokeTest,
           normalizedAcknowledgement(from: trimmed) != nil {
            return trimmed
        }
        guard let validatedRawOutput = validatedDailyStoryJSON(from: trimmed) else {
            throw CocoaError(
                .executableLoad,
                userInfo: [NSLocalizedDescriptionKey: "Smoke test returned invalid story JSON"]
            )
        }
        return validatedRawOutput
    }

    func arguments(for prompt: String) -> [String] {
        switch tool {
        case .claude:
            return [
                "-p", prompt,
                "--output-format", "json",
                "--json-schema", Self.dailyStorySchema,
            ]
        case .gemini:
            return [
                "-p", prompt,
                "--output-format", "json",
            ]
        case .codex:
            return [
                "exec",
                "--skip-git-repo-check",
                prompt,
            ]
        case .openclaw:
            return [
                "agent",
                "--agent", "main",
                "--message", prompt,
                "--local",
                "--json",
            ]
        }
    }

    private func smokeTestPrompt() -> String {
        switch tool {
        case .claude:
            return "Return a minimal valid JSON object that matches the daily story schema."
        case .codex, .gemini, .openclaw:
            return "Reply with OK."
        }
    }

    private var acceptsAcknowledgementSmokeTest: Bool {
        switch tool {
        case .claude:
            return false
        case .codex, .gemini, .openclaw:
            return true
        }
    }

    private func extractClaudeStructuredOutput(from raw: String) -> String? {
        guard let normalized = normalizedStoryJSONText(from: raw),
              let data = normalized.data(using: .utf8),
              let envelope = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let structuredOutput = envelope["structured_output"],
              let structuredData = try? JSONSerialization.data(withJSONObject: structuredOutput, options: []),
              let structuredText = String(data: structuredData, encoding: .utf8)
        else {
            return nil
        }

        return structuredText
    }

    private func validatedClaudeStoryJSON(from raw: String) -> String? {
        if let structuredOutput = extractClaudeStructuredOutput(from: raw),
           let validatedStructuredOutput = validatedDailyStoryJSON(from: structuredOutput) {
            return validatedStructuredOutput
        }

        return validatedDailyStoryJSON(from: raw)
    }

    private func validatedDailyStoryJSON(from raw: String) -> String? {
        guard
            let normalized = normalizedStoryJSONText(from: raw),
            let data = normalized.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data),
            isValidDailyStoryPayload(json),
            let serialized = try? JSONSerialization.data(withJSONObject: json, options: []),
            let text = String(data: serialized, encoding: .utf8)
        else {
            return nil
        }

        return text
    }

    private func extractedTextOutput(from raw: String) -> String? {
        switch tool {
        case .claude:
            return nil
        case .codex:
            return extractedCodexResponse(from: raw)
        case .gemini:
            return extractedGeminiResponse(from: raw)
        case .openclaw:
            return extractedOpenclawPayloadText(from: raw)
        }
    }

    private func extractedCodexResponse(from raw: String) -> String? {
        if let jsonObject = extractedJSONObject(from: raw),
           let data = try? JSONSerialization.data(withJSONObject: jsonObject, options: []),
           let text = String(data: data, encoding: .utf8) {
            return text
        }

        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let fenced = strippedMarkdownCodeFence(from: trimmed) {
            return fenced
        }

        let lines = raw
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return lines.last
    }

    private func extractedGeminiResponse(from raw: String) -> String? {
        guard
            let object = extractedJSONObject(from: raw),
            let response = object["response"] as? String
        else {
            return nil
        }

        return response.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func extractedOpenclawPayloadText(from raw: String) -> String? {
        guard
            let object = extractedJSONObject(from: raw),
            let payloads = object["payloads"] as? [[String: Any]],
            let firstPayload = payloads.first,
            let text = firstPayload["text"] as? String
        else {
            return nil
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func extractedJSONObject(from raw: String) -> [String: Any]? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let indices = trimmed.indices.filter { trimmed[$0] == "{" }
        for index in indices {
            let candidate = String(trimmed[index...])
            guard let data = candidate.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                continue
            }

            return object
        }

        return nil
    }

    private func normalizedAcknowledgement(from raw: String) -> String? {
        let normalized = raw
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".!?"))

        guard !normalized.isEmpty else {
            return nil
        }

        switch normalized {
        case "ok", "okay":
            return normalized
        default:
            return nil
        }
    }

    private func normalizedStoryJSONText(from raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        if let fenced = strippedMarkdownCodeFence(from: trimmed) {
            return fenced
        }

        return trimmed
    }

    private func strippedMarkdownCodeFence(from raw: String) -> String? {
        let lines = raw.components(separatedBy: .newlines)
        guard
            lines.count >= 3,
            let firstLine = lines.first?.trimmingCharacters(in: .whitespacesAndNewlines),
            firstLine.hasPrefix("```"),
            let lastLine = lines.last?.trimmingCharacters(in: .whitespacesAndNewlines),
            lastLine == "```"
        else {
            return nil
        }

        return lines.dropFirst().dropLast().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isValidDailyStoryPayload(_ value: Any) -> Bool {
        guard let object = value as? [String: Any],
              object.keys.count == 1,
              let sections = object["sections"] as? [Any],
              !sections.isEmpty
        else {
            return false
        }

        return sections.allSatisfy { sectionValue in
            guard let section = sectionValue as? [String: Any],
                  section.keys.count == 2,
                  let id = section["id"] as? String,
                  id == "daily-journal",
                  let paragraphs = section["paragraphs"] as? [Any],
                  !paragraphs.isEmpty,
                  paragraphs.count <= 4
            else {
                return false
            }

            return paragraphs.allSatisfy { paragraphValue in
                guard let paragraph = paragraphValue as? [String: Any],
                      paragraph.keys.count == 2,
                      let text = paragraph["text"] as? String,
                      !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      let sourceEventIDs = paragraph["sourceEventIDs"] as? [Any],
                      !sourceEventIDs.isEmpty
                else {
                    return false
                }

                return sourceEventIDs.allSatisfy { sourceValue in
                    guard let sourceID = sourceValue as? String else {
                        return false
                    }

                    return UUID(uuidString: sourceID) != nil
                }
            }
        }
    }
}
