import Foundation

struct NetworkingProfileContext: Codable, Equatable {
    let summary: String
    let citations: [String]
}

struct NetworkingGeneratedProfileContent: Codable, Equatable {
    let summary: String
    let sections: [NetworkingProfileSummarySection]
}

enum NetworkingProfileGenerationError: Error, LocalizedError, Equatable {
    case myWikiUnavailable
    case emptyLLMOutput
    case llmFailed(String)

    var errorDescription: String? {
        switch self {
        case .myWikiUnavailable:
            return "My Wiki context is not available."
        case .emptyLLMOutput:
            return "The profile generator returned empty output."
        case .llmFailed(let message):
            return message
        }
    }
}

protocol NetworkingMyWikiContextProviding: Sendable {
    func context(for scenario: NetworkingProfileScenario, prompt: String, projectRoot: URL) throws -> NetworkingProfileContext
}

protocol NetworkingLLMProfileGenerating: Sendable {
    func generateProfile(
        scenario: NetworkingProfileScenario,
        prompt: String,
        personName: String,
        context: NetworkingProfileContext
    ) async throws -> NetworkingGeneratedProfileContent
}

struct MyWikiNetworkingContextProvider: NetworkingMyWikiContextProviding, @unchecked Sendable {
    let contextPackService: MyWikiContextPackService

    init(contextPackService: MyWikiContextPackService = MyWikiContextPackService()) {
        self.contextPackService = contextPackService
    }

    func context(for scenario: NetworkingProfileScenario, prompt: String, projectRoot: URL) throws -> NetworkingProfileContext {
        let pack = contextPackService.contextPack(
            for: MyWikiContextPackRequest(
                projectRoot: projectRoot,
                query: "\(scenario.label)\n\(scenario.description)\n\(prompt)",
                maxItems: 8,
                characterBudget: 8_000
            )
        )
        guard pack.items.isEmpty == false else {
            throw NetworkingProfileGenerationError.myWikiUnavailable
        }

        let summary = pack.items.map { item in
            "- \(item.title): \(item.excerpt)"
        }
        .joined(separator: "\n")
        return NetworkingProfileContext(
            summary: summary,
            citations: pack.citations.map(\.relativePath)
        )
    }
}

struct NetworkingPromptProfileGenerator: NetworkingLLMProfileGenerating {
    let summarizer: any SummaryGenerating

    private static let profileSchema = """
    {"type":"object","additionalProperties":false,"required":["summary","sections"],"properties":{"summary":{"type":"string"},"sections":{"type":"array","minItems":1,"maxItems":4,"items":{"type":"object","additionalProperties":false,"required":["title","body"],"properties":{"title":{"type":"string"},"body":{"type":"string"}}}}}}
    """

    func generateProfile(
        scenario: NetworkingProfileScenario,
        prompt: String,
        personName: String,
        context: NetworkingProfileContext
    ) async throws -> NetworkingGeneratedProfileContent {
        let input = """
        你在为 KnowYou Networking 生成公开 profile 草稿。
        人名：\(personName)
        场景：\(scenario.label)
        用户 prompt：\(prompt)

        My Wiki context:
        \(context.summary)

        请输出一段公开摘要。不要包含 My Wiki 原始证据、私有匹配理由、账号、token 或完整原文。
        """
        let raw: String
        if let jsonSummarizer = summarizer as? any JSONSummaryGenerating {
            raw = try await jsonSummarizer.summarizeJSON(
                dayKey: "networking-\(scenario.id)",
                prompt: input,
                schema: Self.profileSchema,
                context: .manualRefresh
            )
        } else {
            raw = try await summarizer.summarize(dayKey: scenario.id, markdown: input, context: .manualRefresh)
        }

        let content = Self.profileContent(from: raw, fallbackTitle: scenario.label)
        let text = content.summary
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.isEmpty == false else {
            throw NetworkingProfileGenerationError.emptyLLMOutput
        }

        return NetworkingGeneratedProfileContent(
            summary: text,
            sections: content.sections
        )
    }

    private static func profileContent(from raw: String, fallbackTitle: String) -> NetworkingGeneratedProfileContent {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8) else {
            return oneSection(summary: trimmed, title: fallbackTitle)
        }

        if let payload = try? JSONDecoder().decode(NetworkingProfilePayload.self, from: data) {
            let summary = payload.summary.trimmingCharacters(in: .whitespacesAndNewlines)
            let sections = payload.sections
                .map { NetworkingProfileSummarySection(title: $0.title, body: $0.body) }
                .filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !$0.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            return NetworkingGeneratedProfileContent(
                summary: summary,
                sections: sections.isEmpty ? oneSection(summary: summary, title: fallbackTitle).sections : sections
            )
        }

        if let story = try? JSONDecoder().decode(NetworkingStoryPayload.self, from: data) {
            let text = story.sections
                .flatMap(\.paragraphs)
                .map(\.text)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n\n")
            return oneSection(summary: text, title: fallbackTitle)
        }

        return oneSection(summary: trimmed, title: fallbackTitle)
    }

    private static func oneSection(summary: String, title: String) -> NetworkingGeneratedProfileContent {
        NetworkingGeneratedProfileContent(
            summary: summary,
            sections: [
                NetworkingProfileSummarySection(title: title, body: summary)
            ]
        )
    }
}

private struct NetworkingProfilePayload: Decodable {
    let summary: String
    let sections: [NetworkingProfilePayloadSection]
}

private struct NetworkingProfilePayloadSection: Decodable {
    let title: String
    let body: String
}

private struct NetworkingStoryPayload: Decodable {
    let sections: [NetworkingStorySection]
}

private struct NetworkingStorySection: Decodable {
    let paragraphs: [NetworkingStoryParagraph]
}

private struct NetworkingStoryParagraph: Decodable {
    let text: String
}

struct NetworkingProfileGenerationService: Sendable {
    let contextProvider: any NetworkingMyWikiContextProviding
    let generator: any NetworkingLLMProfileGenerating

    init(
        contextProvider: any NetworkingMyWikiContextProviding = MyWikiNetworkingContextProvider(),
        generator: any NetworkingLLMProfileGenerating
    ) {
        self.contextProvider = contextProvider
        self.generator = generator
    }

    func generateDraft(
        scenario: NetworkingProfileScenario,
        prompt: String,
        personName: String,
        projectRoot: URL
    ) async throws -> NetworkingProfileDraft {
        let context = try contextProvider.context(for: scenario, prompt: prompt, projectRoot: projectRoot)
        let content = try await generator.generateProfile(
            scenario: scenario,
            prompt: prompt,
            personName: personName,
            context: context
        )
        let body = """
        \(content.sections.map { "## \($0.title)\n\($0.body)" }.joined(separator: "\n\n"))

        Public citations:
        \(context.citations.joined(separator: "\n"))
        """

        return NetworkingProfileDraft(
            id: "profile-\(scenario.id)",
            personName: personName,
            profileLabel: scenario.label,
            summary: content.summary,
            body: body,
            source: .myWiki,
            approvalStatus: .draft
        )
    }
}
