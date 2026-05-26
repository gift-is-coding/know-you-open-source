import Foundation

struct FeishuKnowledgeConnector: KnowledgeImportConnector {
    let connectorInstanceID: String
    let connectorID: KnowledgeConnectorID = .feishuImport

    private let docToken: String
    private let docType: String
    private let bearerToken: String
    private let client: KnowledgeHTTPClient

    init(
        connectorInstanceID: String,
        docToken: String,
        docType: String = "docx",
        bearerToken: String,
        client: KnowledgeHTTPClient = KnowledgeHTTPClient()
    ) {
        self.connectorInstanceID = connectorInstanceID
        self.docToken = docToken
        self.docType = docType
        self.bearerToken = bearerToken
        self.client = client
    }

    func fetchSnapshots() async throws -> [KnowledgeImportSnapshot] {
        guard let url = contentURL() else {
            throw KnowledgeImportConnectorError.invalidResponse("Cannot build Feishu document content URL.")
        }

        let request = KnowledgeHTTPClient.bearerRequest(url: url, token: bearerToken)
        let data = try await client.data(for: request)
        let response = try JSONDecoder().decode(FeishuContentResponse.self, from: data)
        return [
            KnowledgeImportSnapshot(
                connectorInstanceID: connectorInstanceID,
                connectorID: connectorID,
                remoteID: docToken,
                title: response.data.title ?? docToken,
                sourcePath: nil,
                remoteURL: response.data.url,
                mimeType: "text/markdown",
                contentMarkdown: response.data.content,
                remoteUpdatedAt: nil,
                originKind: "feishu-doc"
            )
        ]
    }

    private func contentURL() -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "open.feishu.cn"
        components.path = "/open-apis/docs/v1/content"
        components.queryItems = [
            URLQueryItem(name: "doc_token", value: docToken),
            URLQueryItem(name: "doc_type", value: docType),
            URLQueryItem(name: "content_type", value: "markdown")
        ]
        return components.url
    }
}

private struct FeishuContentResponse: Decodable {
    var data: Payload

    struct Payload: Decodable {
        var content: String
        var title: String?
        var url: String?
    }
}
