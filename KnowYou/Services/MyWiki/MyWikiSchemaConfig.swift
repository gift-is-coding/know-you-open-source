import Foundation

struct MyWikiSchemaConfig: Codable, Equatable {
    let id: String
    let displayName: String
    let categories: [MyWikiCategoryDefinition]
    let views: [MyWikiViewDefinition]

    static func defaultPersonalContext() throws -> MyWikiSchemaConfig {
        let data = Data(defaultPersonalContextJSON.utf8)
        return try JSONDecoder().decode(MyWikiSchemaConfig.self, from: data)
    }

    private static let defaultPersonalContextJSON = """
    {
      "id": "personal-context-default",
      "displayName": "Personal Context",
      "categories": [
        {
          "id": "people",
          "displayName": "People",
          "singularName": "Person",
          "directory": "wiki/people",
          "frontmatterTypes": ["person"],
          "extractionGuidance": "Extract real individual people only: family, friends, collaborators, customers, investors, creators, or named public figures. Do not classify tools, agents, companies, or product names as people.",
          "detailSections": ["Summary", "Recent Mentions", "Sources", "Related", "Markdown Page"]
        },
        {
          "id": "organizations",
          "displayName": "Organizations",
          "singularName": "Organization",
          "directory": "wiki/organizations",
          "frontmatterTypes": ["organization", "company", "team"],
          "extractionGuidance": "Extract companies, teams, communities, institutions, and product organizations that recur in the source material.",
          "detailSections": ["Summary", "Recent Mentions", "Sources", "Related", "Markdown Page"]
        },
        {
          "id": "projects",
          "displayName": "Projects",
          "singularName": "Project",
          "directory": "wiki/projects",
          "frontmatterTypes": ["project"],
          "extractionGuidance": "Extract ongoing bodies of work with goals, milestones, owners, or repeated execution context.",
          "detailSections": ["Summary", "Recent Mentions", "Sources", "Related", "Markdown Page"]
        },
        {
          "id": "events",
          "displayName": "Events",
          "singularName": "Event",
          "directory": "wiki/events",
          "frontmatterTypes": ["event"],
          "extractionGuidance": "Extract bounded happenings such as meetings, calls, trips, launches, deadlines, incidents, or decisions made at a specific time.",
          "detailSections": ["Summary", "Recent Mentions", "Sources", "Related", "Markdown Page"]
        },
        {
          "id": "topics",
          "displayName": "Topics",
          "singularName": "Topic",
          "directory": "wiki/topics",
          "legacyDirectories": ["wiki/themes"],
          "frontmatterTypes": ["topic"],
          "legacyTypes": ["theme"],
          "extractionGuidance": "Extract recurring themes, interests, questions, fields, technical areas, product ideas, and conceptual concerns.",
          "detailSections": ["Summary", "Recent Mentions", "Sources", "Related", "Markdown Page"]
        },
        {
          "id": "decisions",
          "displayName": "Decisions",
          "singularName": "Decision",
          "directory": "wiki/decisions",
          "frontmatterTypes": ["decision"],
          "extractionGuidance": "Extract explicit choices, trade-offs, commitments, and policy decisions that should guide future behavior.",
          "detailSections": ["Summary", "Rationale", "Sources", "Related", "Markdown Page"]
        },
        {
          "id": "preferences",
          "displayName": "Preferences",
          "singularName": "Preference",
          "directory": "wiki/preferences",
          "frontmatterTypes": ["preference"],
          "extractionGuidance": "Extract stable user preferences, working style, product taste, communication preferences, and explicit long-term constraints.",
          "detailSections": ["Summary", "Evidence", "Sources", "Related", "Markdown Page"]
        },
        {
          "id": "follow-ups",
          "displayName": "Follow-ups",
          "singularName": "Follow-up",
          "directory": "wiki/follow-ups",
          "legacyDirectories": ["wiki/open-loops"],
          "frontmatterTypes": ["follow-up"],
          "legacyTypes": ["open-loop"],
          "extractionGuidance": "Extract unresolved open loops, promised next steps, pending asks, waiting-for items, and things the user wants to revisit.",
          "detailSections": ["Summary", "Status", "Sources", "Related", "Markdown Page"]
        },
        {
          "id": "summaries",
          "displayName": "Summaries",
          "singularName": "Summary",
          "directory": "wiki/summaries",
          "frontmatterTypes": ["summary", "overview"],
          "extractionGuidance": "Create readable synthesis pages across days, weeks, projects, or themes. Summaries should cite sources and avoid inventing facts.",
          "detailSections": ["Summary", "Sources", "Markdown Page"]
        },
        {
          "id": "sources",
          "displayName": "Sources",
          "singularName": "Source",
          "directory": "wiki/sources",
          "frontmatterTypes": ["source", "knowyou-diary"],
          "extractionGuidance": "Represent source materials and source indexes. Do not duplicate raw secrets or credentials.",
          "detailSections": ["Summary", "Markdown Page"]
        }
      ],
      "views": [
        {
          "id": "recent",
          "displayName": "Recent",
          "kind": "recentActivity",
          "categoryIDs": ["people", "organizations", "projects", "events", "topics", "decisions", "preferences", "follow-ups"]
        },
        {
          "id": "needs-review",
          "displayName": "Needs Review",
          "kind": "needsReview",
          "categoryIDs": ["people", "organizations", "projects", "events", "topics", "decisions", "preferences", "follow-ups"]
        }
      ]
    }
    """
}

struct MyWikiCategoryDefinition: Codable, Equatable, Hashable, Identifiable {
    let id: String
    let displayName: String
    let singularName: String
    let directory: String
    let legacyDirectories: [String]
    let frontmatterTypes: [String]
    let legacyTypes: [String]
    let extractionGuidance: String
    let detailSections: [String]

    var directoryCandidates: [String] {
        ([directory] + legacyDirectories).uniqued()
    }

    var typeCandidates: [String] {
        (frontmatterTypes + legacyTypes).uniqued()
    }

    init(
        id: String,
        displayName: String,
        singularName: String,
        directory: String,
        legacyDirectories: [String] = [],
        frontmatterTypes: [String],
        legacyTypes: [String] = [],
        extractionGuidance: String,
        detailSections: [String]
    ) {
        self.id = id
        self.displayName = displayName
        self.singularName = singularName
        self.directory = directory
        self.legacyDirectories = legacyDirectories
        self.frontmatterTypes = frontmatterTypes
        self.legacyTypes = legacyTypes
        self.extractionGuidance = extractionGuidance
        self.detailSections = detailSections
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        displayName = try container.decode(String.self, forKey: .displayName)
        singularName = try container.decode(String.self, forKey: .singularName)
        directory = try container.decode(String.self, forKey: .directory)
        legacyDirectories = try container.decodeIfPresent([String].self, forKey: .legacyDirectories) ?? []
        frontmatterTypes = try container.decode([String].self, forKey: .frontmatterTypes)
        legacyTypes = try container.decodeIfPresent([String].self, forKey: .legacyTypes) ?? []
        extractionGuidance = try container.decode(String.self, forKey: .extractionGuidance)
        detailSections = try container.decodeIfPresent([String].self, forKey: .detailSections) ?? []
    }
}

struct MyWikiViewDefinition: Codable, Equatable, Identifiable {
    let id: String
    let displayName: String
    let kind: MyWikiViewKind
    let categoryIDs: [String]
}

enum MyWikiViewKind: String, Codable, Equatable {
    case recentActivity
    case needsReview
    case categoryList
}

struct MyWikiSchemaMarkdownRenderer {
    func render(_ schema: MyWikiSchemaConfig) -> String {
        let categoryRows = schema.categories.map { category in
            "| \(category.displayName) | `\(category.directory)` | \(category.frontmatterTypes.map { "`\($0)`" }.joined(separator: ", ")) | \(category.extractionGuidance) |"
        }
        .joined(separator: "\n")

        let guidance = schema.categories.map { category in
            """
            ### \(category.displayName)
            - Directory: `\(category.directory)`
            - Types: \(category.frontmatterTypes.joined(separator: ", "))
            - Guidance: \(category.extractionGuidance)
            """
        }
        .joined(separator: "\n\n")

        return """
        # My Wiki Schema

        Generated from `mywiki.schema.json`. Treat it as the source of truth for ontology extraction and page organization.

        ## Categories

        | Category | Directory | Frontmatter types | Extraction guidance |
        |---|---|---|---|
        \(categoryRows)

        ## Extraction Contract

        \(guidance)

        ## Shared Rules

        - Use LLM semantic understanding for ontology extraction, relationship discovery, deduplication, summarization, search ranking, and agent context generation.
        - Do not classify tools, agents, products, or companies as people.
        - Every generated page must cite sources using source filenames or source days.
        - Use aliases for alternate spellings and translations; use rename only for the display title.
        - Mark uncertain facts as low confidence or needs review instead of writing them as certain.
        - Do not copy secrets, API keys, tokens, passwords, or complete account identifiers.
        """
    }
}
