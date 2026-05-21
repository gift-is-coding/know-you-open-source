import Foundation

struct KnowledgeHTTPClient: @unchecked Sendable {
    let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func data(for request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw KnowledgeImportConnectorError.invalidResponse("Knowledge connector response was not HTTP.")
        }

        switch httpResponse.statusCode {
        case 200..<300:
            return data
        case 401, 403:
            throw KnowledgeImportConnectorError.unauthorized("Knowledge connector authorization failed.")
        default:
            throw KnowledgeImportConnectorError.unavailable(
                "Knowledge connector request failed with HTTP \(httpResponse.statusCode)."
            )
        }
    }

    static func bearerRequest(
        url: URL,
        token: String,
        method: String = "GET"
    ) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }
}
