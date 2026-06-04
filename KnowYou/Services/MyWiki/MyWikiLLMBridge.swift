import Foundation

protocol MyWikiLLMCompleting: Sendable {
    func complete(messages: [MyWikiLLMMessage], temperature: Double?) async throws -> String
}

struct MyWikiLLMMessage: Codable, Equatable, Sendable {
    let role: String
    let content: String
}

struct MyWikiLLMRequest: Codable, Equatable, Sendable {
    let id: String
    let messages: [MyWikiLLMMessage]
    let temperature: Double?
}

struct MyWikiLLMResponse: Codable, Equatable, Sendable {
    let id: String
    let content: String
}

struct MyWikiLLMErrorResponse: Codable, Equatable, Sendable {
    let id: String
    let code: String
    let message: String
}

enum MyWikiBridgeEnvelope: Codable, Equatable, Sendable {
    case llmRequest(MyWikiLLMRequest)
    case llmResponse(MyWikiLLMResponse)
    case llmError(MyWikiLLMErrorResponse)
}

enum MyWikiLLMBridgeError: LocalizedError, Equatable, Sendable {
    case unexpectedRunnerEnvelope

    var errorDescription: String? {
        switch self {
        case .unexpectedRunnerEnvelope:
            return "Runner sent an unexpected MyWiki bridge response."
        }
    }
}

struct MyWikiLLMBridge: Sendable {
    let engine: any MyWikiLLMCompleting

    init(engine: any MyWikiLLMCompleting) {
        self.engine = engine
    }

    func handle(_ envelope: MyWikiBridgeEnvelope) async throws -> MyWikiBridgeEnvelope {
        switch envelope {
        case .llmRequest(let request):
            return await handle(request)
        case .llmResponse, .llmError:
            throw MyWikiLLMBridgeError.unexpectedRunnerEnvelope
        }
    }

    private func handle(_ request: MyWikiLLMRequest) async -> MyWikiBridgeEnvelope {
        do {
            let content = try await engine.complete(
                messages: request.messages,
                temperature: request.temperature
            )
            return .llmResponse(MyWikiLLMResponse(id: request.id, content: content))
        } catch {
            return .llmError(
                MyWikiLLMErrorResponse(
                    id: request.id,
                    code: Self.code(for: error),
                    message: Self.message(for: error)
                )
            )
        }
    }

    private static func code(for error: Error) -> String {
        if isAuthenticationError(error) {
            return "auth_failed"
        }
        return "engine_failed"
    }

    private static func message(for error: Error) -> String {
        if isAuthenticationError(error) {
            return "Diary Engine authentication failed."
        }
        return error.localizedDescription
    }

    private static func isAuthenticationError(_ error: Error) -> Bool {
        if let clientError = error as? LLMAPIClientError {
            return clientError.isAuthenticationFailure
        }

        guard let code = urlErrorCode(for: error) else {
            return false
        }
        return code == .userAuthenticationRequired || code == .userCancelledAuthentication
    }

    private static func urlErrorCode(for error: Error) -> URLError.Code? {
        if let urlError = error as? URLError {
            return urlError.code
        }

        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else {
            return nil
        }
        return URLError.Code(rawValue: nsError.code)
    }
}

extension MyWikiBridgeEnvelope {
    private enum CodingKeys: String, CodingKey {
        case type
        case id
        case messages
        case temperature
        case content
        case code
        case message
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "llm.request":
            self = .llmRequest(
                MyWikiLLMRequest(
                    id: try container.decode(String.self, forKey: .id),
                    messages: try container.decode([MyWikiLLMMessage].self, forKey: .messages),
                    temperature: try container.decodeIfPresent(Double.self, forKey: .temperature)
                )
            )
        case "llm.response":
            self = .llmResponse(
                MyWikiLLMResponse(
                    id: try container.decode(String.self, forKey: .id),
                    content: try container.decode(String.self, forKey: .content)
                )
            )
        case "llm.error":
            self = .llmError(
                MyWikiLLMErrorResponse(
                    id: try container.decode(String.self, forKey: .id),
                    code: try container.decode(String.self, forKey: .code),
                    message: try container.decode(String.self, forKey: .message)
                )
            )
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown MyWiki bridge envelope type: \(type)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .llmRequest(let request):
            try container.encode("llm.request", forKey: .type)
            try container.encode(request.id, forKey: .id)
            try container.encode(request.messages, forKey: .messages)
            try container.encodeIfPresent(request.temperature, forKey: .temperature)
        case .llmResponse(let response):
            try container.encode("llm.response", forKey: .type)
            try container.encode(response.id, forKey: .id)
            try container.encode(response.content, forKey: .content)
        case .llmError(let response):
            try container.encode("llm.error", forKey: .type)
            try container.encode(response.id, forKey: .id)
            try container.encode(response.code, forKey: .code)
            try container.encode(response.message, forKey: .message)
        }
    }
}

extension Array where Element == MyWikiLLMMessage {
    var myWikiSystemPrompt: String? {
        let prompt = filter(\.isSystemMessage)
            .map(\.content)
            .joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return prompt.isEmpty ? nil : prompt
    }

    var myWikiNonSystemTranscript: String {
        filter { !$0.isSystemMessage }
            .map { "\($0.role):\n\($0.content)" }
            .joined(separator: "\n\n")
    }

    var myWikiFullTranscript: String {
        map { "\($0.role.uppercased()):\n\($0.content)" }
            .joined(separator: "\n\n")
    }
}

private extension MyWikiLLMMessage {
    var isSystemMessage: Bool {
        role.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "system"
    }
}
