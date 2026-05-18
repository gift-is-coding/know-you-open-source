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
          "id": "sources",
          "displayName": "Sources",
          "singularName": "Source",
          "directory": "wiki/sources",
          "frontmatterTypes": ["source", "knowyou-diary"],
          "extractionGuidance": "Represent KnowYou diary source materials and source indexes. Do not duplicate raw secrets or credentials.",
          "detailSections": ["Summary", "Markdown Page"]
        },
        {
          "id": "entities",
          "displayName": "Entities",
          "singularName": "Entity",
          "directory": "wiki/entities",
          "legacyDirectories": ["wiki/people", "wiki/organizations", "wiki/projects", "wiki/events"],
          "frontmatterTypes": ["entity"],
          "legacyTypes": ["person", "organization", "company", "team", "project", "event"],
          "extractionGuidance": "Extract high-signal people, organizations, tools, products, projects, and other concrete entities that matter across the journal sources.",
          "detailSections": ["Summary", "Recent Mentions", "Sources", "Related", "Markdown Page"]
        },
        {
          "id": "concepts",
          "displayName": "Concepts",
          "singularName": "Concept",
          "directory": "wiki/concepts",
          "legacyDirectories": ["wiki/topics", "wiki/decisions", "wiki/preferences", "wiki/follow-ups", "wiki/summaries"],
          "frontmatterTypes": ["concept"],
          "legacyTypes": ["topic", "decision", "preference", "follow-up", "summary", "overview"],
          "extractionGuidance": "Extract high-signal topics, working patterns, preferences, decisions, open loops, questions, and long-term context from the journals.",
          "detailSections": ["Summary", "Evidence", "Sources", "Related", "Markdown Page"]
        }
      ],
      "views": [
        {
          "id": "recent",
          "displayName": "Recent",
          "kind": "recentActivity",
          "categoryIDs": ["sources", "entities", "concepts"]
        },
        {
          "id": "needs-review",
          "displayName": "Needs Review",
          "kind": "needsReview",
          "categoryIDs": ["sources", "entities", "concepts"]
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

        - Use llm_wiki's native source, entity, and concept pages for extraction, relationship discovery, deduplication, summarization, search ranking, and agent context generation.
        - Prefer a small number of high-signal entity and concept pages over many low-confidence category pages.
        - Every generated page must cite sources using source filenames or source days.
        - Use aliases for alternate spellings and translations; use rename only for the display title.
        - Mark uncertain facts as low confidence or needs review instead of writing them as certain.
        - Do not copy secrets, API keys, tokens, passwords, or complete account identifiers.
        """
    }
}
