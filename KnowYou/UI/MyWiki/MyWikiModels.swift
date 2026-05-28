import CoreGraphics
import Foundation

struct MyWikiDashboardSnapshot: Equatable {
    var entriesByCategoryID: [String: [MyWikiEntry]]

    var categories: [MyWikiCategory] {
        MyWikiCategory.nativeCategories
    }

    var sources: [MyWikiEntry] {
        entries(for: .source)
    }

    var entities: [MyWikiEntry] {
        entries(for: .entity)
    }

    var concepts: [MyWikiEntry] {
        entries(for: .concept)
    }

    var allEntries: [MyWikiEntry] {
        categories.flatMap { entries(for: $0.id) }
    }

    var primaryEntries: [MyWikiEntry] {
        entities + concepts
    }

    init(entriesByCategoryID: [String: [MyWikiEntry]]) {
        self.entriesByCategoryID = entriesByCategoryID
    }

    init(
        sources: [MyWikiEntry] = [],
        entities: [MyWikiEntry] = [],
        concepts: [MyWikiEntry] = []
    ) {
        entriesByCategoryID = [
            MyWikiCategory.source.id: Self.recategorized(sources, as: .source),
            MyWikiCategory.entity.id: Self.recategorized(entities, as: .entity),
            MyWikiCategory.concept.id: Self.recategorized(concepts, as: .concept)
        ]
    }

    static let empty = MyWikiDashboardSnapshot(
        sources: [],
        entities: [],
        concepts: []
    )

    private static func recategorized(_ entries: [MyWikiEntry], as category: MyWikiCategory) -> [MyWikiEntry] {
        entries.map { entry in
            MyWikiEntry(
                id: entry.id,
                title: entry.title,
                category: category,
                summary: entry.summary,
                sourceNames: entry.sourceNames,
                aliases: entry.aliases,
                related: entry.related,
                tags: entry.tags,
                confidence: entry.confidence,
                mentions: entry.mentions,
                markdownBody: entry.markdownBody,
                fileURL: entry.fileURL
            )
        }
    }

    func entries(for category: MyWikiCategory) -> [MyWikiEntry] {
        entries(for: category.id)
    }

    func entries(for categoryID: String) -> [MyWikiEntry] {
        entriesByCategoryID[categoryID] ?? []
    }
}

struct MyWikiEntry: Identifiable, Equatable {
    let id: String
    let title: String
    let category: MyWikiCategory
    let summary: String
    let sourceNames: [String]
    var aliases: [String] = []
    var related: [String] = []
    var tags: [String] = []
    var confidence: String = ""
    var mentions: [MyWikiMention] = []
    var markdownBody: String = ""
    var fileURL: URL = URL(fileURLWithPath: "/")
}

struct MyWikiMention: Equatable {
    let day: String
    let text: String
}

struct MyWikiDetailPresentation: Equatable {
    let markdownText: String
    let isMarkdownTruncated: Bool
    let showsMarkdownPage: Bool

    init(entry: MyWikiEntry, markdownPreviewLimit: Int = 100_000, showsMarkdownPage: Bool = true) {
        self.showsMarkdownPage = showsMarkdownPage
        let source = entry.markdownBody.isEmpty ? entry.summary : entry.markdownBody
        let limit = max(0, markdownPreviewLimit)
        if source.count > limit {
            let endIndex = source.index(source.startIndex, offsetBy: limit)
            markdownText = String(source[..<endIndex])
            isMarkdownTruncated = true
        } else {
            markdownText = source
            isMarkdownTruncated = false
        }
    }
}

enum MyWikiWikilinkText {
    private static let scheme = "knowyou-mywiki"
    private static let host = "open"

    static func attributedString(from markdown: String) -> AttributedString {
        var result = AttributedString()
        var cursor = markdown.startIndex

        while let opener = markdown[cursor...].range(of: "[[") {
            appendMarkdown(String(markdown[cursor..<opener.lowerBound]), to: &result)

            guard let closer = markdown[opener.upperBound...].range(of: "]]") else {
                appendMarkdown(String(markdown[opener.lowerBound...]), to: &result)
                return result
            }

            let rawTarget = String(markdown[opener.upperBound..<closer.lowerBound])
            let parsed = parse(rawTarget)
            if let reference = parsed.reference {
                var linked = AttributedString(parsed.label)
                linked.link = url(for: reference)
                result += linked
            } else {
                appendMarkdown("[[\(rawTarget)]]", to: &result)
            }

            cursor = closer.upperBound
        }

        appendMarkdown(String(markdown[cursor...]), to: &result)
        return result
    }

    static func reference(from url: URL) -> String? {
        guard url.scheme == scheme, url.host == host else { return nil }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        return components?.queryItems?.first { $0.name == "reference" }?.value
    }

    static func containsWikilink(_ text: String) -> Bool {
        text.contains("[[") && text.contains("]]")
    }

    private static func url(for reference: String) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.queryItems = [URLQueryItem(name: "reference", value: reference)]
        return components.url ?? URL(string: "\(scheme)://\(host)")!
    }

    private static func parse(_ rawTarget: String) -> (reference: String?, label: String) {
        let parts = rawTarget.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        let reference = parts.first.map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let label = (parts.count > 1 ? String(parts[1]) : reference)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard reference.isEmpty == false else {
            return (nil, rawTarget)
        }
        return (reference, label.isEmpty ? reference : label)
    }

    private static func appendMarkdown(_ markdown: String, to attributed: inout AttributedString) {
        guard markdown.isEmpty == false else { return }
        let parsed = try? AttributedString(
            markdown: markdown,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )
        attributed += parsed ?? AttributedString(markdown)
    }
}

enum MyWikiDetailLayoutPolicy {
    static let showsStandaloneSummaryCard = false
}

enum MyWikiIndexRowHitTargetPolicy {
    static let usesFullRowContentShape = true
    static let showsSummary = false
    static let showsCategoryBadge = false
    static let minHeight: CGFloat = 34
}

struct MyWikiTagFacet: Identifiable, Equatable {
    let tag: String
    let title: String
    let count: Int

    var id: String {
        Self.normalize(tag)
    }

    static func facets(for entries: [MyWikiEntry]) -> [MyWikiTagFacet] {
        var counts: [String: Int] = [:]
        var displayTags: [String: String] = [:]

        for entry in entries {
            for rawTag in entry.tags {
                let trimmed = rawTag.trimmingCharacters(in: .whitespacesAndNewlines)
                let normalized = normalize(trimmed)
                guard normalized.isEmpty == false else { continue }
                counts[normalized, default: 0] += 1
                displayTags[normalized] = displayTags[normalized] ?? trimmed
            }
        }

        return counts.map { normalized, count in
            MyWikiTagFacet(tag: displayTags[normalized] ?? normalized, title: displayTags[normalized] ?? normalized, count: count)
        }
        .sorted { lhs, rhs in
            if lhs.isOther != rhs.isOther {
                return rhs.isOther
            }
            if lhs.count != rhs.count {
                return lhs.count > rhs.count
            }
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
    }

    func matches(_ entry: MyWikiEntry) -> Bool {
        entry.tags.contains { Self.normalize($0) == id }
    }

    private static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var isOther: Bool {
        id == "other"
    }
}

enum MyWikiTagFacetDisplayPolicy {
    static let defaultVisibleLimit = 6

    static func visibleFacets(_ facets: [MyWikiTagFacet], isExpanded: Bool) -> [MyWikiTagFacet] {
        guard isExpanded == false else { return facets }
        return Array(facets.prefix(defaultVisibleLimit))
    }

    static func hiddenCount(for facets: [MyWikiTagFacet], isExpanded: Bool) -> Int {
        guard isExpanded == false else { return 0 }
        return max(0, facets.count - defaultVisibleLimit)
    }

    static func canExpand(_ facets: [MyWikiTagFacet], isExpanded: Bool) -> Bool {
        isExpanded == false && facets.count > defaultVisibleLimit
    }

    static func canCollapse(_ facets: [MyWikiTagFacet], isExpanded: Bool) -> Bool {
        isExpanded && facets.count > defaultVisibleLimit
    }

    static func toggleTitle(for facets: [MyWikiTagFacet], isExpanded: Bool) -> String {
        if isExpanded {
            return "Show less"
        }
        return "+\(hiddenCount(for: facets, isExpanded: isExpanded)) more"
    }
}

enum MyWikiIndexNavigationPolicy {
    static let usesInlineShowMore = true
    static let usesFullListNavigation = false
}

enum MyWikiProgressRefreshPolicy {
    static let intervalNanoseconds: UInt64 = 2_000_000_000

    static func shouldRefresh(isSyncing: Bool, progressState: MyWikiIngestProgress.State?) -> Bool {
        isSyncing || progressState == .running
    }
}

enum MyWikiSourceLibraryEntryPolicy {
    static let showsManageSourcesButton = true
    static let progressCardOpensSourceLibrary = false
    static let manageButtonTitle = "Set Digest Files"
    static let manageButtonSystemImage = "doc.text.magnifyingglass"
    static let manageButtonIconSize: CGFloat = 13
    static let manageButtonMinWidth: CGFloat = 152
    static let manageButtonMinHeight: CGFloat = 36
}

enum MyWikiDetailMaintenancePolicy {
    static func showsDuplicateSuggestionCard(
        duplicateSuggestionCount: Int,
        isCurrentEntryAffected: Bool
    ) -> Bool {
        duplicateSuggestionCount > 0 && isCurrentEntryAffected
    }
}

enum MyWikiDuplicateDiscoveryPolicy {
    static let scansOnDashboardLoad = true
}

enum MyWikiIndexPreviewPolicy {
    static let defaultVisibleLimit = 10
    static let expandedEntityConceptLimit = 10

    static func previewLimit(for categoryID: String, fallback: Int) -> Int {
        switch categoryID {
        case MyWikiCategory.entity.id, MyWikiCategory.concept.id:
            return expandedEntityConceptLimit
        default:
            return defaultVisibleLimit
        }
    }

    static func sortPriority(for categoryID: String) -> Int {
        switch categoryID {
        case MyWikiCategory.entity.id:
            return 0
        case MyWikiCategory.concept.id:
            return 1
        case MyWikiCategory.source.id:
            return 99
        default:
            return 10
        }
    }
}

struct MyWikiIndexSectionPresentation {
    let title: String
    let entries: [MyWikiEntry]
    let isExpanded: Bool
    let previewLimit: Int
    let isShowingAll: Bool

    init(
        title: String,
        entries: [MyWikiEntry],
        isExpanded: Bool,
        previewLimit: Int,
        isShowingAll: Bool = false
    ) {
        self.title = title
        self.entries = entries
        self.isExpanded = isExpanded
        self.previewLimit = previewLimit
        self.isShowingAll = isShowingAll
    }

    var visibleEntries: [MyWikiEntry] {
        guard isExpanded else { return [] }
        guard isShowingAll == false else { return entries }
        return Array(entries.prefix(max(0, previewLimit)))
    }

    var canViewAll: Bool {
        canShowMore
    }

    var hiddenCount: Int {
        max(0, entries.count - previewLimit)
    }

    var canShowMore: Bool {
        isExpanded && isShowingAll == false && hiddenCount > 0
    }

    var canShowLess: Bool {
        isExpanded && isShowingAll && hiddenCount > 0
    }

    var showMoreTitle: String {
        isShowingAll ? "Show less" : "Show more (\(hiddenCount))"
    }
}

struct MyWikiIndexCategorySection: Identifiable {
    let category: MyWikiCategory
    let presentation: MyWikiIndexSectionPresentation
    let tagFacets: [MyWikiTagFacet]

    var id: String {
        category.id
    }
}

struct MyWikiIndexSectionsBuilder {
    func categorySections(
        snapshot: MyWikiDashboardSnapshot,
        query: String,
        expandedCategoryIDs: Set<String>,
        showingAllCategoryIDs: Set<String> = [],
        selectedTagByCategoryID: [String: String] = [:],
        previewLimit: Int
    ) -> [MyWikiIndexCategorySection] {
        let orderedCategories = snapshot.categories.enumerated().sorted { lhs, rhs in
            let lhsPriority = MyWikiIndexPreviewPolicy.sortPriority(for: lhs.element.id)
            let rhsPriority = MyWikiIndexPreviewPolicy.sortPriority(for: rhs.element.id)
            if lhsPriority != rhsPriority {
                return lhsPriority < rhsPriority
            }
            return lhs.offset < rhs.offset
        }.map(\.element)

        return orderedCategories.compactMap { category in
            let queryFilteredEntries = filtered(snapshot.entries(for: category.id), query: query)
            let tagFacets = MyWikiTagFacet.facets(for: queryFilteredEntries)
            let entries = tagFiltered(
                queryFilteredEntries,
                selectedTag: selectedTagByCategoryID[category.id]
            )
            guard entries.isEmpty == false || query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            return MyWikiIndexCategorySection(
                category: category,
                presentation: MyWikiIndexSectionPresentation(
                    title: category.displayTitle,
                    entries: entries,
                    isExpanded: expandedCategoryIDs.contains(category.id),
                    previewLimit: MyWikiIndexPreviewPolicy.previewLimit(
                        for: category.id,
                        fallback: previewLimit
                    ),
                    isShowingAll: showingAllCategoryIDs.contains(category.id)
                ),
                tagFacets: tagFacets
            )
        }
    }

    private func tagFiltered(
        _ entries: [MyWikiEntry],
        selectedTag: String?
    ) -> [MyWikiEntry] {
        guard let selectedTag,
              selectedTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        else {
            return entries
        }
        let facet = MyWikiTagFacet(tag: selectedTag, title: selectedTag, count: 0)
        return entries.filter(facet.matches)
    }

    private func filtered(_ entries: [MyWikiEntry], query: String) -> [MyWikiEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return entries }

        return entries.filter { entry in
            ([entry.title, entry.summary] + entry.aliases + entry.related + entry.tags)
                .contains { $0.localizedCaseInsensitiveContains(trimmed) }
        }
    }
}

enum MyWikiPanelLifecycleAction: Equatable {
    case loadDashboard
    case syncDiaries
}

enum MyWikiUserFacingCopy {
    static let overviewSubtitle = "Search and review sources, entities, and concepts organized from your journals."
    static let duplicateSuggestionSubtitle = "Review possible duplicate entities or concepts."
    static let detailPlaceholder = "Sources, entities, and concepts will appear here after your journals are organized."
}

struct MyWikiPanelLifecyclePolicy {
    static var onAppearActions: [MyWikiPanelLifecycleAction] {
        [.loadDashboard]
    }
}

struct MyWikiCategory: Equatable, Hashable, Identifiable {
    let id: String
    let displayTitle: String
    let singularTitle: String
    let frontmatterType: String

    init(id: String, displayTitle: String, singularTitle: String, frontmatterType: String) {
        self.id = id
        self.displayTitle = displayTitle
        self.singularTitle = singularTitle
        self.frontmatterType = frontmatterType
    }

    static let source = MyWikiCategory(
        id: "sources",
        displayTitle: "Sources",
        singularTitle: "Source",
        frontmatterType: "source"
    )
    static let entity = MyWikiCategory(
        id: "entities",
        displayTitle: "Entities",
        singularTitle: "Entity",
        frontmatterType: "entity"
    )
    static let concept = MyWikiCategory(
        id: "concepts",
        displayTitle: "Concepts",
        singularTitle: "Concept",
        frontmatterType: "concept"
    )
    static let nativeCategories = [source, entity, concept]
}
