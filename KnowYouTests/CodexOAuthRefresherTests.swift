import XCTest
@testable import KnowYou

final class CodexOAuthRefresherTests: XCTestCase {
    private var temporaryDirectoryURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectoryURL, withIntermediateDirectories: true)
        CodexOAuthStubURLProtocol.reset()
    }

    override func tearDownWithError() throws {
        CodexOAuthStubURLProtocol.reset()
        try? FileManager.default.removeItem(at: temporaryDirectoryURL)
        try super.tearDownWithError()
    }

    func testSendsFormEncodedRefreshRequestAndPersistsCredential() async throws {
        let authFileURL = try makeAuthFile()
        let newAccess = token(accountID: "new-account")
        CodexOAuthStubURLProtocol.response = .success(
            statusCode: 200,
            body: Data("""
            {
              "access_token": "\(newAccess)",
              "refresh_token": "new-refresh",
              "expires_in": 3600
            }
            """.utf8)
        )
        let refresher = CodexOAuthRefresher(
            session: CodexOAuthStubURLProtocol.makeSession(),
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )
        let store = CodexAuthStore(environment: ["CODEX_HOME": temporaryDirectoryURL.path])
        let credential = CodexOAuthCredential(
            accessToken: token(accountID: "old-account"),
            refreshToken: "old-refresh",
            expiresAt: Date(timeIntervalSince1970: 1_700_000_000),
            accountID: "old-account",
            source: .authFile(path: authFileURL.path)
        )

        let refreshed = try await refresher.refresh(credential, using: store)

        XCTAssertEqual(refreshed.accessToken, newAccess)
        XCTAssertEqual(refreshed.refreshToken, "new-refresh")
        XCTAssertEqual(refreshed.accountID, "new-account")
        XCTAssertEqual(refreshed.expiresAt.timeIntervalSince1970, 1_800_003_600, accuracy: 0.001)

        let request = try XCTUnwrap(CodexOAuthStubURLProtocol.lastRequest)
        XCTAssertEqual(request.url, URL(string: "https://auth.openai.com/oauth/token"))
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded")
        XCTAssertEqual(CodexOAuthStubURLProtocol.lastBody, "client_id=app_EMoamEEZ73f0CkXaXp7hrann&grant_type=refresh_token&refresh_token=old-refresh")

        let written = try String(contentsOf: authFileURL, encoding: .utf8)
        XCTAssertTrue(written.contains(newAccess))
        XCTAssertTrue(written.contains("new-refresh"))
        XCTAssertTrue(written.contains("new-account"))
    }

    func testRejectsRefreshResponseMissingRequiredFields() async throws {
        let authFileURL = try makeAuthFile()
        CodexOAuthStubURLProtocol.response = .success(
            statusCode: 200,
            body: Data(#"{"access_token":"only-access"}"#.utf8)
        )
        let refresher = CodexOAuthRefresher(session: CodexOAuthStubURLProtocol.makeSession())

        await XCTAssertThrowsErrorAsync(
            _ = try await refresher.refresh(
                CodexOAuthCredential(
                    accessToken: token(accountID: "old-account"),
                    refreshToken: "old-refresh",
                    expiresAt: Date(timeIntervalSince1970: 1_700_000_000),
                    accountID: "old-account",
                    source: .authFile(path: authFileURL.path)
                ),
                using: CodexAuthStore(environment: ["CODEX_HOME": temporaryDirectoryURL.path])
            )
        ) { error in
            XCTAssertEqual(error as? CodexOAuthRefreshError, .invalidResponse)
        }
    }

    func testErrorDescriptionDoesNotExposeTokenValues() async throws {
        let authFileURL = try makeAuthFile()
        CodexOAuthStubURLProtocol.response = .success(statusCode: 401, body: Data("refresh-secret denied".utf8))
        let refresher = CodexOAuthRefresher(session: CodexOAuthStubURLProtocol.makeSession())

        await XCTAssertThrowsErrorAsync(
            _ = try await refresher.refresh(
                CodexOAuthCredential(
                    accessToken: "access-secret",
                    refreshToken: "refresh-secret",
                    expiresAt: Date(timeIntervalSince1970: 1_700_000_000),
                    accountID: "old-account",
                    source: .authFile(path: authFileURL.path)
                ),
                using: CodexAuthStore(environment: ["CODEX_HOME": temporaryDirectoryURL.path])
            )
        ) { error in
            XCTAssertFalse(error.localizedDescription.contains("refresh-secret"))
            XCTAssertFalse(error.localizedDescription.contains("access-secret"))
        }
    }

    private func makeAuthFile() throws -> URL {
        let authFileURL = temporaryDirectoryURL.appendingPathComponent("auth.json")
        try """
        {
          "auth_mode": "chatgpt",
          "tokens": {
            "access_token": "\(token(accountID: "old-account"))",
            "refresh_token": "old-refresh"
          }
        }
        """.write(to: authFileURL, atomically: true, encoding: .utf8)
        return authFileURL
    }

    private func token(accountID: String) -> String {
        makeJWT(payload: [
            "exp": 2_000_000_000,
            "https://api.openai.com/auth": [
                "chatgpt_account_id": accountID
            ]
        ])
    }
}

private final class CodexOAuthStubURLProtocol: URLProtocol {
    enum Response {
        case success(statusCode: Int, body: Data)
        case failure(Error)
    }

    nonisolated(unsafe) static var response: Response?
    nonisolated(unsafe) static var lastRequest: URLRequest?
    nonisolated(unsafe) static var lastBody: String?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.lastRequest = request
        Self.lastBody = request.codexHTTPBodyString()

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
                headerFields: ["Content-Type": "application/json"]
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
        configuration.protocolClasses = [CodexOAuthStubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    static func reset() {
        response = nil
        lastRequest = nil
        lastBody = nil
    }
}

private extension URLRequest {
    func codexHTTPBodyString() -> String? {
        if let httpBody {
            return String(decoding: httpBody, as: UTF8.self)
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
        return String(decoding: data, as: UTF8.self)
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
