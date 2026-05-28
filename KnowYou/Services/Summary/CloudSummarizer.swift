import Foundation

enum SummaryInvocationContext: Sendable, Equatable {
    case manualRefresh
    case automationRefresh
    case defaultBehavior
}

protocol SummaryGenerating: Sendable {
    func summarize(dayKey: String, markdown: String, context: SummaryInvocationContext) async throws -> String
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

struct LLMAPIClient: Sendable {
    let providerConfig: LLMAPIProviderConfig
    let session: URLSession

    init(providerConfig: LLMAPIProviderConfig, session: URLSession = .shared) {
        self.providerConfig = providerConfig
        self.session = session
    }

    func complete(input: String, systemPrompt: String? = nil) async throws -> String {
        let request = try makeRequest(input: input, systemPrompt: systemPrompt)
        let (data, response) = try await session.data(for: request)
        guard
            let httpResponse = response as? HTTPURLResponse,
            (200..<300).contains(httpResponse.statusCode)
        else {
            throw URLError(.badServerResponse)
        }

        return try decodeText(from: data)
    }

    private func makeRequest(input: String, systemPrompt: String?) throws -> URLRequest {
        let endpointURL = try endpointURL()
        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        switch providerConfig.wireFormat {
        case .openAIResponses:
            request.addValue("Bearer \(providerConfig.apiToken)", forHTTPHeaderField: "Authorization")
            request.httpBody = try JSONEncoder().encode(
                ResponsesRequest(
                    model: providerConfig.model,
                    input: input
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
                    stream: false
                )
            )
        case .anthropicMessages:
            request.addValue(providerConfig.apiToken, forHTTPHeaderField: "x-api-key")
            request.addValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            let trimmedSystemPrompt = systemPrompt?.trimmingCharacters(in: .whitespacesAndNewlines)
            request.httpBody = try JSONEncoder().encode(
                AnthropicMessagesRequest(
                    model: providerConfig.model,
                    maxTokens: 4096,
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
                        : nil
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
}

extension CLISummarizer: IncrementalSummaryGenerating {}

private struct ResponsesRequest: Encodable {
    let model: String
    let input: String
}

private struct OpenAIChatRequest: Encodable {
    let model: String
    let messages: [OpenAIChatMessage]
    let stream: Bool
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
    let system: String?
    let messages: [AnthropicMessage]

    enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
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

    enum CodingKeys: String, CodingKey {
        case contents
        case systemInstruction = "system_instruction"
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
