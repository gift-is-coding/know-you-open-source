import Foundation

struct ProcessExecutionResult: Sendable {
    let stdout: String
    let stderr: String
    let terminationStatus: Int32
    let duration: TimeInterval
}

protocol ProcessRunning: Sendable {
    func run(executable: String, arguments: [String], timeoutSeconds: Int) async throws -> ProcessExecutionResult
}

enum ProcessRunError: Error {
    case timedOut(seconds: Int)
}

enum CLISummarizerError: Error, LocalizedError, Equatable {
    case timedOut(seconds: Int)
    case nonZeroExit(status: Int32, detail: String)
    case emptyOutput
    case invalidStructuredOutput
    case repairFailed(detail: String)

    var errorDescription: String? {
        switch self {
        case .timedOut(let seconds):
            return "Summarizer CLI timed out after \(seconds)s"
        case .nonZeroExit(let status, let detail):
            return detail.isEmpty
                ? "Summarizer CLI exited with status \(status)"
                : "Summarizer CLI exited with status \(status): \(detail)"
        case .emptyOutput:
            return "Summarizer CLI returned empty output"
        case .invalidStructuredOutput:
            return "Story output was not valid structured JSON"
        case .repairFailed(let detail):
            return "Structured repair failed: \(detail)"
        }
    }
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
    private let environment: [String: String]

    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.environment = environment
    }

    func run(executable: String, arguments: [String], timeoutSeconds: Int) async throws -> ProcessExecutionResult {
        let controller = ProcessCancellationController()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global().async {
                    let gate = ContinuationGate<ProcessExecutionResult>()
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: executable)
                    process.arguments = arguments
                    process.environment = processEnvironment(for: executable)
                    controller.attach(process)

                    if controller.isCancelled {
                        let error = CancellationError()
                        guard gate.resume(throwing: error) else { return }
                        continuation.resume(throwing: error)
                        return
                    }

                    let outputPipe = Pipe()
                    let errorPipe = Pipe()
                    process.standardOutput = outputPipe
                    process.standardError = errorPipe

                    let start = Date()
                    let timeoutItem = DispatchWorkItem {
                        controller.terminate()
                        let error = ProcessRunError.timedOut(seconds: timeoutSeconds)
                        guard gate.resume(throwing: error) else { return }
                        continuation.resume(throwing: error)
                    }
                    DispatchQueue.global().asyncAfter(deadline: .now() + Double(timeoutSeconds), execute: timeoutItem)

                    do {
                        try process.run()
                        if controller.isCancelled {
                            process.terminate()
                        }
                        process.waitUntilExit()
                        timeoutItem.cancel()
                        if controller.isCancelled {
                            let error = CancellationError()
                            guard gate.resume(throwing: error) else { return }
                            continuation.resume(throwing: error)
                            return
                        }
                        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                        let result = ProcessExecutionResult(
                            stdout: String(decoding: outputData, as: UTF8.self),
                            stderr: String(decoding: errorData, as: UTF8.self),
                            terminationStatus: process.terminationStatus,
                            duration: Date().timeIntervalSince(start)
                        )
                        guard gate.resume(returning: result) else { return }
                        continuation.resume(returning: result)
                    } catch {
                        timeoutItem.cancel()
                        guard gate.resume(throwing: error) else { return }
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            controller.cancel()
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

private final class ProcessCancellationController: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false

    var isCancelled: Bool {
        lock.withLock { cancelled }
    }

    func attach(_ process: Process) {
        let shouldTerminate = lock.withLock {
            self.process = process
            return cancelled
        }
        if shouldTerminate {
            process.terminate()
        }
    }

    func cancel() {
        let process = lock.withLock {
            cancelled = true
            return self.process
        }
        process?.terminate()
    }

    func terminate() {
        lock.withLock {
            process?.terminate()
        }
    }
}

struct CLISummarizer: SummaryGenerating {
    enum Tool: String, Sendable {
        case claude
        case codex
        case gemini
        case openclaw
    }

    private enum Expectation {
        case story
        case incrementalUpdate
        case acknowledgement
    }

    private struct InvocationPlan {
        let arguments: [String]
        let schemaURL: URL?
        let outputURL: URL?
    }

    let tool: Tool
    let executablePath: String
    let runner: ProcessRunning

    private static let manualPrimaryTimeoutSeconds = 600
    private static let automationPrimaryTimeoutSeconds = 300
    private static let manualRepairTimeoutSeconds = 120
    private static let automationRepairTimeoutSeconds = 60
    private static let dailyStorySchema = """
    {"type":"object","additionalProperties":false,"required":["sections"],"properties":{"sections":{"type":"array","items":{"type":"object","additionalProperties":false,"required":["id","paragraphs"],"properties":{"id":{"type":"string","const":"daily-journal"},"paragraphs":{"type":"array","minItems":1,"items":{"type":"object","additionalProperties":false,"required":["text","sourceEventIDs"],"properties":{"text":{"type":"string"},"sourceEventIDs":{"type":"array","minItems":1,"items":{"type":"string","pattern":"^[0-9A-Fa-f-]{36}$"}}}}}}}}}}
    """
    private static let acknowledgementSchema = """
    {"type":"object","additionalProperties":false,"required":["ok"],"properties":{"ok":{"type":"string","const":"OK"}}}
    """
    private static let incrementalUpdateSchema = """
    {"type":"object","additionalProperties":false,"required":["encouragementToReplace","summaryBulletsToReplace","detailBlocksToAppend","todoItemsToReplace"],"properties":{"encouragementToReplace":{"type":"object","additionalProperties":false,"required":["text","sourceEventIDs"],"properties":{"text":{"type":"string"},"sourceEventIDs":{"type":"array","minItems":1,"items":{"type":"string","pattern":"^[0-9A-Fa-f-]{36}$"}}}},"summaryBulletsToReplace":{"type":"array","items":{"type":"object","additionalProperties":false,"required":["text","sourceEventIDs"],"properties":{"text":{"type":"string"},"sourceEventIDs":{"type":"array","minItems":1,"items":{"type":"string","pattern":"^[0-9A-Fa-f-]{36}$"}}}}},"detailBlocksToAppend":{"type":"array","items":{"type":"object","additionalProperties":false,"required":["text","sourceEventIDs"],"properties":{"text":{"type":"string"},"sourceEventIDs":{"type":"array","minItems":1,"items":{"type":"string","pattern":"^[0-9A-Fa-f-]{36}$"}}}}},"todoItemsToReplace":{"type":"array","items":{"type":"object","additionalProperties":false,"required":["text","sourceEventIDs"],"properties":{"text":{"type":"string"},"sourceEventIDs":{"type":"array","minItems":1,"items":{"type":"string","pattern":"^[0-9A-Fa-f-]{36}$"}}}}}}}
    """

    init(tool: Tool, executablePath: String, runner: ProcessRunning = SystemProcessRunner()) {
        self.tool = tool
        self.executablePath = executablePath
        self.runner = runner
    }

    func summarize(dayKey: String, markdown: String, context: SummaryInvocationContext) async throws -> String {
        try await summarizeStructured(prompt: markdown, expectation: .story, context: context)
    }

    func summarizeIncremental(
        dayKey: String,
        markdown: String,
        context: SummaryInvocationContext
    ) async throws -> String {
        try await summarizeStructured(prompt: markdown, expectation: .incrementalUpdate, context: context)
    }

    func smokeTest(prompt: String? = nil) async throws -> String {
        switch tool {
        case .claude:
            let raw = try await run(
                prompt: prompt ?? "Return a minimal valid JSON object that matches the daily story schema.",
                expectation: .story,
                timeoutSeconds: Self.automationPrimaryTimeoutSeconds
            )
            guard let validated = validatedStoryOutput(from: raw) else {
                throw CLISummarizerError.invalidStructuredOutput
            }
            return validated
        case .codex:
            let raw = try await run(
                prompt: prompt ?? "Reply with OK.",
                expectation: .acknowledgement,
                timeoutSeconds: Self.automationPrimaryTimeoutSeconds
            )
            if let acknowledged = normalizedAcknowledgement(from: raw) {
                return acknowledged.uppercased()
            }
            if let object = extractedJSONObject(from: raw),
               let ok = object["ok"] as? String,
               normalizedAcknowledgement(from: ok) != nil {
                return "OK"
            }
            throw CLISummarizerError.invalidStructuredOutput
        case .gemini, .openclaw:
            let raw = try await run(
                prompt: prompt ?? "Reply with OK.",
                expectation: .acknowledgement,
                timeoutSeconds: Self.automationPrimaryTimeoutSeconds
            )
            guard let acknowledged = normalizedAcknowledgement(from: raw) else {
                throw CLISummarizerError.invalidStructuredOutput
            }
            return acknowledged.uppercased()
        }
    }

    private func run(
        prompt: String,
        expectation: Expectation,
        timeoutSeconds: Int
    ) async throws -> String {
        let plan = try makeInvocationPlan(prompt: prompt, expectation: expectation, timeoutSeconds: timeoutSeconds)
        defer {
            if let schemaURL = plan.schemaURL {
                try? FileManager.default.removeItem(at: schemaURL)
            }
            if let outputURL = plan.outputURL {
                try? FileManager.default.removeItem(at: outputURL)
            }
        }

        let executionResult: ProcessExecutionResult
        do {
            executionResult = try await runner.run(
                executable: executablePath,
                arguments: plan.arguments,
                timeoutSeconds: timeoutSeconds
            )
        } catch let error as ProcessRunError {
            switch error {
            case .timedOut(let seconds):
                throw CLISummarizerError.timedOut(seconds: seconds)
            }
        } catch {
            throw error
        }

        let detail = failureDetail(for: executionResult)
        guard executionResult.terminationStatus == 0 else {
            throw CLISummarizerError.nonZeroExit(status: executionResult.terminationStatus, detail: detail)
        }

        if let outputURL = plan.outputURL,
           let fileOutput = try? String(contentsOf: outputURL, encoding: .utf8),
           !fileOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return fileOutput
        }

        let extracted = extractedTextOutput(from: executionResult.stdout)
            ?? executionResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return extracted
    }

    private func summarizeStructured(
        prompt: String,
        expectation: Expectation,
        context: SummaryInvocationContext
    ) async throws -> String {
        let primaryRaw = try await run(
            prompt: prompt,
            expectation: expectation,
            timeoutSeconds: primaryTimeoutSeconds(for: context)
        )
        if let validated = validatedOutput(from: primaryRaw, expectation: expectation) {
            return validated
        }

        guard !primaryRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CLISummarizerError.emptyOutput
        }

        do {
            let repaired = try await run(
                prompt: repairPrompt(for: primaryRaw, expectation: expectation),
                expectation: expectation,
                timeoutSeconds: repairTimeoutSeconds(for: context)
            )
            if let validated = validatedOutput(from: repaired, expectation: expectation) {
                return validated
            }
            throw CLISummarizerError.repairFailed(detail: "repair output was not valid structured JSON")
        } catch let error as CLISummarizerError {
            switch error {
            case .repairFailed:
                throw error
            default:
                throw CLISummarizerError.repairFailed(detail: error.localizedDescription)
            }
        } catch {
            throw CLISummarizerError.repairFailed(detail: error.localizedDescription)
        }
    }

    private func primaryTimeoutSeconds(for context: SummaryInvocationContext) -> Int {
        switch context {
        case .manualRefresh:
            return Self.manualPrimaryTimeoutSeconds
        case .automationRefresh, .defaultBehavior:
            return Self.automationPrimaryTimeoutSeconds
        }
    }

    private func repairTimeoutSeconds(for context: SummaryInvocationContext) -> Int {
        switch context {
        case .manualRefresh:
            return Self.manualRepairTimeoutSeconds
        case .automationRefresh, .defaultBehavior:
            return Self.automationRepairTimeoutSeconds
        }
    }

    private func makeInvocationPlan(
        prompt: String,
        expectation: Expectation,
        timeoutSeconds: Int
    ) throws -> InvocationPlan {
        switch tool {
        case .claude:
            return InvocationPlan(
                arguments: [
                    "-p", prompt,
                    "--output-format", "json",
                    "--json-schema", schemaText(for: expectation),
                ],
                schemaURL: nil,
                outputURL: nil
            )
        case .gemini:
            return InvocationPlan(
                arguments: [
                    "-p", prompt,
                    "--output-format", "json",
                ],
                schemaURL: nil,
                outputURL: nil
            )
        case .openclaw:
            return InvocationPlan(
                arguments: [
                    "agent",
                    "--agent", "main",
                    "--message", prompt,
                    "--local",
                    "--json",
                ],
                schemaURL: nil,
                outputURL: nil
            )
        case .codex:
            let schemaURL = try writeTemporaryFile(contents: schemaText(for: expectation))
            let outputURL = temporaryFileURL()
            try "".write(to: outputURL, atomically: true, encoding: .utf8)
            return InvocationPlan(
                arguments: [
                    "exec",
                    "--skip-git-repo-check",
                    "--ephemeral",
                    "--output-schema", schemaURL.path,
                    "-o", outputURL.path,
                    prompt,
                ],
                schemaURL: schemaURL,
                outputURL: outputURL
            )
        }
    }

    private func writeTemporaryFile(contents: String) throws -> URL {
        let url = temporaryFileURL()
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func temporaryFileURL() -> URL {
        URL.temporaryDirectory.appending(path: UUID().uuidString)
    }

    private func schemaText(for expectation: Expectation) -> String {
        switch expectation {
        case .story:
            return Self.dailyStorySchema
        case .incrementalUpdate:
            return Self.incrementalUpdateSchema
        case .acknowledgement:
            return Self.acknowledgementSchema
        }
    }

    private func repairPrompt(for raw: String, expectation: Expectation) -> String {
        switch expectation {
        case .story:
            return storyRepairPrompt(for: raw)
        case .incrementalUpdate:
            return incrementalRepairPrompt(for: raw)
        case .acknowledgement:
            return #"{"ok":"OK"}"#
        }
    }

    private func storyRepairPrompt(for raw: String) -> String {
        """
        Convert the following content into strict JSON only. Do not add markdown fences.

        Required JSON shape:
        {
          "sections": [
            { "id": "daily-journal", "paragraphs": [{ "text": "...", "sourceEventIDs": ["uuid"] }] }
          ]
        }

        Rules:
        - Preserve supported facts only.
        - Keep the section id exactly as "daily-journal".
        - Keep between 1 and 4 paragraphs.
        - Each paragraph must include at least one valid UUID string in sourceEventIDs.
        - Return JSON only.

        Content to repair:
        \(raw)
        """
    }

    private func incrementalRepairPrompt(for raw: String) -> String {
        """
        Convert the following content into strict JSON only. Do not add markdown fences.

        Required JSON shape:
        {
          "encouragementToReplace": {
            "text": "...",
            "sourceEventIDs": ["uuid"]
          },
          "summaryBulletsToReplace": [
            { "text": "...", "sourceEventIDs": ["uuid"] }
          ],
          "detailBlocksToAppend": [
            { "text": "...", "sourceEventIDs": ["uuid"] }
          ],
          "todoItemsToReplace": [
            { "text": "...", "sourceEventIDs": ["uuid"] }
          ]
        }

        Rules:
        - Preserve supported facts only.
        - Return all four top-level fields.
        - Do not use null for any field.
        - encouragementToReplace.text must be a non-empty string.
        - encouragementToReplace.sourceEventIDs must contain at least one valid UUID string.
        - summaryBulletsToReplace, detailBlocksToAppend, and todoItemsToReplace may be empty arrays.
        - Every item in those arrays must include non-empty text and at least one valid UUID string in sourceEventIDs.
        - Return JSON only.

        Content to repair:
        \(raw)
        """
    }

    private func failureDetail(for result: ProcessExecutionResult) -> String {
        let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if !stderr.isEmpty {
            return stderr
        }

        let stdout = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return stdout
    }

    private func validatedOutput(from raw: String, expectation: Expectation) -> String? {
        switch expectation {
        case .story:
            return validatedStoryOutput(from: raw)
        case .incrementalUpdate:
            return validatedIncrementalOutput(from: raw)
        case .acknowledgement:
            return normalizedAcknowledgement(from: raw) == nil ? nil : #"{"ok":"OK"}"#
        }
    }

    private func validatedStoryOutput(from raw: String) -> String? {
        switch tool {
        case .claude:
            return validatedClaudeStoryJSON(from: raw)
        case .codex, .gemini, .openclaw:
            if let extracted = extractedTextOutput(from: raw),
               let validated = validatedDailyStoryJSON(from: extracted) {
                return validated
            }
            return validatedDailyStoryJSON(from: raw)
        }
    }

    private func validatedIncrementalOutput(from raw: String) -> String? {
        switch tool {
        case .claude:
            if let structuredOutput = extractClaudeStructuredOutput(from: raw),
               let validatedStructuredOutput = validatedIncrementalUpdateJSON(from: structuredOutput) {
                return validatedStructuredOutput
            }
            return validatedIncrementalUpdateJSON(from: raw)
        case .codex, .gemini, .openclaw:
            if let extracted = extractedTextOutput(from: raw),
               let validated = validatedIncrementalUpdateJSON(from: extracted) {
                return validated
            }
            return validatedIncrementalUpdateJSON(from: raw)
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
                  !paragraphs.isEmpty
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

    private func validatedIncrementalUpdateJSON(from raw: String) -> String? {
        guard
            let normalized = normalizedStoryJSONText(from: raw),
            let data = normalized.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data),
            isValidIncrementalUpdatePayload(json),
            let serialized = try? JSONSerialization.data(withJSONObject: json, options: []),
            let text = String(data: serialized, encoding: .utf8)
        else {
            return nil
        }

        return text
    }

    private func isValidIncrementalUpdatePayload(_ value: Any) -> Bool {
        guard let object = value as? [String: Any],
              object.keys.count == 4,
              let encouragement = object["encouragementToReplace"] as? [String: Any],
              let summaryBullets = object["summaryBulletsToReplace"] as? [Any],
              let detailBlocks = object["detailBlocksToAppend"] as? [Any],
              let todoItems = object["todoItemsToReplace"] as? [Any]
        else {
            return false
        }

        return isValidIncrementalItem(encouragement)
            && isValidIncrementalItemArray(summaryBullets)
            && isValidIncrementalItemArray(detailBlocks)
            && isValidIncrementalItemArray(todoItems)
    }

    private func isValidIncrementalItemArray(_ values: [Any]) -> Bool {
        values.allSatisfy { value in
            guard let item = value as? [String: Any] else {
                return false
            }

            return isValidIncrementalItem(item)
        }
    }

    private func isValidIncrementalItem(_ value: [String: Any]) -> Bool {
        guard value.keys.count == 2,
              let text = value["text"] as? String,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let sourceEventIDs = value["sourceEventIDs"] as? [Any],
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
