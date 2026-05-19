import CoreGraphics
import Foundation

struct MyWikiDashboardSnapshot: Equatable {
    var schema: MyWikiSchemaConfig
    var entriesByCategoryID: [String: [MyWikiEntry]]

    var categories: [MyWikiCategoryDefinition] {
        schema.categories
    }

    var summaries: [MyWikiEntry] {
        entries(for: .summary)
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

    var people: [MyWikiEntry] {
        entries(for: .person)
    }

    var projects: [MyWikiEntry] {
        entries(for: .project)
    }

    var events: [MyWikiEntry] {
        entries(for: .event)
    }

    var themes: [MyWikiEntry] {
        entries(for: .theme)
    }

    var preferences: [MyWikiEntry] {
        entries(for: .preference)
    }

    var openLoops: [MyWikiEntry] {
        entries(for: .openLoop)
    }

    var allEntries: [MyWikiEntry] {
        schema.categories.flatMap { entries(for: $0.id) }
    }

    var primaryEntries: [MyWikiEntry] {
        schema.categories
            .filter { ["summaries", "sources"].contains($0.id) == false }
            .flatMap { entries(for: $0.id) }
    }

    init(schema: MyWikiSchemaConfig, entriesByCategoryID: [String: [MyWikiEntry]]) {
        self.schema = schema
        self.entriesByCategoryID = entriesByCategoryID
    }

    init(
        summaries: [MyWikiEntry],
        people: [MyWikiEntry],
        projects: [MyWikiEntry],
        events: [MyWikiEntry] = [],
        themes: [MyWikiEntry],
        preferences: [MyWikiEntry],
        openLoops: [MyWikiEntry]
    ) {
        schema = Self.defaultSchema
        let entityEntries = Self.recategorized(people + projects + events, as: .entity)
        let conceptEntries = Self.recategorized(summaries + themes + preferences + openLoops, as: .concept)
        entriesByCategoryID = [
            MyWikiCategory.source.id: [],
            MyWikiCategory.entity.id: entityEntries,
            MyWikiCategory.concept.id: conceptEntries,
            MyWikiCategory.summary.id: summaries,
            MyWikiCategory.person.id: people,
            MyWikiCategory.project.id: projects,
            MyWikiCategory.event.id: events,
            MyWikiCategory.theme.id: themes,
            MyWikiCategory.preference.id: preferences,
            MyWikiCategory.openLoop.id: openLoops
        ]
    }

    static let empty = MyWikiDashboardSnapshot(
        summaries: [],
        people: [],
        projects: [],
        events: [],
        themes: [],
        preferences: [],
        openLoops: []
    )

    private static let defaultSchema = try! MyWikiSchemaConfig.defaultPersonalContext()

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

enum MyWikiDetailLayoutPolicy {
    static let showsStandaloneSummaryCard = false
}

enum MyWikiIndexRowHitTargetPolicy {
    static let usesFullRowContentShape = true
    static let showsSummary = false
    static let showsCategoryBadge = false
    static let minHeight: CGFloat = 34
}

struct MyWikiEntityFacet: Identifiable, Equatable {
    let id: String
    let title: String
    let matchingTags: Set<String>

    static let people = MyWikiEntityFacet(
        id: "people",
        title: "人物",
        matchingTags: [
            "person", "people", "human", "individual", "founder", "leader",
            "manager", "owner", "interviewer", "participant", "stakeholder"
        ]
    )
    static let projects = MyWikiEntityFacet(
        id: "projects",
        title: "项目",
        matchingTags: [
            "project", "program", "initiative", "platform", "product",
            "app", "workflow", "poc", "workstream"
        ]
    )
    static let organizations = MyWikiEntityFacet(
        id: "organizations",
        title: "组织",
        matchingTags: [
            "organization", "organisation", "org", "company", "team",
            "department", "institution", "enterprise", "vendor", "customer"
        ]
    )
    static let other = MyWikiEntityFacet(id: "other", title: "其他", matchingTags: [])
    static let defaults = [people, projects, organizations, other]

    static func facet(id: String?) -> MyWikiEntityFacet? {
        guard let id else { return nil }
        return defaults.first { $0.id == id }
    }

    static func facet(for entry: MyWikiEntry) -> MyWikiEntityFacet {
        defaults.first { $0 != other && $0.matches(entry) } ?? other
    }

    func matches(_ entry: MyWikiEntry) -> Bool {
        guard entry.category == .entity else { return false }
        let normalizedTags = Set(entry.tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        if self == Self.other {
            return Self.defaults
                .filter { $0 != Self.other }
                .contains { $0.matches(entry) } == false
        }
        return normalizedTags.isDisjoint(with: matchingTags) == false
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

enum MyWikiDetailMaintenancePolicy {
    static func showsDuplicateSuggestionCard(duplicateSuggestionCount: Int) -> Bool {
        duplicateSuggestionCount > 0
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
        selectedEntityFacetID: String? = nil,
        previewLimit: Int
    ) -> [MyWikiIndexCategorySection] {
        let orderedDefinitions = snapshot.categories.enumerated().sorted { lhs, rhs in
            let lhsPriority = MyWikiIndexPreviewPolicy.sortPriority(for: lhs.element.id)
            let rhsPriority = MyWikiIndexPreviewPolicy.sortPriority(for: rhs.element.id)
            if lhsPriority != rhsPriority {
                return lhsPriority < rhsPriority
            }
            return lhs.offset < rhs.offset
        }.map(\.element)

        return orderedDefinitions.compactMap { definition in
            let category = MyWikiCategory(definition: definition)
            let entries = entityFacetFiltered(
                filtered(snapshot.entries(for: definition.id), query: query),
                categoryID: definition.id,
                selectedEntityFacetID: selectedEntityFacetID
            )
            guard entries.isEmpty == false || query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            return MyWikiIndexCategorySection(
                category: category,
                presentation: MyWikiIndexSectionPresentation(
                    title: definition.displayName,
                    entries: entries,
                    isExpanded: expandedCategoryIDs.contains(definition.id),
                    previewLimit: MyWikiIndexPreviewPolicy.previewLimit(
                        for: definition.id,
                        fallback: previewLimit
                    ),
                    isShowingAll: showingAllCategoryIDs.contains(definition.id)
                )
            )
        }
    }

    private func entityFacetFiltered(
        _ entries: [MyWikiEntry],
        categoryID: String,
        selectedEntityFacetID: String?
    ) -> [MyWikiEntry] {
        guard categoryID == MyWikiCategory.entity.id,
              let facet = MyWikiEntityFacet.facet(id: selectedEntityFacetID)
        else {
            return entries
        }
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

    init(definition: MyWikiCategoryDefinition) {
        self.id = definition.id
        self.displayTitle = definition.displayName
        self.singularTitle = definition.singularName
        self.frontmatterType = definition.frontmatterTypes.first ?? definition.id
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
    static let summary = MyWikiCategory(
        id: "summaries",
        displayTitle: "Summaries",
        singularTitle: "Summary",
        frontmatterType: "summary"
    )
    static let person = MyWikiCategory(
        id: "people",
        displayTitle: "People",
        singularTitle: "Person",
        frontmatterType: "person"
    )
    static let project = MyWikiCategory(
        id: "projects",
        displayTitle: "Projects",
        singularTitle: "Project",
        frontmatterType: "project"
    )
    static let event = MyWikiCategory(
        id: "events",
        displayTitle: "Events",
        singularTitle: "Event",
        frontmatterType: "event"
    )
    static let theme = MyWikiCategory(
        id: "topics",
        displayTitle: "Topics",
        singularTitle: "Topic",
        frontmatterType: "topic"
    )
    static let preference = MyWikiCategory(
        id: "preferences",
        displayTitle: "Patterns",
        singularTitle: "Pattern",
        frontmatterType: "preference"
    )
    static let openLoop = MyWikiCategory(
        id: "follow-ups",
        displayTitle: "Follow-ups",
        singularTitle: "Follow-up",
        frontmatterType: "follow-up"
    )
}
