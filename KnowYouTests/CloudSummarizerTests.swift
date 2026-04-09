import XCTest
@testable import KnowYou

final class CloudSummarizerTests: XCTestCase {
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
}
