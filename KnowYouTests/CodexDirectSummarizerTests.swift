import XCTest
@testable import KnowYou

final class CodexDirectSummarizerTests: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        CodexDirectStubURLProtocol.reset()
    }

    override func tearDownWithError() throws {
        CodexDirectStubURLProtocol.reset()
        try super.tearDownWithError()
    }

    func testPostsCodexResponsesRequestWithCodexHeaders() async throws {
        CodexDirectStubURLProtocol.response = .success(
            statusCode: 200,
            body: Data("""
            data: {"type":"response.completed","response":{"output_text":" Codex summary "}}

            """.utf8)
        )
        let summarizer = CodexDirectSummarizer(
            credentialProvider: StubCodexCredentialProvider(
                credential: CodexOAuthCredential(
                    accessToken: "access-token",
                    refreshToken: "refresh-token",
                    expiresAt: Date(timeIntervalSince1970: 2_000_000_000),
                    accountID: "account-id",
                    source: .authFile(path: "/tmp/auth.json")
                )
            ),
            session: CodexDirectStubURLProtocol.makeSession()
        )

        let result = try await summarizer.summarize(
            dayKey: "2026-05-07",
            markdown: "Daily markdown",
            context: .manualRefresh
        )

        XCTAssertEqual(result, "Codex summary")
        let request = try XCTUnwrap(CodexDirectStubURLProtocol.lastRequest)
        XCTAssertEqual(request.url, URL(string: "https://chatgpt.com/backend-api/codex/responses"))
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "chatgpt-account-id"), "account-id")
        XCTAssertEqual(request.value(forHTTPHeaderField: "originator"), "pi")
        XCTAssertEqual(request.value(forHTTPHeaderField: "OpenAI-Beta"), "responses=experimental")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "text/event-stream")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let body = try XCTUnwrap(CodexDirectStubURLProtocol.lastBodyData)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(object["model"] as? String, "gpt-5.4")
        XCTAssertEqual(object["store"] as? Bool, false)
        XCTAssertEqual(object["stream"] as? Bool, true)
        XCTAssertEqual(object["tool_choice"] as? String, "auto")
        XCTAssertEqual(object["parallel_tool_calls"] as? Bool, true)
        XCTAssertEqual(object["include"] as? [String], ["reasoning.encrypted_content"])

        let text = try XCTUnwrap(object["text"] as? [String: Any])
        XCTAssertEqual(text["verbosity"] as? String, "medium")
        let input = try XCTUnwrap(object["input"] as? [[String: Any]])
        let firstMessage = try XCTUnwrap(input.first)
        XCTAssertEqual(firstMessage["role"] as? String, "user")
        let content = try XCTUnwrap(firstMessage["content"] as? String)
        XCTAssertTrue(content.contains("Summarize this day as a concise diary entry for 2026-05-07"))
        XCTAssertTrue(content.contains("Daily markdown"))
    }

    func testIncrementalRequestUsesMarkdownWithoutFullSummaryPrefix() async throws {
        CodexDirectStubURLProtocol.response = .success(
            statusCode: 200,
            body: Data("""
            data: {"type":"response.completed","response":{"output_text":"Incremental summary"}}

            """.utf8)
        )
        let summarizer = CodexDirectSummarizer(
            credentialProvider: StubCodexCredentialProvider(
                credential: CodexOAuthCredential(
                    accessToken: "access-token",
                    refreshToken: "refresh-token",
                    expiresAt: Date(timeIntervalSince1970: 2_000_000_000),
                    accountID: "account-id",
                    source: .authFile(path: "/tmp/auth.json")
                )
            ),
            session: CodexDirectStubURLProtocol.makeSession()
        )

        let result = try await summarizer.summarizeIncremental(
            dayKey: "2026-05-07",
            markdown: "Incremental markdown",
            context: .automationRefresh
        )

        XCTAssertEqual(result, "Incremental summary")
        let body = try XCTUnwrap(CodexDirectStubURLProtocol.lastBodyData)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let input = try XCTUnwrap(object["input"] as? [[String: Any]])
        let firstMessage = try XCTUnwrap(input.first)
        XCTAssertEqual(firstMessage["content"] as? String, "Incremental markdown")
    }

    func testMyWikiCompletionReusesCodexAuthWithSystemInstructionsAndTranscript() async throws {
        CodexDirectStubURLProtocol.response = .success(
            statusCode: 200,
            body: Data("""
            data: {"type":"response.completed","response":{"output_text":"Codex MyWiki ontology"}}

            """.utf8)
        )
        let summarizer = CodexDirectSummarizer(
            credentialProvider: StubCodexCredentialProvider(
                credential: CodexOAuthCredential(
                    accessToken: "access-token",
                    refreshToken: "refresh-token",
                    expiresAt: Date(timeIntervalSince1970: 2_000_000_000),
                    accountID: "account-id",
                    source: .authFile(path: "/tmp/auth.json")
                )
            ),
            session: CodexDirectStubURLProtocol.makeSession(),
            instructions: "Default diary instructions."
        )

        let result = try await summarizer.complete(
            messages: [
                MyWikiLLMMessage(role: "system", content: "Extract My Wiki ontology."),
                MyWikiLLMMessage(role: "user", content: "Diary text"),
                MyWikiLLMMessage(role: "assistant", content: "Prior context")
            ],
            options: LLMCompletionOptions(temperature: 0.2, maxTokens: 8192)
        )

        XCTAssertEqual(result, "Codex MyWiki ontology")
        let body = try XCTUnwrap(CodexDirectStubURLProtocol.lastBodyData)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(object["instructions"] as? String, "Extract My Wiki ontology.")
        XCTAssertEqual(object["max_output_tokens"] as? Int, 8192)
        let input = try XCTUnwrap(object["input"] as? [[String: Any]])
        XCTAssertEqual(input.count, 2)
        XCTAssertEqual(input[0]["role"] as? String, "user")
        XCTAssertEqual(input[0]["content"] as? String, "Diary text")
        XCTAssertEqual(input[1]["role"] as? String, "assistant")
        XCTAssertEqual(input[1]["content"] as? String, "Prior context")
    }

    func testMyWikiCompletionReasoningOffOmitsReasoningPayload() async throws {
        CodexDirectStubURLProtocol.response = .success(
            statusCode: 200,
            body: Data("""
            data: {"type":"response.completed","response":{"output_text":"Codex MyWiki ontology"}}

            """.utf8)
        )
        let summarizer = CodexDirectSummarizer(
            credentialProvider: StubCodexCredentialProvider(
                credential: CodexOAuthCredential(
                    accessToken: "access-token",
                    refreshToken: "refresh-token",
                    expiresAt: Date(timeIntervalSince1970: 2_000_000_000),
                    accountID: "account-id",
                    source: .authFile(path: "/tmp/auth.json")
                )
            ),
            session: CodexDirectStubURLProtocol.makeSession(),
            instructions: "Default diary instructions."
        )

        _ = try await summarizer.complete(
            messages: [MyWikiLLMMessage(role: "user", content: "Diary text")],
            options: LLMCompletionOptions(
                temperature: 0.2,
                maxTokens: 8192,
                reasoning: LLMReasoningOptions(mode: "off")
            )
        )

        let body = try XCTUnwrap(CodexDirectStubURLProtocol.lastBodyData)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertNil(object["reasoning"])
        XCTAssertNil(object["include"])
    }

    func testCompletedSSEEventIgnoresReasoningOutputItemsWithoutContent() async throws {
        CodexDirectStubURLProtocol.response = .success(
            statusCode: 200,
            body: Data("""
            data: {"type":"response.completed","response":{"output":[{"type":"reasoning","summary":[]},{"type":"message","content":[{"type":"output_text","text":"OK from real shape"}]}]}}

            """.utf8)
        )
        let summarizer = CodexDirectSummarizer(
            credentialProvider: StubCodexCredentialProvider(
                credential: CodexOAuthCredential(
                    accessToken: "access-token",
                    refreshToken: "refresh-token",
                    expiresAt: Date(timeIntervalSince1970: 2_000_000_000),
                    accountID: "account-id",
                    source: .authFile(path: "/tmp/auth.json")
                )
            ),
            session: CodexDirectStubURLProtocol.makeSession()
        )

        let result = try await summarizer.smokeTest()

        XCTAssertEqual(result, "OK from real shape")
    }

    func testSSEDeltaEventsAreAccumulatedWhenCompletedEventHasNoText() async throws {
        CodexDirectStubURLProtocol.response = .success(
            statusCode: 200,
            body: Data("""
            data: {"type":"response.created","response":{"id":"resp_123","status":"in_progress"}}

            data: {"type":"response.output_text.delta","delta":"O"}

            data: {"type":"response.output_text.delta","delta":"K"}

            data: [DONE]

            """.utf8)
        )
        let summarizer = CodexDirectSummarizer(
            credentialProvider: StubCodexCredentialProvider(
                credential: CodexOAuthCredential(
                    accessToken: "access-token",
                    refreshToken: "refresh-token",
                    expiresAt: Date(timeIntervalSince1970: 2_000_000_000),
                    accountID: "account-id",
                    source: .authFile(path: "/tmp/auth.json")
                )
            ),
            session: CodexDirectStubURLProtocol.makeSession()
        )

        let result = try await summarizer.smokeTest()

        XCTAssertEqual(result, "OK")
    }

    func testHTTPErrorDescriptionDoesNotExposeTokenValues() async throws {
        CodexDirectStubURLProtocol.response = .success(
            statusCode: 401,
            body: Data("access-token denied".utf8)
        )
        let summarizer = CodexDirectSummarizer(
            credentialProvider: StubCodexCredentialProvider(
                credential: CodexOAuthCredential(
                    accessToken: "access-token",
                    refreshToken: "refresh-token",
                    expiresAt: Date(timeIntervalSince1970: 2_000_000_000),
                    accountID: "account-id",
                    source: .authFile(path: "/tmp/auth.json")
                )
            ),
            session: CodexDirectStubURLProtocol.makeSession()
        )

        await XCTAssertThrowsErrorAsync(
            _ = try await summarizer.summarize(dayKey: "2026-05-07", markdown: "Daily markdown", context: .manualRefresh)
        ) { error in
            XCTAssertFalse(error.localizedDescription.contains("access-token"))
            XCTAssertFalse(error.localizedDescription.contains("refresh-token"))
        }
    }
}

private final class StubCodexCredentialProvider: CodexCredentialProviding, @unchecked Sendable {
    private let credential: CodexOAuthCredential

    init(credential: CodexOAuthCredential) {
        self.credential = credential
    }

    func validCredential() async throws -> CodexOAuthCredential {
        credential
    }
}

private final class CodexDirectStubURLProtocol: URLProtocol {
    enum Response {
        case success(statusCode: Int, body: Data)
        case failure(Error)
    }

    nonisolated(unsafe) static var response: Response?
    nonisolated(unsafe) static var lastRequest: URLRequest?
    nonisolated(unsafe) static var lastBodyData: Data?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.lastRequest = request
        Self.lastBodyData = request.codexHTTPBodyData()

        guard let response = Self.response else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        switch response {
        case .success(let statusCode, let body):
            let httpResponse = HTTPURLResponse(
                url: request.url ?? URL(string: "https://example.com")!,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "text/event-stream"]
            )!
            client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        case .failure(let error):
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CodexDirectStubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    static func reset() {
        response = nil
        lastRequest = nil
        lastBodyData = nil
    }
}

private extension URLRequest {
    func codexHTTPBodyData() -> Data? {
        if let httpBody {
            return httpBody
        }
        guard let stream = httpBodyStream else {
            return nil
        }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 {
                break
            }
            data.append(buffer, count: count)
        }
        return data
    }
}

private func XCTAssertThrowsErrorAsync(
    _ expression: @autoclosure () async throws -> Void,
    verify: (Error) -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await expression()
        XCTFail("Expected error to be thrown", file: file, line: line)
    } catch {
        verify(error)
    }
}
