import Foundation

protocol CodexCredentialProviding: Sendable {
    func validCredential() async throws -> CodexOAuthCredential
}

struct CodexCredentialProvider: CodexCredentialProviding {
    let store: CodexAuthStore
    let refresher: CodexOAuthRefresher
    let refreshLeeway: TimeInterval
    let now: @Sendable () -> Date

    init(
        store: CodexAuthStore = CodexAuthStore(),
        refresher: CodexOAuthRefresher = CodexOAuthRefresher(),
        refreshLeeway: TimeInterval = 300,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.store = store
        self.refresher = refresher
        self.refreshLeeway = refreshLeeway
        self.now = now
    }

    func validCredential() async throws -> CodexOAuthCredential {
        let credential = try store.readCredential()
        guard credential.expiresAt.timeIntervalSince(now()) <= refreshLeeway else {
            return credential
        }

        return try await refresher.refresh(credential, using: store)
    }
}

enum CodexDirectSummarizerError: Error, LocalizedError, Equatable {
    case requestFailed
    case invalidResponse
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .requestFailed:
            return "Codex Auth request failed. Sign in with Codex CLI, then retest Codex Auth."
        case .invalidResponse:
            return "Codex Auth returned an invalid response."
        case .emptyResponse:
            return "Codex Auth response did not include any text."
        }
    }
}

struct CodexDirectSummarizer: IncrementalSummaryGenerating, JSONSummaryGenerating {
    static let apiURL = URL(string: "https://chatgpt.com/backend-api/codex/responses")!

    let credentialProvider: any CodexCredentialProviding
    let session: URLSession
    let model: String
    let instructions: String

    init(
        credentialProvider: any CodexCredentialProviding = CodexCredentialProvider(),
        session: URLSession = .shared,
        model: String = "gpt-5.4",
        instructions: String = "You are a careful diary summarizer. Return concise, useful diary text."
    ) {
        self.credentialProvider = credentialProvider
        self.session = session
        self.model = model
        self.instructions = instructions
    }

    func summarize(dayKey: String, markdown: String, context: SummaryInvocationContext) async throws -> String {
        try await sendRequest(
            input: "Summarize this day as a concise diary entry for \(dayKey):\n\n\(markdown)"
        )
    }

    func summarizeIncremental(
        dayKey: String,
        markdown: String,
        context: SummaryInvocationContext
    ) async throws -> String {
        try await sendRequest(input: markdown)
    }

    func summarizeJSON(
        dayKey: String,
        prompt: String,
        schema: String,
        context: SummaryInvocationContext
    ) async throws -> String {
        let input = """
        Generate JSON for \(dayKey).

        JSON schema:
        \(schema)

        Prompt:
        \(prompt)
        """
        return try await sendRequest(
            input: [
                CodexResponsesInputMessage(role: "user", content: input)
            ],
            instructions: "You are a careful structured JSON generator. Return only valid JSON that matches the provided schema. Do not include markdown fences, commentary, or diary-style wrapper text.",
            options: LLMCompletionOptions()
        )
    }

    func smokeTest(prompt: String? = nil) async throws -> String {
        try await sendRequest(input: prompt ?? "Reply with OK.")
    }

    private func sendRequest(input: String) async throws -> String {
        try await sendRequest(
            input: [CodexResponsesInputMessage(role: "user", content: input)],
            instructions: instructions,
            options: LLMCompletionOptions()
        )
    }

    private func sendRequest(
        input: [CodexResponsesInputMessage],
        instructions: String,
        options: LLMCompletionOptions
    ) async throws -> String {
        let credential = try await credentialProvider.validCredential()
        var request = URLRequest(url: Self.apiURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(credential.accountID, forHTTPHeaderField: "chatgpt-account-id")
        request.setValue("pi", forHTTPHeaderField: "originator")
        request.setValue("responses=experimental", forHTTPHeaderField: "OpenAI-Beta")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            CodexResponsesRequest(
                model: model,
                instructions: instructions,
                input: input,
                temperature: options.temperature,
                maxOutputTokens: options.maxTokens,
                reasoningOptions: options.reasoning
            )
        )

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw CodexDirectSummarizerError.requestFailed
        }

        guard
            let httpResponse = response as? HTTPURLResponse,
            (200..<300).contains(httpResponse.statusCode)
        else {
            throw CodexDirectSummarizerError.requestFailed
        }

        return try parseResponse(data)
    }

    private func parseResponse(_ data: Data) throws -> String {
        let body = String(decoding: data, as: UTF8.self)
        var sawSSEPayload = false
        var deltaParts: [String] = []
        for event in body.components(separatedBy: "\n\n") {
            let payload = event
                .split(separator: "\n")
                .compactMap { line -> String? in
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    guard trimmed.hasPrefix("data:") else {
                        return nil
                    }
                    return String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                }
                .joined(separator: "\n")

            guard !payload.isEmpty, payload != "[DONE]" else {
                continue
            }

            sawSSEPayload = true
            let parsedEvent = try parseEventPayload(Data(payload.utf8))
            if parsedEvent.isFinal, !parsedEvent.text.isEmpty {
                return parsedEvent.text
            }
            if !parsedEvent.text.isEmpty {
                deltaParts.append(parsedEvent.text)
            }
        }

        let deltaText = deltaParts.joined().trimmingCharacters(in: .whitespacesAndNewlines)
        if !deltaText.isEmpty {
            return deltaText
        }
        if sawSSEPayload {
            throw CodexDirectSummarizerError.emptyResponse
        }

        let direct = try JSONDecoder().decode(ResponsesResponse.self, from: data)
        guard let text = direct.outputText?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            throw CodexDirectSummarizerError.emptyResponse
        }
        return text
    }

    private func parseEventPayload(_ data: Data) throws -> ParsedCodexResponseEvent {
        let event: CodexResponseEvent
        do {
            event = try JSONDecoder().decode(CodexResponseEvent.self, from: data)
        } catch {
            throw CodexDirectSummarizerError.invalidResponse
        }

        if let type = event.type?.lowercased(), type.contains("error") || type.contains("failed") {
            throw CodexDirectSummarizerError.requestFailed
        }

        if let text = event.response?.outputText ?? event.outputText {
            return ParsedCodexResponseEvent(
                text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                isFinal: true
            )
        }

        return ParsedCodexResponseEvent(
            text: event.delta ?? "",
            isFinal: false
        )
    }
}

extension CodexDirectSummarizer: MyWikiLLMCompleting {
    func complete(messages: [MyWikiLLMMessage], options: LLMCompletionOptions) async throws -> String {
        let input = messages.codexNonSystemInputMessages
        return try await sendRequest(
            input: input.isEmpty ? [CodexResponsesInputMessage(role: "user", content: "")] : input,
            instructions: messages.myWikiSystemPrompt ?? instructions,
            options: options
        )
    }
}

private struct ParsedCodexResponseEvent {
    let text: String
    let isFinal: Bool
}

private struct CodexResponsesRequest: Encodable {
    let model: String
    let instructions: String
    let input: [CodexResponsesInputMessage]
    let temperature: Double?
    let maxOutputTokens: Int?
    let store = false
    let stream = true
    let text = CodexResponsesTextOptions(verbosity: "medium")
    let include: [String]?
    let toolChoice = "auto"
    let parallelToolCalls = true
    let reasoning: CodexResponsesReasoningOptions?

    init(
        model: String,
        instructions: String,
        input: [CodexResponsesInputMessage],
        temperature: Double?,
        maxOutputTokens: Int?,
        reasoningOptions: LLMReasoningOptions?
    ) {
        self.model = model
        self.instructions = instructions
        self.input = input
        self.temperature = temperature
        self.maxOutputTokens = maxOutputTokens

        let mode = reasoningOptions?.mode
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if mode == "off" {
            include = nil
            reasoning = nil
        } else {
            include = ["reasoning.encrypted_content"]
            reasoning = CodexResponsesReasoningOptions(summary: "auto")
        }
    }

    enum CodingKeys: String, CodingKey {
        case model
        case instructions
        case input
        case temperature
        case maxOutputTokens = "max_output_tokens"
        case store
        case stream
        case text
        case include
        case toolChoice = "tool_choice"
        case parallelToolCalls = "parallel_tool_calls"
        case reasoning
    }
}

private struct CodexResponsesInputMessage: Encodable {
    let role: String
    let content: String
}

private extension Array where Element == MyWikiLLMMessage {
    var codexNonSystemInputMessages: [CodexResponsesInputMessage] {
        filter { !$0.codexIsSystemMessage }
            .map { CodexResponsesInputMessage(role: $0.codexInputRole, content: $0.content) }
    }
}

private extension MyWikiLLMMessage {
    var codexIsSystemMessage: Bool {
        role.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "system"
    }

    var codexInputRole: String {
        let normalized = role.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "assistant" ? "assistant" : "user"
    }
}

private struct CodexResponsesTextOptions: Encodable {
    let verbosity: String
}

private struct CodexResponsesReasoningOptions: Encodable {
    let summary: String
}

private struct CodexResponseEvent: Decodable {
    let type: String?
    let response: ResponsesResponse?
    let outputText: String?
    let delta: String?

    enum CodingKeys: String, CodingKey {
        case type
        case response
        case outputText = "output_text"
        case delta
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decodeIfPresent(String.self, forKey: .type)
        response = try? container.decodeIfPresent(ResponsesResponse.self, forKey: .response)
        outputText = try container.decodeIfPresent(String.self, forKey: .outputText)
        delta = try container.decodeIfPresent(String.self, forKey: .delta)
    }
}
