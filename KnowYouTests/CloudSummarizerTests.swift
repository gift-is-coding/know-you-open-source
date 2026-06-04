import XCTest
@testable import KnowYou

private final class CloudStubURLProtocol: URLProtocol {
    enum Behavior {
        case success(statusCode: Int, body: Data)
        case failure(Error)
    }

    nonisolated(unsafe) static var behavior: Behavior?
    nonisolated(unsafe) static var lastRequest: URLRequest?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.lastRequest = request

        guard let behavior = Self.behavior else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        switch behavior {
        case .success(let statusCode, let body):
            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://example.com")!,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        case .failure(let error):
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CloudStubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    static func reset() {
        behavior = nil
        lastRequest = nil
    }
}

final class CloudSummarizerTests: XCTestCase {
    override func tearDown() {
        CloudStubURLProtocol.reset()
        super.tearDown()
    }

    func testResponsesResponseExtractsTextFromOutputMessageContent() throws {
        let payload = """
        {
          "output": [
            { "type": "reasoning", "summary": [] },
            {
              "type": "message",
              "content": [
                { "type": "output_text", "text": "# 你今天做得很棒\\n\\n- 你把重点拎清了。" }
              ]
            }
          ]
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(ResponsesResponse.self, from: payload)

        XCTAssertEqual(response.outputText, "# 你今天做得很棒\n\n- 你把重点拎清了。")
    }

    func testLLMAPIClientSendsOpenAIResponsesRequestAndParsesOutputText() async throws {
        CloudStubURLProtocol.behavior = .success(statusCode: 200, body: Data(#"{"output_text":"OpenAI OK"}"#.utf8))
        let providerConfig = LLMAPIProviderConfig(
            id: .openAI,
            baseURL: "https://api.openai.com/v1/responses",
            model: "gpt-5",
            wireFormat: .openAIResponses,
            apiToken: "sk-openai-test"
        )

        let output = try await LLMAPIClient(
            providerConfig: providerConfig,
            session: CloudStubURLProtocol.makeSession()
        ).complete(input: "Reply with OK.")

        XCTAssertEqual(output, "OpenAI OK")
        let request = try XCTUnwrap(CloudStubURLProtocol.lastRequest)
        XCTAssertEqual(request.url, URL(string: "https://api.openai.com/v1/responses"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-openai-test")
        let body = try requestBodyJSON(request)
        XCTAssertEqual(body["model"] as? String, "gpt-5")
        XCTAssertEqual(body["input"] as? String, "Reply with OK.")
    }

    func testLLMAPIClientSendsOpenAIChatRequestAndParsesChoiceText() async throws {
        CloudStubURLProtocol.behavior = .success(
            statusCode: 200,
            body: Data(#"{"choices":[{"message":{"content":"DeepSeek OK"}}]}"#.utf8)
        )
        let providerConfig = LLMAPIProviderConfig(
            id: .deepSeek,
            baseURL: "https://api.deepseek.com",
            model: "deepseek-v4-pro",
            wireFormat: .openAIChat,
            apiToken: "sk-deepseek-test"
        )

        let output = try await LLMAPIClient(
            providerConfig: providerConfig,
            session: CloudStubURLProtocol.makeSession()
        ).complete(input: "Reply with OK.")

        XCTAssertEqual(output, "DeepSeek OK")
        let request = try XCTUnwrap(CloudStubURLProtocol.lastRequest)
        XCTAssertEqual(request.url, URL(string: "https://api.deepseek.com/chat/completions"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-deepseek-test")
        let body = try requestBodyJSON(request)
        XCTAssertEqual(body["model"] as? String, "deepseek-v4-pro")
        XCTAssertEqual(body["stream"] as? Bool, false)
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.first?["role"] as? String, "user")
        XCTAssertEqual(messages.first?["content"] as? String, "Reply with OK.")
    }

    func testLLMAPIClientSendsAnthropicMessagesRequestAndParsesTextContent() async throws {
        CloudStubURLProtocol.behavior = .success(
            statusCode: 200,
            body: Data(#"{"content":[{"type":"text","text":"Anthropic OK"}]}"#.utf8)
        )
        let providerConfig = LLMAPIProviderConfig(
            id: .anthropic,
            baseURL: "https://api.anthropic.com/v1/messages",
            model: "claude-sonnet-4-5",
            wireFormat: .anthropicMessages,
            apiToken: "sk-ant-test"
        )

        let output = try await LLMAPIClient(
            providerConfig: providerConfig,
            session: CloudStubURLProtocol.makeSession()
        ).complete(input: "Reply with OK.", systemPrompt: "Be brief.")

        XCTAssertEqual(output, "Anthropic OK")
        let request = try XCTUnwrap(CloudStubURLProtocol.lastRequest)
        XCTAssertEqual(request.url, URL(string: "https://api.anthropic.com/v1/messages"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "sk-ant-test")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
        let body = try requestBodyJSON(request)
        XCTAssertEqual(body["model"] as? String, "claude-sonnet-4-5")
        XCTAssertEqual(body["max_tokens"] as? Int, 4096)
        XCTAssertEqual(body["system"] as? String, "Be brief.")
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.first?["role"] as? String, "user")
        XCTAssertEqual(messages.first?["content"] as? String, "Reply with OK.")
    }

    func testLLMAPIClientSendsGeminiGenerateContentRequestAndParsesCandidateText() async throws {
        CloudStubURLProtocol.behavior = .success(
            statusCode: 200,
            body: Data(#"{"candidates":[{"content":{"parts":[{"text":"Gemini OK"}]}}]}"#.utf8)
        )
        let providerConfig = LLMAPIProviderConfig(
            id: .gemini,
            baseURL: "https://generativelanguage.googleapis.com/v1beta",
            model: "gemini-3.5-flash",
            wireFormat: .geminiGenerateContent,
            apiToken: "sk-gemini-test"
        )

        let output = try await LLMAPIClient(
            providerConfig: providerConfig,
            session: CloudStubURLProtocol.makeSession()
        ).complete(input: "Reply with OK.", systemPrompt: "Be brief.")

        XCTAssertEqual(output, "Gemini OK")
        let request = try XCTUnwrap(CloudStubURLProtocol.lastRequest)
        XCTAssertEqual(
            request.url,
            URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.5-flash:generateContent")
        )
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-goog-api-key"), "sk-gemini-test")
        let body = try requestBodyJSON(request)
        let contents = try XCTUnwrap(body["contents"] as? [[String: Any]])
        let userParts = try XCTUnwrap(contents.first?["parts"] as? [[String: Any]])
        XCTAssertEqual(userParts.first?["text"] as? String, "Reply with OK.")
        let systemInstruction = try XCTUnwrap(body["system_instruction"] as? [String: Any])
        let systemParts = try XCTUnwrap(systemInstruction["parts"] as? [[String: Any]])
        XCTAssertEqual(systemParts.first?["text"] as? String, "Be brief.")
    }

    func testMyWikiBridgeMapsCloudUnauthorizedResponsesToAuthFailed() async throws {
        for statusCode in [401, 403] {
            CloudStubURLProtocol.reset()
            CloudStubURLProtocol.behavior = .success(statusCode: statusCode, body: Data(#"{"error":"invalid token"}"#.utf8))
            let providerConfig = LLMAPIProviderConfig(
                id: .openAI,
                baseURL: "https://api.openai.com/v1/responses",
                model: "gpt-5",
                wireFormat: .openAIResponses,
                apiToken: "sk-invalid"
            )
            let summarizer = CloudSummarizer(
                providerConfig: providerConfig,
                session: CloudStubURLProtocol.makeSession()
            )
            let bridge = MyWikiLLMBridge(engine: summarizer)

            let response = try await bridge.handle(
                .llmRequest(
                    MyWikiLLMRequest(
                        id: "req-\(statusCode)",
                        messages: [MyWikiLLMMessage(role: "user", content: "Build My Wiki context.")],
                        temperature: nil
                    )
                )
            )

            XCTAssertEqual(
                response,
                .llmError(
                    MyWikiLLMErrorResponse(
                        id: "req-\(statusCode)",
                        code: "auth_failed",
                        message: "Diary Engine authentication failed."
                    )
                )
            )
        }
    }

    private func requestBodyJSON(_ request: URLRequest) throws -> [String: Any] {
        let bodyData = try XCTUnwrap(request.httpBody ?? data(from: request.httpBodyStream))
        return try XCTUnwrap(
            JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
        )
    }

    private func data(from stream: InputStream?) -> Data? {
        guard let stream else {
            return nil
        }
        stream.open()
        defer { stream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count > 0 {
                data.append(buffer, count: count)
            } else {
                break
            }
        }
        return data
    }
}
