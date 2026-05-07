import XCTest
@testable import KnowYou

final class CodexJWTTests: XCTestCase {
    func testDecodesExpiry() throws {
        let token = makeJWT(payload: ["exp": 2_000_000_000])

        let expiry = try XCTUnwrap(CodexJWT.expiryDate(from: token))

        XCTAssertEqual(expiry.timeIntervalSince1970, 2_000_000_000, accuracy: 0.001)
    }

    func testDecodesChatGPTAccountID() {
        let token = makeJWT(payload: [
            "https://api.openai.com/auth": [
                "chatgpt_account_id": "account-test-123"
            ]
        ])

        XCTAssertEqual(CodexJWT.accountID(from: token), "account-test-123")
    }

    func testRejectsMalformedToken() {
        XCTAssertNil(CodexJWT.expiryDate(from: "not-a-jwt"))
        XCTAssertNil(CodexJWT.accountID(from: "not-a-jwt"))
    }
}

func makeJWT(payload: [String: Any]) -> String {
    let header = base64URLEncodedJSON(["alg": "none", "typ": "JWT"])
    let payload = base64URLEncodedJSON(payload)
    return "\(header).\(payload).signature"
}

private func base64URLEncodedJSON(_ object: Any) -> String {
    let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    return data
        .base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}
