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

    var errorDescription: String? {
        switch self {
        case .myWikiUnavailable:
            return "My Wiki context is not available."
        case .emptyLLMOutput:
            return "The profile generator returned empty output."
        }
    }
}

protocol NetworkingMyWikiContextProviding {
    func context(for scenario: NetworkingProfileScenario, prompt: String, projectRoot: URL) throws -> NetworkingProfileContext
}

protocol NetworkingLLMProfileGenerating {
    func generateProfile(
        scenario: NetworkingProfileScenario,
        prompt: String,
        personName: String,
        context: NetworkingProfileContext
    ) async throws -> NetworkingGeneratedProfileContent
}

struct MyWikiNetworkingContextProvider: NetworkingMyWikiContextProviding {
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
        let text = try await summarizer.summarize(dayKey: scenario.id, markdown: input, context: .manualRefresh)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.isEmpty == false else {
            throw NetworkingProfileGenerationError.emptyLLMOutput
        }

        return NetworkingGeneratedProfileContent(
            summary: text,
            sections: [
                NetworkingProfileSummarySection(title: scenario.label, body: text)
            ]
        )
    }
}

struct NetworkingProfileGenerationService {
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
