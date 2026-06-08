import Foundation

enum SummaryInvocationContext: Sendable, Equatable {
    case manualRefresh
    case automationRefresh
    case defaultBehavior
}

protocol SummaryGenerating: Sendable {
    func summarize(dayKey: String, markdown: String, context: SummaryInvocationContext) async throws -> String
}

protocol JSONSummaryGenerating: SummaryGenerating {
    func summarizeJSON(
        dayKey: String,
        prompt: String,
        schema: String,
        context: SummaryInvocationContext
    ) async throws -> String
}

protocol IncrementalSummaryGenerating: SummaryGenerating {
    func summarizeIncremental(dayKey: String, markdown: String, context: SummaryInvocationContext) async throws -> String
}

extension SummaryGenerating {
    func summarize(dayKey: String, markdown: String) async throws -> String {
        try await summarize(dayKey: dayKey, markdown: markdown, context: .defaultBehavior)
    }

    func summarizeIncremental(
        dayKey: String,
        markdown: String,
        context: SummaryInvocationContext
    ) async throws -> String {
        if let incrementalSummarizer = self as? any IncrementalSummaryGenerating {
            return try await incrementalSummarizer.summarizeIncremental(
                dayKey: dayKey,
                markdown: markdown,
                context: context
            )
        }

        return try await summarize(dayKey: dayKey, markdown: markdown, context: context)
    }
}

struct CloudSummarizer: IncrementalSummaryGenerating {
    let providerConfig: LLMAPIProviderConfig
    let session: URLSession

    var apiKey: String { providerConfig.apiToken }
    var apiURL: URL { providerConfig.validatedBaseURL() ?? URL(string: "https://api.openai.com/v1/responses")! }
    var model: String { providerConfig.model }

    init(
        apiKey: String,
        apiURL: URL = URL(string: "https://api.openai.com/v1/responses")!,
        session: URLSession = .shared,
        model: String = "gpt-5"
    ) {
        self.providerConfig = LLMAPIProviderConfig(
            id: .openAI,
            baseURL: apiURL.absoluteString,
            model: model,
            wireFormat: .openAIResponses,
            apiToken: apiKey
        )
        self.session = session
    }

    init(
        providerConfig: LLMAPIProviderConfig,
        session: URLSession = .shared
    ) {
        self.providerConfig = providerConfig
        self.session = session
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

    private func sendRequest(input: String) async throws -> String {
        let client = LLMAPIClient(providerConfig: providerConfig, session: session)
        let outputText = try await client.complete(input: input)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return outputText.isEmpty ? "Summary unavailable." : outputText
    }
}

extension CloudSummarizer: MyWikiLLMCompleting {
    func complete(messages: [MyWikiLLMMessage], options: LLMCompletionOptions) async throws -> String {
        try await LLMAPIClient(providerConfig: providerConfig, session: session)
            .complete(
                input: messages.myWikiNonSystemTranscript,
                systemPrompt: messages.myWikiSystemPrompt,
                options: options
            )
    }
}

enum LLMAPIClientError: Error, LocalizedError, Equatable, Sendable {
    case nonSuccessStatus(statusCode: Int, responseBody: String)

    var errorDescription: String? {
        switch self {
        case .nonSuccessStatus(let statusCode, let responseBody):
            let body = responseBody.trimmingCharacters(in: .whitespacesAndNewlines)
            return body.isEmpty
                ? "LLM API request failed with HTTP \(statusCode)."
                : "LLM API request failed with HTTP \(statusCode): \(body)"
        }
    }

    var isAuthenticationFailure: Bool {
        switch self {
        case .nonSuccessStatus(let statusCode, _):
            return statusCode == 401 || statusCode == 403
        }
    }
}

struct LLMAPIClient: Sendable {
    let providerConfig: LLMAPIProviderConfig
    let session: URLSession

    init(providerConfig: LLMAPIProviderConfig, session: URLSession = .shared) {
        self.providerConfig = providerConfig
        self.session = session
    }

    func complete(
        input: String,
        systemPrompt: String? = nil,
        options: LLMCompletionOptions = LLMCompletionOptions()
    ) async throws -> String {
        let request = try makeRequest(input: input, systemPrompt: systemPrompt, options: options)
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw LLMAPIClientError.nonSuccessStatus(
                statusCode: httpResponse.statusCode,
                responseBody: String(decoding: data, as: UTF8.self)
            )
        }

        return try decodeText(from: data)
    }

    private func makeRequest(
        input: String,
        systemPrompt: String?,
        options: LLMCompletionOptions
    ) throws -> URLRequest {
        let endpointURL = try endpointURL()
        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        switch providerConfig.wireFormat {
        case .openAIResponses:
            request.addValue("Bearer \(providerConfig.apiToken)", forHTTPHeaderField: "Authorization")
            let trimmedSystemPrompt = systemPrompt?.trimmingCharacters(in: .whitespacesAndNewlines)
            request.httpBody = try JSONEncoder().encode(
                ResponsesRequest(
                    model: providerConfig.model,
                    input: input,
                    instructions: trimmedSystemPrompt?.isEmpty == false ? trimmedSystemPrompt : nil,
                    temperature: options.temperature,
                    maxOutputTokens: options.maxTokens
                )
            )
        case .openAIChat:
            request.addValue("Bearer \(providerConfig.apiToken)", forHTTPHeaderField: "Authorization")
            var messages: [OpenAIChatMessage] = []
            if let systemPrompt, !systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                messages.append(OpenAIChatMessage(role: "system", content: systemPrompt))
            }
            messages.append(OpenAIChatMessage(role: "user", content: input))
            request.httpBody = try JSONEncoder().encode(
                OpenAIChatRequest(
                    model: providerConfig.model,
                    messages: messages,
                    stream: false,
                    temperature: options.temperature,
                    maxTokens: options.maxTokens,
                    thinking: deepSeekThinkingOptions(for: options),
                    chatTemplateKwargs: qwenChatTemplateKwargs(for: options)
                )
            )
        case .anthropicMessages:
            request.addValue(providerConfig.apiToken, forHTTPHeaderField: "x-api-key")
            request.addValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            let trimmedSystemPrompt = systemPrompt?.trimmingCharacters(in: .whitespacesAndNewlines)
            request.httpBody = try JSONEncoder().encode(
                AnthropicMessagesRequest(
                    model: providerConfig.model,
                    maxTokens: options.maxTokens ?? 4096,
                    temperature: options.temperature,
                    system: trimmedSystemPrompt?.isEmpty == false ? trimmedSystemPrompt : nil,
                    messages: [
                        AnthropicMessage(role: "user", content: input)
                    ]
                )
            )
        case .geminiGenerateContent:
            request.addValue(providerConfig.apiToken, forHTTPHeaderField: "x-goog-api-key")
            let trimmedSystemPrompt = systemPrompt?.trimmingCharacters(in: .whitespacesAndNewlines)
            request.httpBody = try JSONEncoder().encode(
                GeminiGenerateContentRequest(
                    contents: [
                        GeminiContent(
                            role: "user",
                            parts: [GeminiPart(text: input)]
                        )
                    ],
                    systemInstruction: trimmedSystemPrompt?.isEmpty == false
                        ? GeminiSystemInstruction(parts: [GeminiPart(text: trimmedSystemPrompt ?? "")])
                        : nil,
                    generationConfig: GeminiGenerationConfig(
                        temperature: options.temperature,
                        maxOutputTokens: options.maxTokens,
                        thinkingConfig: geminiThinkingConfig(for: options)
                    ).nonEmpty
                )
            )
        }

        return request
    }

    private func endpointURL() throws -> URL {
        guard let baseURL = providerConfig.validatedBaseURL() else {
            throw URLError(.badURL)
        }

        switch providerConfig.wireFormat {
        case .openAIResponses:
            if baseURL.path.hasSuffix("/responses") {
                return baseURL
            }
            return baseURL.appendingPathComponent("responses")
        case .openAIChat:
            if baseURL.path.hasSuffix("/chat/completions") {
                return baseURL
            }
            return baseURL.appendingPathComponent("chat/completions")
        case .anthropicMessages:
            if baseURL.path.hasSuffix("/messages") {
                return baseURL
            }
            return baseURL.appendingPathComponent("messages")
        case .geminiGenerateContent:
            let encodedModel = providerConfig.model.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
                ?? providerConfig.model
            return baseURL
                .appendingPathComponent("models")
                .appendingPathComponent("\(encodedModel):generateContent")
        }
    }

    private func decodeText(from data: Data) throws -> String {
        switch providerConfig.wireFormat {
        case .openAIResponses:
            let payload = try JSONDecoder().decode(ResponsesResponse.self, from: data)
            return payload.outputText ?? ""
        case .openAIChat:
            let payload = try JSONDecoder().decode(OpenAIChatResponse.self, from: data)
            return payload.choices.first?.message.content ?? ""
        case .anthropicMessages:
            let payload = try JSONDecoder().decode(AnthropicMessagesResponse.self, from: data)
            return payload.content.compactMap { content in
                content.type == "text" ? content.text : nil
            }
            .joined(separator: "\n")
        case .geminiGenerateContent:
            let payload = try JSONDecoder().decode(GeminiGenerateContentResponse.self, from: data)
            return payload.candidates
                .flatMap { $0.content.parts }
                .compactMap(\.text)
                .joined(separator: "\n")
        }
    }

    private func reasoningMode(for options: LLMCompletionOptions) -> String? {
        options.reasoning?.mode
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func reasoningIsOff(_ options: LLMCompletionOptions) -> Bool {
        reasoningMode(for: options) == "off"
    }

    private func deepSeekThinkingOptions(for options: LLMCompletionOptions) -> OpenAIChatThinkingOptions? {
        guard reasoningIsOff(options) else {
            return nil
        }
        let baseURL = providerConfig.baseURL.lowercased()
        let model = providerConfig.model.lowercased()
        guard providerConfig.id == .deepSeek || model.contains("deepseek") || baseURL.contains("deepseek") else {
            return nil
        }
        return OpenAIChatThinkingOptions(type: "disabled")
    }

    private func qwenChatTemplateKwargs(for options: LLMCompletionOptions) -> OpenAIChatTemplateKwargs? {
        guard reasoningIsOff(options) else {
            return nil
        }
        let normalizedModel = providerConfig.model
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
        guard normalizedModel.contains("qwen3") else {
            return nil
        }
        return OpenAIChatTemplateKwargs(enableThinking: false)
    }

    private func geminiThinkingConfig(for options: LLMCompletionOptions) -> GeminiThinkingConfig? {
        guard reasoningIsOff(options) else {
            return nil
        }
        return GeminiThinkingConfig(thinkingBudget: 0)
    }
}

extension CLISummarizer: IncrementalSummaryGenerating {}

private struct ResponsesRequest: Encodable {
    let model: String
    let input: String
    let instructions: String?
    let temperature: Double?
    let maxOutputTokens: Int?

    enum CodingKeys: String, CodingKey {
        case model
        case input
        case instructions
        case temperature
        case maxOutputTokens = "max_output_tokens"
    }
}

private struct OpenAIChatRequest: Encodable {
    let model: String
    let messages: [OpenAIChatMessage]
    let stream: Bool
    let temperature: Double?
    let maxTokens: Int?
    let thinking: OpenAIChatThinkingOptions?
    let chatTemplateKwargs: OpenAIChatTemplateKwargs?

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case stream
        case temperature
        case maxTokens = "max_tokens"
        case thinking
        case chatTemplateKwargs = "chat_template_kwargs"
    }
}

private struct OpenAIChatThinkingOptions: Encodable {
    let type: String
}

private struct OpenAIChatTemplateKwargs: Encodable {
    let enableThinking: Bool

    enum CodingKeys: String, CodingKey {
        case enableThinking = "enable_thinking"
    }
}

private struct OpenAIChatMessage: Encodable {
    let role: String
    let content: String
}

private struct OpenAIChatResponse: Decodable {
    let choices: [OpenAIChatChoice]
}

private struct OpenAIChatChoice: Decodable {
    let message: OpenAIChatResponseMessage
}

private struct OpenAIChatResponseMessage: Decodable {
    let content: String
}

private struct AnthropicMessagesRequest: Encodable {
    let model: String
    let maxTokens: Int
    let temperature: Double?
    let system: String?
    let messages: [AnthropicMessage]

    enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
        case temperature
        case system
        case messages
    }
}

private struct AnthropicMessage: Encodable {
    let role: String
    let content: String
}

private struct AnthropicMessagesResponse: Decodable {
    let content: [AnthropicContent]
}

private struct AnthropicContent: Decodable {
    let type: String
    let text: String?
}

private struct GeminiGenerateContentRequest: Encodable {
    let contents: [GeminiContent]
    let systemInstruction: GeminiSystemInstruction?
    let generationConfig: GeminiGenerationConfig?

    enum CodingKeys: String, CodingKey {
        case contents
        case systemInstruction = "system_instruction"
        case generationConfig = "generation_config"
    }
}

private struct GeminiGenerationConfig: Encodable {
    let temperature: Double?
    let maxOutputTokens: Int?
    let thinkingConfig: GeminiThinkingConfig?

    var nonEmpty: GeminiGenerationConfig? {
        temperature == nil && maxOutputTokens == nil && thinkingConfig == nil ? nil : self
    }

    enum CodingKeys: String, CodingKey {
        case temperature
        case maxOutputTokens = "max_output_tokens"
        case thinkingConfig = "thinking_config"
    }
}

private struct GeminiThinkingConfig: Encodable {
    let thinkingBudget: Int

    enum CodingKeys: String, CodingKey {
        case thinkingBudget = "thinking_budget"
    }
}

private struct GeminiContent: Codable {
    let role: String?
    let parts: [GeminiPart]
}

private struct GeminiSystemInstruction: Codable {
    let parts: [GeminiPart]
}

private struct GeminiPart: Codable {
    let text: String?
}

private struct GeminiGenerateContentResponse: Decodable {
    let candidates: [GeminiCandidate]
}

private struct GeminiCandidate: Decodable {
    let content: GeminiContent
}

struct ResponsesResponse: Decodable {
    let outputText: String?
    let output: [ResponseOutputItem]?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let directOutputText = try container.decodeIfPresent(String.self, forKey: .outputText)
        let output = try container.decodeIfPresent([ResponseOutputItem].self, forKey: .output)
        self.output = output
        if let directOutputText {
            self.outputText = directOutputText
        } else {
            let textParts = output?
                .filter { $0.type == "message" }
                .flatMap { item in item.content ?? [] }
                .filter { $0.type == "output_text" }
                .compactMap { $0.text }
            self.outputText = textParts?.joined(separator: "\n")
        }
    }

    enum CodingKeys: String, CodingKey {
        case outputText = "output_text"
        case output
    }
}

struct ResponseOutputItem: Decodable {
    let type: String
    let content: [ResponseOutputContent]?
}

struct ResponseOutputContent: Decodable {
    let type: String
    let text: String?
}
