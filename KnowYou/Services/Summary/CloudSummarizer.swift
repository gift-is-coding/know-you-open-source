import Foundation

enum SummaryInvocationContext: Sendable, Equatable {
    case manualRefresh
    case automationRefresh
    case defaultBehavior
}

protocol SummaryGenerating: Sendable {
    func summarize(dayKey: String, markdown: String, context: SummaryInvocationContext) async throws -> String
}

extension SummaryGenerating {
    func summarize(dayKey: String, markdown: String) async throws -> String {
        try await summarize(dayKey: dayKey, markdown: markdown, context: .defaultBehavior)
    }
}

struct CloudSummarizer: SummaryGenerating {
    let apiKey: String
    let apiURL: URL
    let session: URLSession
    let model: String

    init(
        apiKey: String,
        apiURL: URL = URL(string: "https://api.openai.com/v1/responses")!,
        session: URLSession = .shared,
        model: String = "gpt-5"
    ) {
        self.apiKey = apiKey
        self.apiURL = apiURL
        self.session = session
        self.model = model
    }

    func summarize(dayKey: String, markdown: String, context: SummaryInvocationContext) async throws -> String {
        var request = URLRequest(url: apiURL)
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

struct ResponsesResponse: Decodable {
    let outputText: String?
    let output: [ResponseOutputItem]?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let directOutputText = try container.decodeIfPresent(String.self, forKey: .outputText)
        let output = try container.decodeIfPresent([ResponseOutputItem].self, forKey: .output)
        self.output = output
        self.outputText = directOutputText ?? output?
            .filter { $0.type == "message" }
            .flatMap(\.content)
            .filter { $0.type == "output_text" }
            .map(\.text)
            .joined(separator: "\n")
    }

    enum CodingKeys: String, CodingKey {
        case outputText = "output_text"
        case output
    }
}

struct ResponseOutputItem: Decodable {
    let type: String
    let content: [ResponseOutputContent]
}

struct ResponseOutputContent: Decodable {
    let type: String
    let text: String
}
