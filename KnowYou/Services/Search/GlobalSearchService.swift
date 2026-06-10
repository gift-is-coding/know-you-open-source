import Foundation

struct GlobalSearchRequest: Equatable {
    let query: String
    let diaryNotes: [String: URL]
    let sourceDocuments: [ImportedKnowledgeDocument]
    let todoItems: [UnifiedTodoItem]
    let myWikiEntries: [MyWikiEntry]
    let maxResults: Int

    init(
        query: String,
        diaryNotes: [String: URL],
        sourceDocuments: [ImportedKnowledgeDocument],
        todoItems: [UnifiedTodoItem],
        myWikiEntries: [MyWikiEntry] = [],
        maxResults: Int = 40
    ) {
        self.query = query
        self.diaryNotes = diaryNotes
        self.sourceDocuments = sourceDocuments
        self.todoItems = todoItems
        self.myWikiEntries = myWikiEntries
        self.maxResults = maxResults
    }
}

struct GlobalSearchResponse: Equatable {
    let query: String
    let results: [GlobalSearchResult]
    let groups: [GlobalSearchGroup]

    var totalResultCount: Int {
        results.count
    }
}

struct GlobalSearchGroup: Identifiable, Equatable {
    let id: String
    let title: String
    let results: [GlobalSearchResult]
}

struct GlobalSearchResult: Identifiable, Equatable {
    enum Kind: String, Equatable {
        case todo
        case diary
        case myWiki
        case source
    }

    let id: String
    let title: String
    let kind: Kind
    let groupTitle: String
    let snippet: String
    let score: Int
    let matchedTerms: [String]
    let matchCount: Int
    let todoID: String?
    let dayKey: String?
    let connectorInstanceID: String?
    let documentID: String?
    let myWikiCategoryID: String?
    let myWikiEntryID: String?
}

struct GlobalSearchService {
    var fileManager: FileManager = .default

    func search(_ request: GlobalSearchRequest) -> GlobalSearchResponse {
        let query = request.query.trimmingCharacters(in: .whitespacesAndNewlines)
        let queryPlan = GlobalSearchQueryPlan(query: query)
        guard query.isEmpty == false,
              request.maxResults > 0,
              queryPlan.isEmpty == false
        else {
            return GlobalSearchResponse(query: request.query, results: [], groups: [])
        }

        let results = (
            todoResults(from: request.todoItems, queryPlan: queryPlan)
                + diaryResults(from: request.diaryNotes, queryPlan: queryPlan)
                + myWikiResults(from: request.myWikiEntries, queryPlan: queryPlan)
                + sourceResults(from: request.sourceDocuments, queryPlan: queryPlan)
        )
        .sorted(by: Self.sort)
        .prefix(request.maxResults)

        let resultList = Array(results)
        return GlobalSearchResponse(
            query: request.query,
            results: resultList,
            groups: Self.group(resultList)
        )
    }

    private func todoResults(
        from items: [UnifiedTodoItem],
        queryPlan: GlobalSearchQueryPlan
    ) -> [GlobalSearchResult] {
        items.compactMap { item in
            let searchable = [
                item.title,
                item.normalizedTitle,
                item.sourceDayKey,
                item.status.rawValue,
            ].joined(separator: "\n")
            let match = Self.match(searchable, title: item.title, queryPlan: queryPlan)
            guard match.score > 0 else { return nil }

            return GlobalSearchResult(
                id: "todo:\(item.id)",
                title: item.title,
                kind: .todo,
                groupTitle: "Todo",
                snippet: Self.excerpt(from: item.title, queryPlan: queryPlan),
                score: match.score + 3_000,
                matchedTerms: match.matchedTerms,
                matchCount: match.matchCount,
                todoID: item.id,
                dayKey: item.sourceDayKey,
                connectorInstanceID: nil,
                documentID: nil,
                myWikiCategoryID: nil,
                myWikiEntryID: nil
            )
        }
    }

    private func diaryResults(
        from notes: [String: URL],
        queryPlan: GlobalSearchQueryPlan
    ) -> [GlobalSearchResult] {
        notes
            .filter { Self.isDiaryDayKey($0.key) }
            .compactMap { dayKey, url in
                guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return nil }
                let match = Self.match(contents, title: dayKey, queryPlan: queryPlan)
                guard match.score > 0 else { return nil }

                return GlobalSearchResult(
                    id: "diary:\(dayKey)",
                    title: dayKey,
                    kind: .diary,
                    groupTitle: "Diary",
                    snippet: Self.excerpt(from: contents, queryPlan: queryPlan),
                    score: match.score + 2_000,
                    matchedTerms: match.matchedTerms,
                    matchCount: match.matchCount,
                    todoID: nil,
                    dayKey: dayKey,
                    connectorInstanceID: nil,
                    documentID: nil,
                    myWikiCategoryID: nil,
                    myWikiEntryID: nil
                )
            }
    }

    private func myWikiResults(
        from entries: [MyWikiEntry],
        queryPlan: GlobalSearchQueryPlan
    ) -> [GlobalSearchResult] {
        entries.compactMap { entry in
            let searchable = ([
                entry.title,
                entry.summary,
                entry.confidence,
                entry.markdownBody,
            ] + entry.aliases + entry.related + entry.tags + entry.sourceNames + entry.mentions.map(\.text))
                .joined(separator: "\n")
            let match = Self.match(searchable, title: entry.title, queryPlan: queryPlan)
            guard match.score > 0 else { return nil }

            return GlobalSearchResult(
                id: "my-wiki:\(entry.category.id):\(entry.id)",
                title: entry.title,
                kind: .myWiki,
                groupTitle: "My Wiki",
                snippet: Self.excerpt(
                    from: entry.markdownBody.isEmpty ? entry.summary : entry.markdownBody,
                    queryPlan: queryPlan
                ),
                score: match.score + 1_500,
                matchedTerms: match.matchedTerms,
                matchCount: match.matchCount,
                todoID: nil,
                dayKey: nil,
                connectorInstanceID: nil,
                documentID: nil,
                myWikiCategoryID: entry.category.id,
                myWikiEntryID: entry.id
            )
        }
    }

    private func sourceResults(
        from documents: [ImportedKnowledgeDocument],
        queryPlan: GlobalSearchQueryPlan
    ) -> [GlobalSearchResult] {
        documents.compactMap { document in
            guard document.deletedAt == nil,
                  fileManager.fileExists(atPath: document.localContentPath),
                  let contents = try? String(
                    contentsOf: URL(fileURLWithPath: document.localContentPath),
                    encoding: .utf8
                  )
            else {
                return nil
            }

            let searchable = [
                document.title,
                document.sourcePath ?? "",
                document.remoteID,
                contents,
            ].joined(separator: "\n")
            let match = Self.match(searchable, title: document.title, queryPlan: queryPlan)
            guard match.score > 0 else { return nil }

            return GlobalSearchResult(
                id: "source:\(document.connectorInstanceID):\(document.id)",
                title: document.title,
                kind: .source,
                groupTitle: "Sources",
                snippet: Self.excerpt(from: contents, queryPlan: queryPlan),
                score: match.score + 1_000,
                matchedTerms: match.matchedTerms,
                matchCount: match.matchCount,
                todoID: nil,
                dayKey: nil,
                connectorInstanceID: document.connectorInstanceID,
                documentID: document.id,
                myWikiCategoryID: nil,
                myWikiEntryID: nil
            )
        }
    }

    private static func match(
        _ body: String,
        title: String,
        queryPlan: GlobalSearchQueryPlan
    ) -> (score: Int, matchedTerms: [String], matchCount: Int) {
        var score = 0
        var matchedTerms: [String] = []
        var matchCount = 0
        let titleLower = title.lowercased()
        let bodyLower = body.lowercased()

        for phrase in queryPlan.phrases {
            var phraseScore = 0
            if contains(phrase, in: titleLower) {
                phraseScore += 180
            }
            let bodyCount = occurrenceCount(of: phrase, in: bodyLower)
            phraseScore += min(bodyCount, 8) * 36
            if phraseScore > 0 {
                score += phraseScore
                matchedTerms.append(phrase)
                matchCount += max(bodyCount, 1)
            }
        }

        for term in queryPlan.terms {
            var termScore = 0
            if contains(term, in: titleLower) {
                termScore += 90
            }
            let bodyCount = occurrenceCount(of: term, in: bodyLower)
            termScore += min(bodyCount, 8) * 18
            if termScore > 0 {
                score += termScore
                matchedTerms.append(term)
                matchCount += max(bodyCount, 1)
            }
        }

        return (score, uniquePreservingOrder(matchedTerms), max(matchCount, score > 0 ? 1 : 0))
    }

    private static func sort(_ lhs: GlobalSearchResult, _ rhs: GlobalSearchResult) -> Bool {
        if lhs.score != rhs.score {
            return lhs.score > rhs.score
        }
        if lhs.kind != rhs.kind {
            return kindRank(lhs.kind) < kindRank(rhs.kind)
        }
        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }

    private static func group(_ results: [GlobalSearchResult]) -> [GlobalSearchGroup] {
        let order: [(GlobalSearchResult.Kind, String)] = [
            (.todo, "Todo"),
            (.diary, "Diary"),
            (.myWiki, "My Wiki"),
            (.source, "Sources"),
        ]

        return order.compactMap { kind, title in
            let groupResults = results.filter { $0.kind == kind }
            guard groupResults.isEmpty == false else { return nil }
            return GlobalSearchGroup(id: kind.rawValue, title: title, results: groupResults)
        }
    }

    private static func excerpt(from text: String, queryPlan: GlobalSearchQueryPlan) -> String {
        let clean = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.isEmpty == false else { return "" }

        let lower = clean.lowercased()
        let allTerms = queryPlan.phrases + queryPlan.terms
        let firstMatch = allTerms
            .compactMap { term -> String.Index? in
                lower.range(of: term, options: [.caseInsensitive, .diacriticInsensitive])?.lowerBound
            }
            .min()

        guard let index = firstMatch else {
            return String(clean.prefix(180))
        }

        let start = clean.index(index, offsetBy: -60, limitedBy: clean.startIndex) ?? clean.startIndex
        let end = clean.index(index, offsetBy: 140, limitedBy: clean.endIndex) ?? clean.endIndex
        let prefix = start == clean.startIndex ? "" : "..."
        let suffix = end == clean.endIndex ? "" : "..."
        return "\(prefix)\(clean[start..<end])\(suffix)"
    }

    private static func isDiaryDayKey(_ value: String) -> Bool {
        value.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil
    }

    private static func contains(_ term: String, in text: String) -> Bool {
        text.range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    private static func occurrenceCount(of term: String, in text: String) -> Int {
        guard term.isEmpty == false else { return 0 }
        var count = 0
        var searchRange = text.startIndex..<text.endIndex
        while let range = text.range(
            of: term,
            options: [.caseInsensitive, .diacriticInsensitive],
            range: searchRange
        ) {
            count += 1
            searchRange = range.upperBound..<text.endIndex
        }
        return count
    }

    fileprivate static func uniquePreservingOrder(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for value in values where seen.insert(value).inserted {
            result.append(value)
        }
        return result
    }

    private static func kindRank(_ kind: GlobalSearchResult.Kind) -> Int {
        switch kind {
        case .todo:
            return 0
        case .diary:
            return 1
        case .myWiki:
            return 2
        case .source:
            return 3
        }
    }
}

private struct GlobalSearchQueryPlan: Equatable {
    let phrases: [String]
    let terms: [String]

    var isEmpty: Bool {
        phrases.isEmpty && terms.isEmpty
    }

    init(query: String) {
        let normalized = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard normalized.isEmpty == false else {
            phrases = []
            terms = []
            return
        }

        phrases = [normalized]
        let splitTerms = normalized
            .components(separatedBy: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 2 && $0 != normalized }
        terms = GlobalSearchService.uniquePreservingOrder(splitTerms)
    }
}
