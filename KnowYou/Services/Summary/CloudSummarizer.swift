import Foundation

protocol SummaryGenerating: Sendable {
    func summarize(dayKey: String, markdown: String) async throws -> String
}

struct CloudSummarizer: SummaryGenerating {
    let apiKey: String
    let session: URLSession
    let model: String

    init(apiKey: String, session: URLSession = .shared, model: String = "gpt-5") {
        self.apiKey = apiKey
        self.session = session
        self.model = model
    }

    func summarize(dayKey: String, markdown: String) async throws -> String {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            ResponsesRequest(
                model: model,
                input: "Summarize this day as a concise diary entry for \(dayKey):\n\n\(markdown)"
            )
        )

        let (data, response) = try await session.data(for: request)
        guard
            let httpResponse = response as? HTTPURLResponse,
            (200..<300).contains(httpResponse.statusCode)
        else {
            throw URLError(.badServerResponse)
        }

        let payload = try JSONDecoder().decode(ResponsesResponse.self, from: data)
        return payload.outputText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Summary unavailable."
    }
}

private struct ResponsesRequest: Encodable {
    let model: String
    let input: String
}

private struct ResponsesResponse: Decodable {
    let outputText: String?

    enum CodingKeys: String, CodingKey {
        case outputText = "output_text"
    }
}
