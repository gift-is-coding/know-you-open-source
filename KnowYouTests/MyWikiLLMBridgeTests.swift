import XCTest
@testable import KnowYou

final class MyWikiLLMBridgeTests: XCTestCase {
    func testBridgeAnswersLLMRequestUsingInjectedDiaryEngineAndPreservesTranscript() async throws {
        let messages = [
            MyWikiLLMMessage(role: "system", content: "Extract ontology."),
            MyWikiLLMMessage(role: "user", content: "Diary text"),
            MyWikiLLMMessage(role: "assistant", content: "Prior context")
        ]
        let engine = StubMyWikiLLMEngine(result: "Ontology page draft")
        let bridge = MyWikiLLMBridge(engine: engine)

        let response = try await bridge.handle(
            .llmRequest(
                MyWikiLLMRequest(
                    id: "req-1",
                    messages: messages,
                    temperature: 0.2,
                    maxTokens: 8192,
                    reasoning: LLMReasoningOptions(mode: "off", budgetTokens: nil)
                )
            )
        )

        XCTAssertEqual(
            response,
            .llmResponse(MyWikiLLMResponse(id: "req-1", content: "Ontology page draft"))
        )
        let recordedRequests = await engine.recordedRequests()
        XCTAssertEqual(
            recordedRequests,
            [
                StubMyWikiLLMEngine.Request(
                    messages: messages,
                    options: LLMCompletionOptions(
                        temperature: 0.2,
                        maxTokens: 8192,
                        reasoning: LLMReasoningOptions(mode: "off", budgetTokens: nil)
                    )
                )
            ]
        )
    }

    func testBridgeMapsDiaryEngineAuthFailuresToStructuredError() async throws {
        for code in [URLError.Code.userAuthenticationRequired, .userCancelledAuthentication] {
            let engine = StubMyWikiLLMEngine(error: URLError(code))
            let bridge = MyWikiLLMBridge(engine: engine)

            let response = try await bridge.handle(
                .llmRequest(
                    MyWikiLLMRequest(
                        id: "req-auth",
                        messages: [MyWikiLLMMessage(role: "user", content: "Diary text")],
                        temperature: nil
                    )
                )
            )

            XCTAssertEqual(
                response,
                .llmError(
                    MyWikiLLMErrorResponse(
                        id: "req-auth",
                        code: "auth_failed",
                        message: "Diary Engine authentication failed."
                    )
                )
            )
        }
    }

    func testBridgeMapsOtherDiaryEngineFailuresToStructuredError() async throws {
        let engine = StubMyWikiLLMEngine(error: StubEngineError(message: "Engine unavailable"))
        let bridge = MyWikiLLMBridge(engine: engine)

        let response = try await bridge.handle(
            .llmRequest(
                MyWikiLLMRequest(
                    id: "req-engine",
                    messages: [MyWikiLLMMessage(role: "user", content: "Diary text")],
                    temperature: nil
                )
            )
        )

        XCTAssertEqual(
            response,
            .llmError(
                MyWikiLLMErrorResponse(
                    id: "req-engine",
                    code: "engine_failed",
                    message: "Engine unavailable"
                )
            )
        )
    }

    func testEnvelopeEncodesAndDecodesFlatJSONLShape() throws {
        let requestEnvelope = MyWikiBridgeEnvelope.llmRequest(
            MyWikiLLMRequest(
                id: "req-json",
                messages: [
                    MyWikiLLMMessage(role: "system", content: "Use wiki schema."),
                    MyWikiLLMMessage(role: "user", content: "Diary text")
                ],
                temperature: 0.7,
                maxTokens: 8192,
                reasoning: LLMReasoningOptions(mode: "custom", budgetTokens: 1024)
            )
        )

        let data = try JSONEncoder().encode(requestEnvelope)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["type"] as? String, "llm.request")
        XCTAssertEqual(object["id"] as? String, "req-json")
        XCTAssertNotNil(object["messages"])
        XCTAssertEqual((object["temperature"] as? NSNumber)?.doubleValue, 0.7)
        XCTAssertEqual(object["max_tokens"] as? Int, 8192)
        let reasoning = try XCTUnwrap(object["reasoning"] as? [String: Any])
        XCTAssertEqual(reasoning["mode"] as? String, "custom")
        XCTAssertEqual(reasoning["budgetTokens"] as? Int, 1024)
        XCTAssertNil(object["llmRequest"])
        XCTAssertNil(object["llmResponse"])
        XCTAssertNil(object["llmError"])

        XCTAssertEqual(try JSONDecoder().decode(MyWikiBridgeEnvelope.self, from: data), requestEnvelope)
        XCTAssertEqual(
            try JSONDecoder().decode(
                MyWikiBridgeEnvelope.self,
                from: Data(#"{"type":"llm.response","id":"req-json","content":"Done"}"#.utf8)
            ),
            .llmResponse(MyWikiLLMResponse(id: "req-json", content: "Done"))
        )
        XCTAssertEqual(
            try JSONDecoder().decode(
                MyWikiBridgeEnvelope.self,
                from: Data(#"{"type":"llm.error","id":"req-json","code":"engine_failed","message":"Nope"}"#.utf8)
            ),
            .llmError(
                MyWikiLLMErrorResponse(
                    id: "req-json",
                    code: "engine_failed",
                    message: "Nope"
                )
            )
        )
    }

    func testBridgeRejectsUnexpectedResponseAndErrorEnvelopesFromRunner() async throws {
        let bridge = MyWikiLLMBridge(engine: StubMyWikiLLMEngine(result: "Unused"))

        try await assertUnexpectedRunnerEnvelopeThrows(
            .llmResponse(MyWikiLLMResponse(id: "req-2", content: "Runner response")),
            bridge: bridge
        )
        try await assertUnexpectedRunnerEnvelopeThrows(
            .llmError(
                MyWikiLLMErrorResponse(
                    id: "req-3",
                    code: "runner_failed",
                    message: "Runner error"
                )
            ),
            bridge: bridge
        )
    }

    private func assertUnexpectedRunnerEnvelopeThrows(
        _ envelope: MyWikiBridgeEnvelope,
        bridge: MyWikiLLMBridge,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        do {
            _ = try await bridge.handle(envelope)
            XCTFail("Expected bridge to reject unexpected runner envelope.", file: file, line: line)
        } catch let error as MyWikiLLMBridgeError {
            XCTAssertEqual(error, .unexpectedRunnerEnvelope, file: file, line: line)
        } catch {
            XCTFail("Expected MyWikiLLMBridgeError, got \(error).", file: file, line: line)
        }
    }
}

private struct StubEngineError: LocalizedError {
    let message: String

    var errorDescription: String? {
        message
    }
}

private actor StubMyWikiLLMEngine: MyWikiLLMCompleting {
    struct Request: Equatable {
        let messages: [MyWikiLLMMessage]
        let options: LLMCompletionOptions
    }

    private let result: String?
    private let error: Error?
    private var requests: [Request] = []

    init(result: String) {
        self.result = result
        self.error = nil
    }

    init(error: Error) {
        self.result = nil
        self.error = error
    }

    func complete(messages: [MyWikiLLMMessage], options: LLMCompletionOptions) async throws -> String {
        requests.append(Request(messages: messages, options: options))
        if let error {
            throw error
        }
        return result ?? ""
    }

    func recordedRequests() -> [Request] {
        requests
    }
}
