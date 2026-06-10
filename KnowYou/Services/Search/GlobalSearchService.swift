import Foundation

struct GlobalSearchIndexBuildRequest: Equatable, Sendable {
    let diaryNotes: [String: URL]
    let sourceDocuments: [ImportedKnowledgeDocument]
    let todoItems: [UnifiedTodoItem]
    let myWikiProjectRoot: URL?

    init(
        diaryNotes: [String: URL],
        sourceDocuments: [ImportedKnowledgeDocument],
        todoItems: [UnifiedTodoItem],
        myWikiProjectRoot: URL? = nil
    ) {
        self.diaryNotes = diaryNotes
        self.sourceDocuments = sourceDocuments
        self.todoItems = todoItems
        self.myWikiProjectRoot = myWikiProjectRoot
    }
}

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
    enum Kind: String, Codable, Equatable, Sendable {
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

struct GlobalSearchIndexDocument: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let kind: GlobalSearchResult.Kind
    let groupTitle: String
    let searchableText: String
    let normalizedSearchableText: String
    let normalizedTitle: String
    let snippetText: String
    let baseScore: Int
    let todoID: String?
    let dayKey: String?
    let connectorInstanceID: String?
    let documentID: String?
    let myWikiCategoryID: String?
    let myWikiEntryID: String?

    init(
        id: String,
        title: String,
        kind: GlobalSearchResult.Kind,
        groupTitle: String,
        searchableText: String,
        snippetText: String,
        baseScore: Int,
        todoID: String? = nil,
        dayKey: String? = nil,
        connectorInstanceID: String? = nil,
        documentID: String? = nil,
        myWikiCategoryID: String? = nil,
        myWikiEntryID: String? = nil
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.groupTitle = groupTitle
        self.searchableText = searchableText
        normalizedSearchableText = searchableText.lowercased()
        normalizedTitle = title.lowercased()
        self.snippetText = snippetText
        self.baseScore = baseScore
        self.todoID = todoID
        self.dayKey = dayKey
        self.connectorInstanceID = connectorInstanceID
        self.documentID = documentID
        self.myWikiCategoryID = myWikiCategoryID
        self.myWikiEntryID = myWikiEntryID
    }
}

struct GlobalSearchIndexManifest: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let createdAt: Date
    let sourceSignature: String
    let documentCount: Int
}

struct GlobalSearchIndex: Codable, Equatable, Sendable {
    let manifest: GlobalSearchIndexManifest
    let documents: [GlobalSearchIndexDocument]
}

struct GlobalSearchIndexStore: Sendable {
    let indexURL: URL

    func loadValidIndex(expectedSignature: String) throws -> GlobalSearchIndex? {
        guard FileManager.default.fileExists(atPath: indexURL.path) else {
            return nil
        }

        let index: GlobalSearchIndex
        do {
            let data = try Data(contentsOf: indexURL)
            index = try Self.decoder.decode(GlobalSearchIndex.self, from: data)
        } catch {
            return nil
        }

        guard index.manifest.schemaVersion == GlobalSearchIndexManifest.currentSchemaVersion,
              index.manifest.sourceSignature == expectedSignature,
              index.manifest.documentCount == index.documents.count
        else {
            return nil
        }
        return index
    }

    func save(_ index: GlobalSearchIndex) throws {
        try FileManager.default.createDirectory(
            at: indexURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try Self.encoder.encode(index)
        try data.write(to: indexURL, options: .atomic)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

struct GlobalSearchIndexBuilder: @unchecked Sendable {
    var fileManager: FileManager = .default

    func sourceSignature(for request: GlobalSearchIndexBuildRequest) throws -> String {
        let descriptors = try signatureDescriptors(for: request)
        return SHA256Hasher.hash(descriptors.joined(separator: "\n"))
    }

    func buildIndex(
        for request: GlobalSearchIndexBuildRequest,
        sourceSignature: String? = nil
    ) throws -> GlobalSearchIndex {
        let signature = try sourceSignature ?? self.sourceSignature(for: request)
        let documents = try documents(for: request)
        return GlobalSearchIndex(
            manifest: GlobalSearchIndexManifest(
                schemaVersion: GlobalSearchIndexManifest.currentSchemaVersion,
                createdAt: Date(),
                sourceSignature: signature,
                documentCount: documents.count
            ),
            documents: documents
        )
    }

    func buildIndex(from request: GlobalSearchRequest) -> GlobalSearchIndex {
        let documents =
            todoDocuments(from: request.todoItems)
            + diaryDocuments(from: request.diaryNotes)
            + myWikiDocuments(from: request.myWikiEntries)
            + sourceDocuments(from: request.sourceDocuments)
        let signature = SHA256Hasher.hash("transient|\(request.query)|\(documents.map(\.id).joined(separator: "|"))")
        return GlobalSearchIndex(
            manifest: GlobalSearchIndexManifest(
                schemaVersion: GlobalSearchIndexManifest.currentSchemaVersion,
                createdAt: Date(),
                sourceSignature: signature,
                documentCount: documents.count
            ),
            documents: documents
        )
    }

    private func documents(for request: GlobalSearchIndexBuildRequest) throws -> [GlobalSearchIndexDocument] {
        let myWikiEntries: [MyWikiEntry]
        if let projectRoot = request.myWikiProjectRoot {
            myWikiEntries = (try? MyWikiMarkdownStore(fileManager: fileManager)
                .loadDashboard(projectRoot: projectRoot)
                .primaryEntries) ?? []
        } else {
            myWikiEntries = []
        }

        return todoDocuments(from: request.todoItems)
            + diaryDocuments(from: request.diaryNotes)
            + myWikiDocuments(from: myWikiEntries)
            + sourceDocuments(from: request.sourceDocuments)
    }

    private func todoDocuments(from items: [UnifiedTodoItem]) -> [GlobalSearchIndexDocument] {
        items.map { item in
            let searchable = [
                item.title,
                item.normalizedTitle,
                item.sourceDayKey,
                item.status.rawValue,
            ].joined(separator: "\n")
            return GlobalSearchIndexDocument(
                id: "todo:\(item.id)",
                title: item.title,
                kind: .todo,
                groupTitle: "Todo",
                searchableText: searchable,
                snippetText: item.title,
                baseScore: 3_000,
                todoID: item.id,
                dayKey: item.sourceDayKey
            )
        }
    }

    private func diaryDocuments(from notes: [String: URL]) -> [GlobalSearchIndexDocument] {
        notes
            .filter { GlobalSearchService.isDiaryDayKey($0.key) }
            .compactMap { dayKey, url in
                guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return nil }
                return GlobalSearchIndexDocument(
                    id: "diary:\(dayKey)",
                    title: dayKey,
                    kind: .diary,
                    groupTitle: "Diary",
                    searchableText: contents,
                    snippetText: contents,
                    baseScore: 2_000,
                    dayKey: dayKey
                )
            }
    }

    private func myWikiDocuments(from entries: [MyWikiEntry]) -> [GlobalSearchIndexDocument] {
        entries.map { entry in
            let searchable = ([
                entry.title,
                entry.summary,
                entry.confidence,
                entry.markdownBody,
            ] + entry.aliases + entry.related + entry.tags + entry.sourceNames + entry.mentions.map(\.text))
                .joined(separator: "\n")
            return GlobalSearchIndexDocument(
                id: "my-wiki:\(entry.category.id):\(entry.id)",
                title: entry.title,
                kind: .myWiki,
                groupTitle: "My Wiki",
                searchableText: searchable,
                snippetText: entry.markdownBody.isEmpty ? entry.summary : entry.markdownBody,
                baseScore: 1_500,
                myWikiCategoryID: entry.category.id,
                myWikiEntryID: entry.id
            )
        }
    }

    private func sourceDocuments(from documents: [ImportedKnowledgeDocument]) -> [GlobalSearchIndexDocument] {
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
            return GlobalSearchIndexDocument(
                id: "source:\(document.connectorInstanceID):\(document.id)",
                title: document.title,
                kind: .source,
                groupTitle: "Sources",
                searchableText: searchable,
                snippetText: contents,
                baseScore: 1_000,
                connectorInstanceID: document.connectorInstanceID,
                documentID: document.id
            )
        }
    }

    private func signatureDescriptors(for request: GlobalSearchIndexBuildRequest) throws -> [String] {
        var descriptors: [String] = []

        for (dayKey, url) in request.diaryNotes.sorted(by: { $0.key < $1.key }) where GlobalSearchService.isDiaryDayKey(dayKey) {
            descriptors.append("diary|\(dayKey)|\(fileSignature(url))")
        }

        for document in request.sourceDocuments.sorted(by: { $0.id < $1.id }) {
            descriptors.append([
                "source",
                document.id,
                document.connectorInstanceID,
                document.remoteID,
                document.contentHash,
                document.localContentPath,
                document.deletedAt?.timeIntervalSince1970.description ?? "active",
            ].joined(separator: "|"))
        }

        for item in request.todoItems.sorted(by: { $0.id < $1.id }) {
            descriptors.append([
                "todo",
                item.id,
                item.title,
                item.normalizedTitle,
                item.status.rawValue,
                item.sourceDayKey,
                item.completedAt?.timeIntervalSince1970.description ?? "",
                item.completionKind?.rawValue ?? "",
            ].joined(separator: "|"))
        }

        if let projectRoot = request.myWikiProjectRoot {
            let files = myWikiMarkdownFiles(projectRoot: projectRoot)
            for file in files {
                descriptors.append("mywiki|\(file.path)|\(fileSignature(file))")
            }
        } else {
            descriptors.append("mywiki|none")
        }

        return descriptors
    }

    private func myWikiMarkdownFiles(projectRoot: URL) -> [URL] {
        let filesByCategory: [[URL]] = MyWikiCategory.nativeCategories.map { category in
            let directory = projectRoot.appending(path: "wiki/\(category.id)", directoryHint: .isDirectory)
            guard let files = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else {
                return []
            }
            return files.filter { $0.pathExtension.lowercased() == "md" }
        }
        return filesByCategory.flatMap { $0 }
        .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    private func fileSignature(_ url: URL) -> String {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) else {
            return "\(url.path)|missing"
        }
        let size = values.fileSize ?? -1
        let modifiedAt = values.contentModificationDate?.timeIntervalSince1970 ?? -1
        return "\(url.path)|\(size)|\(modifiedAt)"
    }
}

struct GlobalSearchService {
    var fileManager: FileManager = .default

    func search(_ request: GlobalSearchRequest) -> GlobalSearchResponse {
        let index = GlobalSearchIndexBuilder(fileManager: fileManager).buildIndex(from: request)
        return search(query: request.query, index: index, maxResults: request.maxResults)
    }

    func search(
        query rawQuery: String,
        index: GlobalSearchIndex,
        maxResults: Int = 40
    ) -> GlobalSearchResponse {
        let request = GlobalSearchIndexedRequest(query: rawQuery, index: index, maxResults: maxResults)
        let query = request.query.trimmingCharacters(in: .whitespacesAndNewlines)
        let queryPlan = GlobalSearchQueryPlan(query: query)
        guard query.isEmpty == false,
              request.maxResults > 0,
              queryPlan.isEmpty == false
        else {
            return GlobalSearchResponse(query: request.query, results: [], groups: [])
        }

        let results = request.index.documents.compactMap { document in
            result(from: document, queryPlan: queryPlan)
        }
        .sorted(by: Self.sort)
        .prefix(request.maxResults)

        let resultList = Array(results)
        return GlobalSearchResponse(
            query: request.query,
            results: resultList,
            groups: Self.group(resultList)
        )
    }

    private func result(
        from document: GlobalSearchIndexDocument,
        queryPlan: GlobalSearchQueryPlan
    ) -> GlobalSearchResult? {
        let match = Self.match(
            normalizedBody: document.normalizedSearchableText,
            title: document.title,
            normalizedTitle: document.normalizedTitle,
            queryPlan: queryPlan
        )
        guard match.score > 0 else { return nil }

        return GlobalSearchResult(
            id: document.id,
            title: document.title,
            kind: document.kind,
            groupTitle: document.groupTitle,
            snippet: Self.excerpt(from: document.snippetText, queryPlan: queryPlan),
            score: match.score + document.baseScore,
            matchedTerms: match.matchedTerms,
            matchCount: match.matchCount,
            todoID: document.todoID,
            dayKey: document.dayKey,
            connectorInstanceID: document.connectorInstanceID,
            documentID: document.documentID,
            myWikiCategoryID: document.myWikiCategoryID,
            myWikiEntryID: document.myWikiEntryID
        )
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

    private static func match(
        normalizedBody bodyLower: String,
        title: String,
        normalizedTitle titleLower: String,
        queryPlan: GlobalSearchQueryPlan
    ) -> (score: Int, matchedTerms: [String], matchCount: Int) {
        var score = 0
        var matchedTerms: [String] = []
        var matchCount = 0

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

    static func isDiaryDayKey(_ value: String) -> Bool {
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

private struct GlobalSearchIndexedRequest: Equatable {
    let query: String
    let index: GlobalSearchIndex
    let maxResults: Int
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
