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
    case noNewMyWikiMaterial
    case emptyLLMOutput
    case llmFailed(String)

    var errorDescription: String? {
        switch self {
        case .myWikiUnavailable:
            return "My Wiki context is not available."
        case .noNewMyWikiMaterial:
            return "No new My Wiki material since the last profile update."
        case .emptyLLMOutput:
            return "The profile generator returned empty output."
        case .llmFailed(let message):
            return message
        }
    }
}

protocol NetworkingMyWikiContextProviding: Sendable {
    func context(for scenario: NetworkingProfileScenario, prompt: String, projectRoot: URL) throws -> NetworkingProfileContext
    func context(for scenario: NetworkingProfileScenario, prompt: String, projectRoot: URL, changedAfter: Date?) throws -> NetworkingProfileContext
}

extension NetworkingMyWikiContextProviding {
    func context(for scenario: NetworkingProfileScenario, prompt: String, projectRoot: URL, changedAfter: Date?) throws -> NetworkingProfileContext {
        try context(for: scenario, prompt: prompt, projectRoot: projectRoot)
    }
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
    let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func context(for scenario: NetworkingProfileScenario, prompt: String, projectRoot: URL) throws -> NetworkingProfileContext {
        try context(for: scenario, prompt: prompt, projectRoot: projectRoot, changedAfter: nil)
    }

    func context(
        for scenario: NetworkingProfileScenario,
        prompt: String,
        projectRoot: URL,
        changedAfter: Date?
    ) throws -> NetworkingProfileContext {
        let lens = NetworkingProfileMemoryLens(scenario: scenario, prompt: prompt)
        let files = wikiMarkdownFiles(in: projectRoot, changedAfter: changedAfter)
        if changedAfter != nil, files.isEmpty {
            throw NetworkingProfileGenerationError.noNewMyWikiMaterial
        }

        let candidates = files
            .compactMap { page(from: $0, projectRoot: projectRoot) }
            .compactMap { candidate(for: $0, lens: lens) }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score {
                    return lhs.score > rhs.score
                }
                return lhs.page.relativePath < rhs.page.relativePath
            }

        var remainingBudget = 16_000
        var selected: [NetworkingProfileMemoryCandidate] = []
        for candidate in candidates {
            guard selected.count < 18, remainingBudget > 0 else { break }
            let excerpt = Self.trim(candidate.excerpt, maxCharacters: min(candidate.excerpt.count, remainingBudget))
            guard excerpt.isEmpty == false else { continue }
            selected.append(candidate.withExcerpt(excerpt))
            remainingBudget -= excerpt.count
        }

        guard selected.isEmpty == false else {
            throw changedAfter == nil
                ? NetworkingProfileGenerationError.myWikiUnavailable
                : NetworkingProfileGenerationError.noNewMyWikiMaterial
        }

        let contextSummary: String = selected.map { candidate in
            let terms = candidate.matchedTerms.prefix(8).joined(separator: ", ")
            return String(
                """
            - \(candidate.page.title) [\(candidate.page.relativePath)]
              type: \(candidate.page.pageType)
              matched: \(terms)
              excerpt: \(candidate.excerpt)
            """
            )
        }
        .joined(separator: "\n")
        return NetworkingProfileContext(
            summary: contextSummary,
            citations: selected.map(\.page.relativePath)
        )
    }

    private func wikiMarkdownFiles(in projectRoot: URL, changedAfter: Date?) -> [URL] {
        let wikiRoot = projectRoot.appending(path: "wiki", directoryHint: .isDirectory)
        guard let enumerator = fileManager.enumerator(
            at: wikiRoot,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return enumerator.compactMap { element in
            guard let url = element as? URL, url.pathExtension == "md" else { return nil }
            if let changedAfter {
                let modifiedAt = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                guard let modifiedAt, modifiedAt > changedAfter else { return nil }
            }
            return url
        }
    }

    private func page(from url: URL, projectRoot: URL) -> NetworkingProfileMemoryPage? {
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let parsed = Self.parseMarkdown(contents, fileName: url.lastPathComponent)
        let relativePath = Self.relativePath(from: projectRoot, to: url)
        guard Self.isAllowedMemoryPage(relativePath: relativePath) else { return nil }

        return NetworkingProfileMemoryPage(
            title: parsed.title,
            pageType: parsed.frontmatter["type"] ?? Self.pageType(from: relativePath),
            frontmatter: parsed.frontmatter,
            body: parsed.body,
            relativePath: relativePath
        )
    }

    private static func isAllowedMemoryPage(relativePath: String) -> Bool {
        [
            "wiki/concepts/",
            "wiki/entities/",
            "wiki/synthesis/",
            "wiki/comparisons/",
            "wiki/queries/",
        ].contains { relativePath.hasPrefix($0) }
    }

    private func candidate(
        for page: NetworkingProfileMemoryPage,
        lens: NetworkingProfileMemoryLens
    ) -> NetworkingProfileMemoryCandidate? {
        let searchableTitle = page.title.lowercased()
        let searchablePath = page.relativePath.lowercased()
        let searchableType = page.pageType.lowercased()
        let searchableMetadata = page.frontmatter
            .map { "\($0.key) \($0.value)" }
            .joined(separator: " ")
            .lowercased()
        let searchableBody = page.body.lowercased()

        var score = 0
        var matchedTerms: [String] = []

        for term in lens.terms {
            let termScore = scoreTerm(
                term,
                title: searchableTitle,
                path: searchablePath,
                type: searchableType,
                metadata: searchableMetadata,
                body: searchableBody
            )
            if termScore > 0 {
                score += termScore
                matchedTerms.append(term)
            }
        }

        guard score > 0 else { return nil }
        score += rootBoost(for: page.relativePath)
        score += typeBoost(for: page.pageType)
        if page.relativePath == "wiki/index.md" || page.relativePath == "wiki/overview.md" {
            score -= 30
        }

        let excerpt = Self.excerpt(from: page.body, matching: matchedTerms)
        guard excerpt.isEmpty == false else { return nil }

        return NetworkingProfileMemoryCandidate(
            page: page,
            score: score,
            matchedTerms: Self.uniquePreservingOrder(matchedTerms),
            excerpt: excerpt
        )
    }

    private func scoreTerm(
        _ term: String,
        title: String,
        path: String,
        type: String,
        metadata: String,
        body: String
    ) -> Int {
        let normalized = term.lowercased()
        var score = 0
        if title.contains(normalized) { score += 120 }
        if metadata.contains(normalized) { score += 90 }
        if path.contains(normalized) { score += 70 }
        if type.contains(normalized) { score += 30 }
        score += min(Self.occurrenceCount(of: normalized, in: body), 6) * 14
        return score
    }

    private func rootBoost(for relativePath: String) -> Int {
        if relativePath.hasPrefix("wiki/concepts/") { return 45 }
        if relativePath.hasPrefix("wiki/entities/") { return 40 }
        if relativePath.hasPrefix("wiki/synthesis/") { return 35 }
        if relativePath.hasPrefix("wiki/sources/") { return 15 }
        return 0
    }

    private func typeBoost(for pageType: String) -> Int {
        switch pageType.lowercased() {
        case "concept":
            return 30
        case "entity":
            return 25
        case "synthesis":
            return 20
        default:
            return 0
        }
    }

    private static func parseMarkdown(
        _ markdown: String,
        fileName: String
    ) -> (frontmatter: [String: String], title: String, body: String) {
        var frontmatter: [String: String] = [:]
        var body = markdown

        if markdown.hasPrefix("---\n"),
           let endRange = markdown.range(of: "\n---", range: markdown.index(markdown.startIndex, offsetBy: 4)..<markdown.endIndex) {
            let frontmatterText = String(markdown[markdown.index(markdown.startIndex, offsetBy: 4)..<endRange.lowerBound])
            frontmatter = parseFrontmatter(frontmatterText)
            let bodyStart = markdown.index(
                endRange.upperBound,
                offsetBy: markdown[endRange.upperBound...].first == "\n" ? 1 : 0,
                limitedBy: markdown.endIndex
            ) ?? endRange.upperBound
            body = String(markdown[bodyStart...])
        }

        let title = frontmatter["title"]
            ?? firstMarkdownHeading(in: body)
            ?? fileName.replacingOccurrences(of: ".md", with: "").replacingOccurrences(of: "-", with: " ")

        return (frontmatter, title, body)
    }

    private static func parseFrontmatter(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in text.components(separatedBy: .newlines) {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespacesAndNewlines)
            let valueStart = line.index(after: colon)
            let value = line[valueStart...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            guard key.isEmpty == false, value.isEmpty == false else { continue }
            result[key] = value
        }
        return result
    }

    private static func firstMarkdownHeading(in body: String) -> String? {
        body.components(separatedBy: .newlines)
            .first { $0.hasPrefix("# ") }?
            .dropFirst(2)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func pageType(from relativePath: String) -> String {
        if relativePath.hasPrefix("wiki/concepts/") { return "concept" }
        if relativePath.hasPrefix("wiki/entities/") { return "entity" }
        if relativePath.hasPrefix("wiki/synthesis/") { return "synthesis" }
        if relativePath.hasPrefix("wiki/sources/") { return "source" }
        return "wiki"
    }

    private static func excerpt(from body: String, matching terms: [String]) -> String {
        let normalizedBody = body.lowercased()
        let paragraphs = body
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }

        let paragraph = paragraphs.first { paragraph in
            let normalized = paragraph.lowercased()
            return terms.contains { normalized.contains($0.lowercased()) }
        } ?? paragraphs.first ?? body

        if let term = terms.first(where: { normalizedBody.contains($0.lowercased()) }),
           let range = body.range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) {
            let lowerBound = body.index(range.lowerBound, offsetBy: -260, limitedBy: body.startIndex) ?? body.startIndex
            let upperBound = body.index(range.upperBound, offsetBy: 520, limitedBy: body.endIndex) ?? body.endIndex
            return trim(String(body[lowerBound..<upperBound]), maxCharacters: 900)
        }

        return trim(paragraph, maxCharacters: 900)
    }

    private static func trim(_ text: String, maxCharacters: Int) -> String {
        let collapsed = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard collapsed.count > maxCharacters else { return collapsed }
        let index = collapsed.index(collapsed.startIndex, offsetBy: max(0, maxCharacters - 1))
        return String(collapsed[..<index]).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }

    private static func occurrenceCount(of needle: String, in haystack: String) -> Int {
        guard needle.isEmpty == false else { return 0 }
        var count = 0
        var searchRange = haystack.startIndex..<haystack.endIndex
        while let range = haystack.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive], range: searchRange) {
            count += 1
            searchRange = range.upperBound..<haystack.endIndex
        }
        return count
    }

    private static func relativePath(from root: URL, to url: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let filePath = url.standardizedFileURL.path
        guard filePath.hasPrefix(rootPath) else { return url.lastPathComponent }
        let relative = filePath.dropFirst(rootPath.count)
        return relative.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private static func uniquePreservingOrder(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for value in values where !seen.contains(value) {
            seen.insert(value)
            result.append(value)
        }
        return result
    }
}

private struct NetworkingProfileMemoryLens {
    let terms: [String]

    init(scenario: NetworkingProfileScenario, prompt: String) {
        let fixedTerms: [String]
        switch scenario.id {
        case NetworkingProfileScenario.jobs.id:
            fixedTerms = [
                "career", "hiring", "job", "role", "work", "project", "product", "engineer",
                "engineering", "software", "agent", "ai", "enterprise", "platform", "collaboration",
                "collaborator", "founder", "team", "swiftui", "next.js", "supabase", "mcp",
                "职业", "求职", "招聘", "工作", "项目", "产品", "工程", "平台", "智能体",
                "企业", "合作", "团队", "候选人", "机会", "负责", "能力", "架构", "研发",
            ]
        case NetworkingProfileScenario.friends.id:
            fixedTerms = [
                "friends", "friend", "social", "personal", "interest", "interests", "hobby",
                "hobbies", "activity", "activities", "weekend", "food", "city", "music",
                "movie", "coffee", "conversation", "personality", "lifestyle", "rhythm",
                "creative", "meet", "meeting",
                "朋友", "认识", "社交", "兴趣", "爱好", "活动", "生活", "性格", "节奏",
                "城市", "美食", "咖啡", "旅行", "娱乐", "聊天", "个人", "日常",
            ]
        default:
            fixedTerms = []
        }

        let queryTerms = Self.tokenTerms(from: "\(scenario.label) \(scenario.description) \(prompt)")
        terms = Self.uniquePreservingOrder(fixedTerms + queryTerms)
    }

    private static func tokenTerms(from text: String) -> [String] {
        var terms: [String] = []
        var latin = ""
        var cjk = ""

        func flushLatin() {
            if latin.count > 2, englishStopWords.contains(latin) == false {
                terms.append(latin)
            }
            latin = ""
        }

        func flushCJK() {
            if cjk.isEmpty == false {
                terms.append(cjk)
                terms.append(contentsOf: cjkNgrams(from: cjk))
            }
            cjk = ""
        }

        for character in text.lowercased() {
            if isCJK(character) {
                flushLatin()
                cjk.append(character)
            } else if character.isLetter || character.isNumber || character == "." {
                flushCJK()
                latin.append(character)
            } else {
                flushLatin()
                flushCJK()
            }
        }
        flushLatin()
        flushCJK()

        return uniquePreservingOrder(terms)
    }

    private static func cjkNgrams(from text: String) -> [String] {
        let characters = Array(text)
        guard characters.count > 1 else { return [] }
        var terms: [String] = []
        for size in [2, 3, 4] where characters.count >= size {
            for index in 0...(characters.count - size) {
                terms.append(String(characters[index..<(index + size)]))
            }
        }
        return terms.filter { cjkStopTerms.contains($0) == false }
    }

    private static func isCJK(_ character: Character) -> Bool {
        character.unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(Int(scalar.value))
        }
    }

    private static var englishStopWords: Set<String> {
        [
            "and", "are", "for", "from", "generate", "profile", "the", "with", "you", "your",
            "about", "into", "what", "when", "where", "this", "that", "should", "public",
        ]
    }

    private static var cjkStopTerms: Set<String> {
        ["结合", "总结", "用于", "覆盖", "生成", "不同", "一个", "什么", "我的"]
    }

    private static func uniquePreservingOrder(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for value in values where !seen.contains(value) {
            seen.insert(value)
            result.append(value)
        }
        return result
    }
}

private struct NetworkingProfileMemoryPage {
    let title: String
    let pageType: String
    let frontmatter: [String: String]
    let body: String
    let relativePath: String
}

private struct NetworkingProfileMemoryCandidate {
    let page: NetworkingProfileMemoryPage
    let score: Int
    let matchedTerms: [String]
    let excerpt: String

    func withExcerpt(_ excerpt: String) -> NetworkingProfileMemoryCandidate {
        NetworkingProfileMemoryCandidate(
            page: page,
            score: score,
            matchedTerms: matchedTerms,
            excerpt: excerpt
        )
    }
}

struct NetworkingPromptProfileGenerator: NetworkingLLMProfileGenerating {
    let summarizer: any SummaryGenerating

    private static let profileSchema = """
    {"type":"object","additionalProperties":false,"required":["summary","sections"],"properties":{"summary":{"type":"string"},"sections":{"type":"array","minItems":6,"maxItems":10,"items":{"type":"object","additionalProperties":false,"required":["title","body"],"properties":{"title":{"type":"string"},"body":{"type":"string"}}}}}}
    """

    func generateProfile(
        scenario: NetworkingProfileScenario,
        prompt: String,
        personName: String,
        context: NetworkingProfileContext
    ) async throws -> NetworkingGeneratedProfileContent {
        let scenarioLens = Self.scenarioLensName(for: scenario)
        let input = """
        You are generating a KnowYou Networking public profile draft.

        Output language: English
        Scenario lens: \(scenarioLens)
        Person: \(personName)
        User intent: \(prompt)

        Write a public profile that helps another human decide whether to start a career, hiring, collaboration, or social conversation with this person.
        Write a long-form profile: target 2,000 to 3,000 words across 6 to 10 titled sections. Treat the summary as the executive overview, and the sections as the full original profile text a human can review before approval.
        Use third-person public profile prose. Do not write a diary entry, daily recap, private reflection, or first-person journal.
        Use only the My Wiki memory context below. Use the citations only as grounding.
        Do not include raw My Wiki evidence.
        Do not include deep matching reasons.
        Do not invent facts that are not supported by the memory context.
        If public-safe evidence is sparse for this scenario, say that the available public-safe memory mainly supports a narrower profile instead of inventing hobbies, relationships, or lifestyle claims.
        Redact contact info, account handles, exact locations, private relationships, health or finance details, raw diary or notification text, tokens, account details, and unconfirmed claims.

        For Career / Hiring, emphasize what the person can own, projects or systems they understand, work style, collaboration fit, useful opportunities or candidates, and concrete evidence signals.
        For Friends / Social, emphasize interests, social rhythm, activities, personality, conversation starters, and comfortable ways to begin a conversation.
        Across all scenarios, include the profile's public positioning, scenario fit, strengths, working or social style, examples, boundaries, unknowns, and safe ways another person can reach out.

        My Wiki memory context:
        \(context.summary)

        Return JSON matching the provided schema exactly. Keep the summary specific, grounded, and public-safe. Make each section substantive and evidence-grounded; do not pad with generic biography.
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

    private static func scenarioLensName(for scenario: NetworkingProfileScenario) -> String {
        switch scenario.id {
        case NetworkingProfileScenario.jobs.id:
            return "Career / Hiring"
        case NetworkingProfileScenario.friends.id:
            return "Friends / Social"
        default:
            return scenario.label.isEmpty ? "Custom Profile" : scenario.label
        }
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

        if let diaryEntry = try? JSONDecoder().decode(NetworkingDiaryEntryPayload.self, from: data) {
            let text = diaryEntry.diaryEntry.trimmingCharacters(in: .whitespacesAndNewlines)
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

private struct NetworkingDiaryEntryPayload: Decodable {
    let diaryEntry: String

    private enum CodingKeys: String, CodingKey {
        case diaryEntry = "diary_entry"
    }
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
        projectRoot: URL,
        draftID: String? = nil,
        existingDraft: NetworkingProfileDraft? = nil,
        changedAfter: Date? = nil,
        now: Date = Date()
    ) async throws -> NetworkingProfileDraft {
        let context = try contextProvider.context(
            for: scenario,
            prompt: prompt,
            projectRoot: projectRoot,
            changedAfter: changedAfter
        )
        let generationPrompt = Self.prompt(
            basePrompt: prompt,
            existingDraft: existingDraft,
            changedAfter: changedAfter
        )
        let content = try await generator.generateProfile(
            scenario: scenario,
            prompt: generationPrompt,
            personName: personName,
            context: context
        )
        let body = content.sections
            .map { "## \($0.title)\n\($0.body)" }
            .joined(separator: "\n\n")

        return NetworkingProfileDraft(
            id: draftID ?? "profile-\(scenario.id)",
            personName: personName,
            profileLabel: scenario.label,
            summary: content.summary,
            body: body,
            source: .myWiki,
            approvalStatus: .draft,
            citations: context.citations,
            generatedAt: existingDraft?.generatedAt ?? now,
            updatedAt: now
        )
    }

    private static func prompt(
        basePrompt: String,
        existingDraft: NetworkingProfileDraft?,
        changedAfter: Date?
    ) -> String {
        guard let existingDraft else { return basePrompt }
        let sinceText = changedAfter.map { ISO8601DateFormatter().string(from: $0) } ?? "the previous update"
        return """
        \(basePrompt)

        Update mode:
        Use only the new My Wiki material since \(sinceText) to revise the existing public profile.
        Preserve stable public-safe positioning from the existing profile unless the new material clearly changes it.
        Return a complete updated profile draft, not a patch.

        Existing profile summary:
        \(existingDraft.summary)

        Existing profile body:
        \(existingDraft.body)
        """
    }
}

struct NetworkingProfileDraftCommandResult: Equatable {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}

struct NetworkingProfileDraftCommand {
    static let launchArgument = "--networking-profile-draft"

    static func run(
        arguments: [String],
        summarizer: (any SummaryGenerating)? = nil
    ) -> NetworkingProfileDraftCommandResult {
        let box = NetworkingProfileDraftCommandResultBox()
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            let result = await runAsync(arguments: arguments, summarizer: summarizer)
            box.set(result)
            semaphore.signal()
        }
        semaphore.wait()
        return box.get() ?? NetworkingProfileDraftCommandResult(
            exitCode: 1,
            stdout: "",
            stderr: "Failed to generate Networking profile draft.\n"
        )
    }

    static func runAsync(
        arguments: [String],
        summarizer: (any SummaryGenerating)? = nil
    ) async -> NetworkingProfileDraftCommandResult {
        do {
            let configuration = try parse(arguments: arguments)
            if configuration.showsHelp {
                return NetworkingProfileDraftCommandResult(exitCode: 0, stdout: "", stderr: usage())
            }

            let activeSummarizer = summarizer ?? SummarizerConfig.load().makeSummarizer()
            guard let activeSummarizer else {
                return NetworkingProfileDraftCommandResult(
                    exitCode: 1,
                    stdout: "",
                    stderr: "No Diary Engine is configured for profile generation. Configure an LLM engine, then retry.\n"
                )
            }

            let service = NetworkingProfileGenerationService(
                generator: NetworkingPromptProfileGenerator(summarizer: activeSummarizer)
            )
            let draft = try await service.generateDraft(
                scenario: configuration.scenario,
                prompt: configuration.prompt,
                personName: configuration.personName,
                projectRoot: configuration.projectRoot
            )

            let encoder = JSONEncoder()
            if configuration.prettyPrint {
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            }
            let data = try encoder.encode(draft)
            return NetworkingProfileDraftCommandResult(
                exitCode: 0,
                stdout: String(decoding: data, as: UTF8.self) + "\n",
                stderr: ""
            )
        } catch let error as NetworkingProfileDraftCommandError {
            return NetworkingProfileDraftCommandResult(
                exitCode: 2,
                stdout: "",
                stderr: error.localizedDescription + "\n\n" + usage()
            )
        } catch {
            return NetworkingProfileDraftCommandResult(
                exitCode: 1,
                stdout: "",
                stderr: "Failed to generate Networking profile draft: \(error.localizedDescription)\n"
            )
        }
    }

    private static func parse(arguments: [String]) throws -> NetworkingProfileDraftCommandConfiguration {
        var projectRoot: URL?
        var scenarioRawValue: String?
        var personName: String?
        var prompt: String?
        var prettyPrint = false
        var showsHelp = false

        var index = 1
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case launchArgument:
                index += 1
            case "--project-root":
                projectRoot = URL(fileURLWithPath: try value(after: argument, in: arguments, index: index))
                index += 2
            case "--scenario":
                scenarioRawValue = try value(after: argument, in: arguments, index: index)
                index += 2
            case "--person-name":
                personName = try value(after: argument, in: arguments, index: index)
                index += 2
            case "--prompt":
                prompt = try value(after: argument, in: arguments, index: index)
                index += 2
            case "--pretty":
                prettyPrint = true
                index += 1
            case "--help", "-h":
                showsHelp = true
                index += 1
            default:
                throw NetworkingProfileDraftCommandError.unknownOption(argument)
            }
        }

        if showsHelp {
            return NetworkingProfileDraftCommandConfiguration(
                projectRoot: URL(fileURLWithPath: "."),
                scenario: .jobs,
                prompt: NetworkingProfileScenario.jobs.prompt,
                personName: "",
                prettyPrint: prettyPrint,
                showsHelp: true
            )
        }

        guard let projectRoot else {
            throw NetworkingProfileDraftCommandError.missingRequiredOption("--project-root")
        }
        guard let scenarioRawValue else {
            throw NetworkingProfileDraftCommandError.missingRequiredOption("--scenario")
        }
        guard let personName,
              personName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw NetworkingProfileDraftCommandError.missingRequiredOption("--person-name")
        }

        let scenario = try scenario(from: scenarioRawValue)
        return NetworkingProfileDraftCommandConfiguration(
            projectRoot: projectRoot,
            scenario: scenario,
            prompt: prompt ?? scenario.prompt,
            personName: personName,
            prettyPrint: prettyPrint,
            showsHelp: false
        )
    }

    private static func scenario(from rawValue: String) throws -> NetworkingProfileScenario {
        switch rawValue.lowercased() {
        case "jobs", "job", "career", "careers", "hiring", NetworkingProfileScenario.jobs.id:
            return .jobs
        case "friends", "friend", "social", "personal", NetworkingProfileScenario.friends.id:
            return .friends
        default:
            throw NetworkingProfileDraftCommandError.unsupportedScenario(rawValue)
        }
    }

    private static func value(after option: String, in arguments: [String], index: Int) throws -> String {
        let valueIndex = index + 1
        guard valueIndex < arguments.count else {
            throw NetworkingProfileDraftCommandError.missingValue(option)
        }
        let value = arguments[valueIndex]
        guard value.hasPrefix("--") == false else {
            throw NetworkingProfileDraftCommandError.missingValue(option)
        }
        return value
    }

    private static func usage() -> String {
        """
        Usage: KnowYou --networking-profile-draft --project-root <path> --scenario <jobs|friends> --person-name <name> [--prompt <text>] [--pretty]
        """
    }
}

private final class NetworkingProfileDraftCommandResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: NetworkingProfileDraftCommandResult?

    func set(_ result: NetworkingProfileDraftCommandResult) {
        lock.lock()
        value = result
        lock.unlock()
    }

    func get() -> NetworkingProfileDraftCommandResult? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

private struct NetworkingProfileDraftCommandConfiguration {
    let projectRoot: URL
    let scenario: NetworkingProfileScenario
    let prompt: String
    let personName: String
    let prettyPrint: Bool
    let showsHelp: Bool
}

private enum NetworkingProfileDraftCommandError: LocalizedError, Equatable {
    case missingRequiredOption(String)
    case missingValue(String)
    case unknownOption(String)
    case unsupportedScenario(String)

    var errorDescription: String? {
        switch self {
        case let .missingRequiredOption(option):
            return "Missing required option: \(option)"
        case let .missingValue(option):
            return "Missing value for \(option)"
        case let .unknownOption(option):
            return "Unknown option: \(option)"
        case let .unsupportedScenario(value):
            return "Unsupported scenario: \(value)"
        }
    }
}
