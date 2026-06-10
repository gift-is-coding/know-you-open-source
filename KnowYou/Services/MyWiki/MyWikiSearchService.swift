import Foundation

struct MyWikiSearchRequest: Equatable {
    let projectRoot: URL
    let query: String
    let maxResults: Int

    init(projectRoot: URL, query: String, maxResults: Int = 40) {
        self.projectRoot = projectRoot
        self.query = query
        self.maxResults = maxResults
    }
}

struct MyWikiSearchResponse: Equatable {
    let query: String
    let results: [MyWikiSearchResult]
    let groups: [MyWikiSearchGroup]

    var totalResultCount: Int {
        results.count
    }
}

struct MyWikiSearchGroup: Identifiable, Equatable {
    let id: String
    let title: String
    let results: [MyWikiSearchResult]
}

struct MyWikiSearchResult: Identifiable, Equatable {
    let id: String
    let title: String
    let relativePath: String
    let sourceKind: MyWikiSearchSourceKind
    let groupTitle: String
    let day: String?
    let snippet: String
    let score: Int
    let matchedTerms: [String]
    let matchCount: Int
}

enum MyWikiSearchSourceKind: String, Equatable {
    case wiki
    case rawSource
}

struct MyWikiSearchService {
    var fileManager: FileManager = .default

    func search(_ request: MyWikiSearchRequest) -> MyWikiSearchResponse {
        let query = request.query.trimmingCharacters(in: .whitespacesAndNewlines)
        let queryPlan = Self.queryPlan(for: query)
        guard query.isEmpty == false,
              request.maxResults > 0,
              queryPlan.isEmpty == false,
              fileManager.fileExists(atPath: request.projectRoot.path)
        else {
            return MyWikiSearchResponse(query: request.query, results: [], groups: [])
        }

        let results = markdownFiles(in: request.projectRoot)
            .compactMap { page(from: $0, projectRoot: request.projectRoot) }
            .compactMap { result(for: $0, queryPlan: queryPlan) }
            .sorted(by: Self.sort)
            .prefix(request.maxResults)

        let resultList = Array(results)
        return MyWikiSearchResponse(
            query: request.query,
            results: resultList,
            groups: Self.group(resultList)
        )
    }

    private func markdownFiles(in projectRoot: URL) -> [URL] {
        let roots = [
            projectRoot.appending(path: "wiki", directoryHint: .isDirectory),
            projectRoot.appending(path: "raw/sources", directoryHint: .isDirectory),
        ]

        return roots.flatMap { root -> [URL] in
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else {
                return []
            }

            return enumerator.compactMap { element in
                guard let url = element as? URL,
                      ["md", "txt"].contains(url.pathExtension.lowercased())
                else {
                    return nil
                }
                return url
            }
        }
    }

    private func page(from url: URL, projectRoot: URL) -> MyWikiSearchPage? {
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let parsed = Self.parseMarkdown(contents, fileName: url.lastPathComponent)
        let relativePath = Self.relativePath(from: projectRoot, to: url)
        let sourceKind: MyWikiSearchSourceKind = relativePath.hasPrefix("wiki/") ? .wiki : .rawSource
        let day = parsed.frontmatter["day"] ?? Self.dayFromPath(relativePath)

        return MyWikiSearchPage(
            title: parsed.title,
            pageType: parsed.frontmatter["type"] ?? sourceKind.rawValue,
            body: parsed.body,
            relativePath: relativePath,
            sourceKind: sourceKind,
            day: day
        )
    }

    private func result(for page: MyWikiSearchPage, queryPlan: MyWikiSearchQueryPlan) -> MyWikiSearchResult? {
        let title = page.title.lowercased()
        let path = page.relativePath.lowercased()
        let type = page.pageType.lowercased()
        let body = page.body.lowercased()

        var score = 0
        var matchCount = 0
        var matchedTerms: [String] = []
        for phrase in queryPlan.phrases {
            let termScore = scoreTerm(
                phrase,
                title: title,
                path: path,
                type: type,
                body: body,
                titleWeight: 130,
                pathWeight: 70,
                typeWeight: 35,
                bodyWeight: 24
            )
            if termScore > 0 {
                score += termScore
                matchCount += Self.occurrenceCount(of: phrase, in: page.body)
                matchedTerms.append(phrase)
            }
        }
        for term in queryPlan.terms {
            let termScore = scoreTerm(
                term,
                title: title,
                path: path,
                type: type,
                body: body,
                titleWeight: 80,
                pathWeight: 40,
                typeWeight: 20,
                bodyWeight: 10
            )
            if termScore > 0 {
                score += termScore
                matchCount += Self.occurrenceCount(of: term, in: page.body)
                matchedTerms.append(term)
            }
        }

        guard score > 0 else { return nil }
        if page.sourceKind == .wiki { score += 50 }
        if page.relativePath == "wiki/index.md" || page.relativePath == "wiki/overview.md" {
            score -= 35
        }

        let snippet = Self.excerpt(from: page.body, queryPlan: queryPlan)
        guard snippet.isEmpty == false else { return nil }

        return MyWikiSearchResult(
            id: page.relativePath,
            title: page.title,
            relativePath: page.relativePath,
            sourceKind: page.sourceKind,
            groupTitle: Self.groupTitle(for: page),
            day: page.day,
            snippet: snippet,
            score: score,
            matchedTerms: Self.uniquePreservingOrder(matchedTerms),
            matchCount: max(matchCount, 1)
        )
    }

    private func scoreTerm(
        _ term: String,
        title: String,
        path: String,
        type: String,
        body: String,
        titleWeight: Int,
        pathWeight: Int,
        typeWeight: Int,
        bodyWeight: Int
    ) -> Int {
        var score = 0
        if Self.contains(term, in: title) { score += titleWeight }
        if Self.contains(term, in: path) { score += pathWeight }
        if Self.contains(term, in: type) { score += typeWeight }
        score += min(Self.occurrenceCount(of: term, in: body), 5) * bodyWeight
        return score
    }

    private static func sort(_ lhs: MyWikiSearchResult, _ rhs: MyWikiSearchResult) -> Bool {
        if lhs.score != rhs.score {
            return lhs.score > rhs.score
        }
        if lhs.day != rhs.day {
            return (lhs.day ?? "") > (rhs.day ?? "")
        }
        return lhs.relativePath < rhs.relativePath
    }

    private static func group(_ results: [MyWikiSearchResult]) -> [MyWikiSearchGroup] {
        var groups: [MyWikiSearchGroup] = []
        for result in results {
            if let index = groups.firstIndex(where: { $0.title == result.groupTitle }) {
                let group = groups[index]
                groups[index] = MyWikiSearchGroup(
                    id: group.id,
                    title: group.title,
                    results: group.results + [result]
                )
            } else {
                groups.append(
                    MyWikiSearchGroup(
                        id: result.groupTitle.lowercased(),
                        title: result.groupTitle,
                        results: [result]
                    )
                )
            }
        }
        return groups
    }

    private static func groupTitle(for page: MyWikiSearchPage) -> String {
        if let day = page.day {
            return day
        }
        if page.sourceKind == .wiki {
            return "My Wiki"
        }

        let prefix = "raw/sources/"
        if page.relativePath.hasPrefix(prefix) {
            let rest = String(page.relativePath.dropFirst(prefix.count))
            return rest.split(separator: "/").first.map(String.init) ?? "Sources"
        }
        return "Sources"
    }

    private static func parseMarkdown(
        _ markdown: String,
        fileName: String
    ) -> (frontmatter: [String: String], title: String, body: String) {
        var frontmatter: [String: String] = [:]
        var body = markdown

        if markdown.hasPrefix("---\n"),
           let endRange = markdown.range(
            of: "\n---",
            range: markdown.index(markdown.startIndex, offsetBy: 4)..<markdown.endIndex
           ) {
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

    private static func queryPlan(for query: String) -> MyWikiSearchQueryPlan {
        let runs = tokenRuns(in: query)
        var terms: [String] = []
        var latinTermsInOrder: [String] = []

        for run in runs {
            switch run.kind {
            case .latin:
                let term = run.text.lowercased()
                guard term.count > 1, englishStopWords.contains(term) == false else { continue }
                terms.append(term)
                latinTermsInOrder.append(term)
            case .cjk:
                terms.append(contentsOf: cjkTerms(from: run.text))
            }
        }

        var phrases = quotedPhrases(in: query)
        for index in latinTermsInOrder.indices {
            let nextIndex = latinTermsInOrder.index(after: index)
            guard nextIndex < latinTermsInOrder.endIndex else { continue }
            let first = latinTermsInOrder[index]
            let second = latinTermsInOrder[nextIndex]
            if first.count > 2 || second.count > 2 {
                phrases.append(first + " " + second)
            }
        }

        return MyWikiSearchQueryPlan(
            phrases: Array(uniquePreservingOrder(phrases).prefix(16)),
            terms: Array(uniquePreservingOrder(terms).prefix(60))
        )
    }

    private static var englishStopWords: Set<String> {
        [
            "about", "after", "again", "also", "and", "answer", "before", "between",
            "could", "does", "external", "find", "from", "generic", "give", "have",
            "into", "just", "local", "more", "need", "needs", "only", "paragraph",
            "prefer", "provide", "question", "return", "should", "than", "that",
            "the", "their", "there", "this", "through", "user", "using", "what",
            "when", "where", "whether", "wiki", "with", "work", "working", "use",
            "am", "an", "as", "at", "be", "by", "do", "for", "in", "is", "it",
            "of", "on", "or", "to",
        ]
    }

    private static func tokenRuns(in text: String) -> [MyWikiSearchTokenRun] {
        var runs: [MyWikiSearchTokenRun] = []
        var latin = ""
        var cjk = ""

        func flushLatin() {
            if latin.isEmpty == false {
                runs.append(MyWikiSearchTokenRun(kind: .latin, text: latin))
                latin = ""
            }
        }

        func flushCJK() {
            if cjk.isEmpty == false {
                runs.append(MyWikiSearchTokenRun(kind: .cjk, text: cjk))
                cjk = ""
            }
        }

        for character in text.lowercased() {
            if isCJK(character) {
                flushLatin()
                cjk.append(character)
            } else if character.isLetter || character.isNumber {
                flushCJK()
                latin.append(character)
            } else {
                flushLatin()
                flushCJK()
            }
        }
        flushLatin()
        flushCJK()

        return runs
    }

    private static func cjkTerms(from text: String) -> [String] {
        let characters = Array(text)
        guard characters.count > 1 else { return [] }

        var terms: [String] = []
        if characters.count <= 8 {
            terms.append(String(characters))
        }

        for size in [2, 3] {
            guard characters.count >= size else { continue }
            for index in 0...(characters.count - size) {
                terms.append(String(characters[index..<(index + size)]))
            }
        }

        return terms.filter { cjkStopTerms.contains($0) == false }
    }

    private static var cjkStopTerms: Set<String> {
        ["帮我", "用户", "没有", "给了", "这段", "背景", "应该", "怎么"]
    }

    private static func quotedPhrases(in text: String) -> [String] {
        var phrases: [String] = []
        for delimiter in ["\"", "'", "`"] {
            let parts = text.components(separatedBy: delimiter)
            guard parts.count > 2 else { continue }
            for index in stride(from: 1, to: parts.count, by: 2) {
                let phrase = parts[index].lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                if phrase.count > 2 {
                    phrases.append(phrase)
                }
            }
        }
        return phrases
    }

    private static func excerpt(from body: String, queryPlan: MyWikiSearchQueryPlan) -> String {
        let paragraphs = body
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false && $0.hasPrefix("---") == false }

        let terms = queryPlan.phrases + queryPlan.terms
        let selected = paragraphs
            .filter { $0.hasPrefix("#") == false }
            .max { lhs, rhs in
                paragraphScore(lhs, terms: terms) < paragraphScore(rhs, terms: terms)
            } ?? paragraphs.first { $0.hasPrefix("#") == false } ?? paragraphs.first ?? ""

        return trim(selected.replacingOccurrences(of: "\n", with: " "), maxCharacters: 420)
    }

    private static func paragraphScore(_ paragraph: String, terms: [String]) -> Int {
        let lower = paragraph.lowercased()
        return terms.reduce(0) { score, term in
            score + (contains(term, in: lower) ? 1 : 0)
        }
    }

    private static func trim(_ text: String, maxCharacters: Int) -> String {
        guard maxCharacters > 0 else { return "" }
        guard text.count > maxCharacters else { return text }
        guard maxCharacters > 3 else {
            let end = text.index(text.startIndex, offsetBy: maxCharacters)
            return String(text[..<end])
        }
        let end = text.index(text.startIndex, offsetBy: maxCharacters - 3)
        return String(text[..<end]).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }

    private static func occurrenceCount(of needle: String, in haystack: String) -> Int {
        guard needle.isEmpty == false else { return 0 }
        let normalizedNeedle = normalizeForMatch(needle)
        let normalizedHaystack = normalizeForMatch(haystack)
        var count = 0
        var searchRange = normalizedHaystack.startIndex..<normalizedHaystack.endIndex
        while let range = normalizedHaystack.range(of: normalizedNeedle, options: [], range: searchRange) {
            count += 1
            searchRange = range.upperBound..<normalizedHaystack.endIndex
        }
        return count
    }

    private static func contains(_ needle: String, in haystack: String) -> Bool {
        guard needle.isEmpty == false else { return false }
        return normalizeForMatch(haystack).contains(normalizeForMatch(needle))
    }

    private static func normalizeForMatch(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "/", with: " ")
            .replacingOccurrences(of: ".", with: " ")
    }

    private static func uniquePreservingOrder(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for value in values {
            guard value.isEmpty == false, seen.contains(value) == false else { continue }
            seen.insert(value)
            result.append(value)
        }
        return result
    }

    private static func isCJK(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { scalar in
            switch scalar.value {
            case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF:
                return true
            default:
                return false
            }
        }
    }

    private static func relativePath(from root: URL, to url: URL) -> String {
        let rootPath = root.standardizedFileURL.resolvingSymlinksInPath().path
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        let rootPrefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        if path.hasPrefix(rootPrefix) {
            return String(path.dropFirst(rootPrefix.count)).replacingOccurrences(of: "\\", with: "/")
        }

        for marker in ["/wiki/", "/raw/sources/"] {
            if let range = path.range(of: marker) {
                return String(String(path[range.lowerBound...]).dropFirst())
                    .replacingOccurrences(of: "\\", with: "/")
            }
        }
        return url.lastPathComponent
    }

    private static func dayFromPath(_ path: String) -> String? {
        let pattern = #"\d{4}-\d{2}-\d{2}"#
        guard let range = path.range(of: pattern, options: .regularExpression) else { return nil }
        return String(path[range])
    }
}

private extension MyWikiSearchQueryPlan {
    var isEmpty: Bool {
        phrases.isEmpty && terms.isEmpty
    }
}

private struct MyWikiSearchQueryPlan {
    let phrases: [String]
    let terms: [String]
}

private enum MyWikiSearchTokenKind {
    case latin
    case cjk
}

private struct MyWikiSearchTokenRun {
    let kind: MyWikiSearchTokenKind
    let text: String
}

private struct MyWikiSearchPage {
    let title: String
    let pageType: String
    let body: String
    let relativePath: String
    let sourceKind: MyWikiSearchSourceKind
    let day: String?
}
