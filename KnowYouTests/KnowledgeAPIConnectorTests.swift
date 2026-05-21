import XCTest
@testable import KnowYou

final class KnowledgeAPIConnectorTests: XCTestCase {
    override func setUp() {
        super.setUp()
        KnowledgeAPIStubURLProtocol.reset()
    }

    override func tearDown() {
        KnowledgeAPIStubURLProtocol.reset()
        super.tearDown()
    }

    func testFeishuFetchesMarkdownContentEndpoint() async throws {
        KnowledgeAPIStubURLProtocol.responses = [
            .success("""
            {"data":{"content":"# Feishu Doc","title":"Feishu Doc","url":"https://example.feishu.cn/docx/doc123"}}
            """)
        ]
        let client = KnowledgeHTTPClient(session: KnowledgeAPIStubURLProtocol.makeSession())
        let connector = FeishuKnowledgeConnector(
            connectorInstanceID: "feishu-main",
            docToken: "doc123",
            bearerToken: "token",
            client: client
        )

        let snapshots = try await connector.fetchSnapshots()

        let snapshot = try XCTUnwrap(snapshots.first)
        XCTAssertEqual(snapshot.connectorInstanceID, "feishu-main")
        XCTAssertEqual(snapshot.connectorID, .feishuImport)
        XCTAssertEqual(snapshot.remoteID, "doc123")
        XCTAssertEqual(snapshot.title, "Feishu Doc")
        XCTAssertEqual(snapshot.remoteURL, "https://example.feishu.cn/docx/doc123")
        XCTAssertEqual(snapshot.mimeType, "text/markdown")
        XCTAssertEqual(snapshot.contentMarkdown, "# Feishu Doc")
        XCTAssertEqual(snapshot.originKind, "feishu-doc")

        let request = try XCTUnwrap(KnowledgeAPIStubURLProtocol.requests.first)
        XCTAssertEqual(request.url?.host, "open.feishu.cn")
        XCTAssertEqual(request.url?.path, "/open-apis/docs/v1/content")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token")
        let components = try XCTUnwrap(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.queryValue("doc_token"), "doc123")
        XCTAssertEqual(components.queryValue("doc_type"), "docx")
        XCTAssertEqual(components.queryValue("content_type"), "markdown")
    }

    func testNotionConvertsHeadingParagraphAndNestedBlocksToMarkdown() async throws {
        KnowledgeAPIStubURLProtocol.responses = [
            .success("""
            {"object":"list","results":[{"object":"page","id":"page-1","last_edited_time":"2026-05-21T00:00:00.000Z","url":"https://notion.so/page-1","properties":{"Name":{"type":"title","title":[{"plain_text":"Page One"}]}}}],"next_cursor":null,"has_more":false}
            """),
            .success("""
            {"object":"list","results":[{"object":"block","id":"h1","type":"heading_1","heading_1":{"rich_text":[{"plain_text":"Title"}]},"has_children":false},{"object":"block","id":"p1","type":"paragraph","paragraph":{"rich_text":[{"plain_text":"Body"}]},"has_children":true}],"next_cursor":null,"has_more":false}
            """),
            .success("""
            {"object":"list","results":[{"object":"block","id":"b1","type":"bulleted_list_item","bulleted_list_item":{"rich_text":[{"plain_text":"Nested"}]},"has_children":false}],"next_cursor":null,"has_more":false}
            """)
        ]
        let client = KnowledgeHTTPClient(session: KnowledgeAPIStubURLProtocol.makeSession())
        let connector = NotionKnowledgeConnector(
            connectorInstanceID: "notion-main",
            bearerToken: "token",
            client: client
        )

        let snapshots = try await connector.fetchSnapshots()

        let snapshot = try XCTUnwrap(snapshots.first)
        XCTAssertEqual(snapshot.connectorInstanceID, "notion-main")
        XCTAssertEqual(snapshot.connectorID, .notionImport)
        XCTAssertEqual(snapshot.remoteID, "page-1")
        XCTAssertEqual(snapshot.title, "Page One")
        XCTAssertEqual(snapshot.remoteURL, "https://notion.so/page-1")
        XCTAssertEqual(snapshot.remoteUpdatedAt, knowledgeAPIDate("2026-05-21T00:00:00.000Z"))
        XCTAssertEqual(snapshot.contentMarkdown, "# Title\n\nBody\n\n  - Nested")
        XCTAssertEqual(snapshot.originKind, "notion-page")

        XCTAssertEqual(KnowledgeAPIStubURLProtocol.requests.first?.url?.absoluteString, "https://api.notion.com/v1/search")
        XCTAssertEqual(KnowledgeAPIStubURLProtocol.requests.first?.httpMethod, "POST")
        XCTAssertEqual(KnowledgeAPIStubURLProtocol.requests.first?.value(forHTTPHeaderField: "Notion-Version"), "2026-03-11")
        XCTAssertEqual(KnowledgeAPIStubURLProtocol.requests[1].url?.path, "/v1/blocks/page-1/children")
        XCTAssertEqual(KnowledgeAPIStubURLProtocol.requests[2].url?.path, "/v1/blocks/p1/children")
    }

    func testGoogleDriveExportsGoogleDocAsMarkdownAndDownloadsTextFiles() async throws {
        KnowledgeAPIStubURLProtocol.responses = [
            .success("""
            {"files":[{"id":"file-1","name":"Doc One","mimeType":"application/vnd.google-apps.document","modifiedTime":"2026-05-21T00:00:00.000Z","webViewLink":"https://docs.google.com/document/d/file-1"},{"id":"file-2","name":"Notes.md","mimeType":"text/markdown","modifiedTime":"2026-05-20T00:00:00.000Z","webViewLink":"https://drive.google.com/file/d/file-2"}],"nextPageToken":null}
            """),
            .success("# Drive Doc"),
            .success("# Markdown File")
        ]
        let client = KnowledgeHTTPClient(session: KnowledgeAPIStubURLProtocol.makeSession())
        let connector = GoogleDriveKnowledgeConnector(
            connectorInstanceID: "drive-main",
            bearerToken: "token",
            client: client
        )

        let snapshots = try await connector.fetchSnapshots()

        XCTAssertEqual(snapshots.map(\.remoteID), ["file-1", "file-2"])
        XCTAssertEqual(snapshots.map(\.connectorID), [.googleDriveImport, .googleDriveImport])
        XCTAssertEqual(snapshots.map(\.title), ["Doc One", "Notes.md"])
        XCTAssertEqual(snapshots.map(\.contentMarkdown), ["# Drive Doc", "# Markdown File"])
        XCTAssertEqual(snapshots.map(\.originKind), ["google-drive-file", "google-drive-file"])

        let listRequest = try XCTUnwrap(KnowledgeAPIStubURLProtocol.requests.first)
        XCTAssertEqual(listRequest.url?.path, "/drive/v3/files")
        XCTAssertEqual(listRequest.value(forHTTPHeaderField: "Authorization"), "Bearer token")
        XCTAssertEqual(KnowledgeAPIStubURLProtocol.requests[1].url?.path, "/drive/v3/files/file-1/export")
        XCTAssertEqual(URLComponents(url: try XCTUnwrap(KnowledgeAPIStubURLProtocol.requests[1].url), resolvingAgainstBaseURL: false)?.queryValue("mimeType"), "text/markdown")
        XCTAssertEqual(KnowledgeAPIStubURLProtocol.requests[2].url?.path, "/drive/v3/files/file-2")
        XCTAssertEqual(URLComponents(url: try XCTUnwrap(KnowledgeAPIStubURLProtocol.requests[2].url), resolvingAgainstBaseURL: false)?.queryValue("alt"), "media")
    }

    func testHTTPClientMapsAuthorizationAndServerErrors() async throws {
        KnowledgeAPIStubURLProtocol.responses = [.status(401, "denied")]
        let client = KnowledgeHTTPClient(session: KnowledgeAPIStubURLProtocol.makeSession())

        await XCTAssertThrowsErrorAsync(
            _ = try await client.data(
                for: KnowledgeHTTPClient.bearerRequest(url: URL(string: "https://example.com")!, token: "token")
            )
        ) { error in
            XCTAssertEqual(
                error as? KnowledgeImportConnectorError,
                .unauthorized("Knowledge connector authorization failed.")
            )
        }
    }
}

private final class KnowledgeAPIStubURLProtocol: URLProtocol {
    enum Response {
        case success(String)
        case status(Int, String)
        case failure(Error)
    }

    nonisolated(unsafe) static var responses: [Response] = []
    nonisolated(unsafe) static var requests: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.requests.append(request)

        guard Self.responses.isEmpty == false else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        let response = Self.responses.removeFirst()
        switch response {
        case let .success(body):
            finish(statusCode: 200, body: body)
        case let .status(statusCode, body):
            finish(statusCode: statusCode, body: body)
        case let .failure(error):
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [KnowledgeAPIStubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    static func reset() {
        responses = []
        requests = []
    }

    private func finish(statusCode: Int, body: String) {
        let httpResponse = HTTPURLResponse(
            url: request.url ?? URL(string: "https://example.com")!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

private extension URLComponents {
    func queryValue(_ name: String) -> String? {
        queryItems?.first { $0.name == name }?.value
    }
}

private func knowledgeAPIDate(_ string: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.date(from: string)
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
