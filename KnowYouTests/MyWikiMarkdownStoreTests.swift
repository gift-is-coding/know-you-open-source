import XCTest
@testable import KnowYou

final class MyWikiMarkdownStoreTests: XCTestCase {
    func testLoadsCustomSchemaCategoryWithoutChangingSwiftEnum() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        let schema = MyWikiSchemaConfig(
            id: "custom",
            displayName: "Custom",
            categories: [
                MyWikiCategoryDefinition(
                    id: "relationships",
                    displayName: "Relationships",
                    singularName: "Relationship",
                    directory: "wiki/relationships",
                    frontmatterTypes: ["relationship"],
                    extractionGuidance: "Relationships between entities.",
                    detailSections: ["Summary", "Sources"]
                )
            ],
            views: []
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try encoder.encode(schema).write(to: root.appending(path: "mywiki.schema.json"))
        try FileManager.default.createDirectory(at: root.appending(path: "wiki/relationships"), withIntermediateDirectories: true)
        try """
        ---
        type: relationship
        title: Huang Shan and Lenovo Platform
        sources: ["knowyou-diary-2026-05-14.md"]
        ---

        # Huang Shan and Lenovo Platform

        Huang Shan is responsible for hardware acceleration boundaries.
        """.write(to: root.appending(path: "wiki/relationships/huang-shan-lenovo.md"), atomically: true, encoding: .utf8)

        let snapshot = try MyWikiMarkdownStore(fileManager: .default).loadDashboard(projectRoot: root)

        XCTAssertEqual(snapshot.categories.map(\.id), ["relationships"])
        XCTAssertEqual(snapshot.entries(for: "relationships").map(\.title), ["Huang Shan and Lenovo Platform"])
        XCTAssertEqual(snapshot.entries(for: "relationships").first?.category.singularTitle, "Relationship")
    }

    func testLoadsDashboardSnapshotFromMarkdownFolders() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: root.appending(path: "wiki/people"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appending(path: "wiki/projects"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appending(path: "wiki/themes"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appending(path: "wiki/summaries"), withIntermediateDirectories: true)

        try """
        ---
        type: person
        title: Alex
        sources: ["knowyou-diary-2026-05-12.md"]
        ---

        # Alex

        最近一起讨论 My Wiki 的产品轻量化。
        """.write(to: root.appending(path: "wiki/people/alex.md"), atomically: true, encoding: .utf8)

        try """
        ---
        type: project
        title: KnowYou
        sources: ["knowyou-diary-2026-05-12.md"]
        ---

        # KnowYou

        从日记工具升级为个人 My Wiki。
        """.write(to: root.appending(path: "wiki/projects/knowyou.md"), atomically: true, encoding: .utf8)

        let snapshot = try MyWikiMarkdownStore(fileManager: .default).loadDashboard(projectRoot: root)

        XCTAssertEqual(snapshot.people.map(\.title), ["Alex"])
        XCTAssertEqual(snapshot.projects.map(\.title), ["KnowYou"])
        XCTAssertTrue(snapshot.people[0].summary.contains("产品轻量化"))
        XCTAssertEqual(snapshot.people[0].sourceNames, ["knowyou-diary-2026-05-12.md"])
    }

    func testLoadsAliasesRelatedMentionsAndMarkdownBodyFromWikiPage() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: root.appending(path: "wiki/people"), withIntermediateDirectories: true)
        try """
        ---
        type: person
        title: Huang Shan
        aliases: ["黄山", "huang-shan"]
        related: ["lenovo", "cloud-platform"]
        sources: ["knowyou-diary-2026-05-14.md"]
        source_days: ["2026-05-14"]
        confidence: medium
        ---

        # Huang Shan

        Huang Shan owns hardware-platform coordination.

        ## Recent Mentions

        - 2026-05-14: Discussed K8S scheduling boundaries.
        - 2026-05-07: Clarified platform certification.
        """.write(to: root.appending(path: "wiki/people/huang-shan.md"), atomically: true, encoding: .utf8)

        let snapshot = try MyWikiMarkdownStore(fileManager: .default).loadDashboard(projectRoot: root)

        let entry = try XCTUnwrap(snapshot.people.first)
        XCTAssertEqual(entry.aliases, ["黄山", "huang-shan"])
        XCTAssertEqual(entry.related, ["lenovo", "cloud-platform"])
        XCTAssertEqual(entry.confidence, "medium")
        XCTAssertEqual(entry.mentions.map(\.day), ["2026-05-14", "2026-05-07"])
        XCTAssertTrue(entry.markdownBody.contains("Recent Mentions"))
        XCTAssertEqual(entry.fileURL.lastPathComponent, "huang-shan.md")
    }

    func testLoadDashboardUsesDescriptionFrontmatterAsSummary() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: root.appending(path: "wiki/people"), withIntermediateDirectories: true)
        try """
        ---
        type: person
        title: Adam Wu
        description: Adam coordinates the Lenovo knowledge-platform workstream.
        sources: ["knowyou-diary-2026-05-06.md"]
        ---

        # Adam Wu

        This longer body should not replace the explicit description.
        """.write(to: root.appending(path: "wiki/people/adam-wu.md"), atomically: true, encoding: .utf8)

        let snapshot = try MyWikiMarkdownStore(fileManager: .default).loadDashboard(projectRoot: root)

        XCTAssertEqual(snapshot.people.first?.summary, "Adam coordinates the Lenovo knowledge-platform workstream.")
    }

    func testLoadDashboardUsesSummarySectionBeforeBodyFallback() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: root.appending(path: "wiki/people"), withIntermediateDirectories: true)
        try """
        ---
        type: person
        title: Adam Wu
        sources: ["knowyou-diary-2026-05-06.md"]
        ---

        # Adam Wu

        ## Summary

        Adam connects CTO, DT, and external vendor discussions for the knowledge-platform collaboration.

        ## Recent Mentions

        - 2026-05-06: Adam agreed to include the right colleagues.
        """.write(to: root.appending(path: "wiki/people/adam-wu.md"), atomically: true, encoding: .utf8)

        let snapshot = try MyWikiMarkdownStore(fileManager: .default).loadDashboard(projectRoot: root)

        XCTAssertEqual(
            snapshot.people.first?.summary,
            "Adam connects CTO, DT, and external vendor discussions for the knowledge-platform collaboration."
        )
    }

    func testLoadDashboardFallsBackToFirstBodyParagraph() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: root.appending(path: "wiki/people"), withIntermediateDirectories: true)
        try """
        ---
        type: person
        title: Adam Wu
        sources: ["knowyou-diary-2026-05-06.md"]
        ---

        # Adam Wu

        Adam helps connect knowledge-platform planning across teams.

        A second paragraph has extra detail that should stay in the markdown body.
        """.write(to: root.appending(path: "wiki/people/adam-wu.md"), atomically: true, encoding: .utf8)

        let snapshot = try MyWikiMarkdownStore(fileManager: .default).loadDashboard(projectRoot: root)

        XCTAssertEqual(snapshot.people.first?.summary, "Adam helps connect knowledge-platform planning across teams.")
    }

    func testLoadDashboardSkipsStarterExtractorPages() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: root.appending(path: "wiki/people"), withIntermediateDirectories: true)
        try page(title: "Adam", aliases: [], body: "Adam appears as a real person mentioned in the journal evidence below.")
            .replacingOccurrences(of: "confidence: medium", with: "confidence: medium\ngenerated_by: KnowYou My Wiki starter extractor")
            .write(to: root.appending(path: "wiki/people/adam.md"), atomically: true, encoding: .utf8)
        try page(title: "Adam Wu", aliases: [], body: "Adam coordinates the Lenovo knowledge-platform workstream.")
            .write(to: root.appending(path: "wiki/people/adam-wu.md"), atomically: true, encoding: .utf8)

        let snapshot = try MyWikiMarkdownStore().loadDashboard(projectRoot: root)

        XCTAssertEqual(snapshot.people.map(\.title), ["Adam Wu"])
    }

    func testHidesStarterGeneratedAiToolsFromPeopleAndProjects() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: root.appending(path: "wiki/people"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appending(path: "wiki/projects"), withIntermediateDirectories: true)
        try page(title: "Codex", aliases: [], body: "Codex agent appears in journals.")
            .replacingOccurrences(of: "confidence: medium", with: "confidence: medium\ngenerated_by: KnowYou My Wiki starter extractor")
            .write(to: root.appending(path: "wiki/people/codex.md"), atomically: true, encoding: .utf8)
        try page(title: "Claude / Cowork", aliases: [], body: "Claude and Cowork agent workflow.")
            .replacingOccurrences(of: "type: person", with: "type: project")
            .replacingOccurrences(of: "confidence: medium", with: "confidence: medium\ngenerated_by: KnowYou My Wiki starter extractor")
            .write(to: root.appending(path: "wiki/projects/claude-cowork.md"), atomically: true, encoding: .utf8)

        let snapshot = try MyWikiMarkdownStore().loadDashboard(projectRoot: root)

        XCTAssertTrue(snapshot.people.isEmpty)
        XCTAssertTrue(snapshot.projects.isEmpty)
    }

    func testMarkdownPreviewCapsLargeEntryBodiesForResponsiveSelection() {
        let largeBody = String(repeating: "A", count: 9_000)
        let entry = MyWikiEntry(
            id: "large",
            title: "Large Page",
            category: .theme,
            summary: "Summary",
            sourceNames: [],
            markdownBody: largeBody
        )

        let presentation = MyWikiDetailPresentation(entry: entry, markdownPreviewLimit: 512)

        XCTAssertEqual(presentation.markdownText.count, 512)
        XCTAssertTrue(presentation.isMarkdownTruncated)
    }

    func testRenameServiceUpdatesTitleAliasesAndDetectsNameConflict() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        let people = root.appending(path: "wiki/people", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: people, withIntermediateDirectories: true)
        try page(title: "Huang Shan", aliases: ["黄山"], body: "Original summary.")
            .write(to: people.appending(path: "huang-shan.md"), atomically: true, encoding: .utf8)
        try page(title: "Billy", aliases: [], body: "Existing person.")
            .write(to: people.appending(path: "billy.md"), atomically: true, encoding: .utf8)

        let store = MyWikiMarkdownStore(fileManager: .default)
        var snapshot = try store.loadDashboard(projectRoot: root)
        let huangShan = try XCTUnwrap(snapshot.people.first { $0.id == "huang-shan" })

        let renameResult = try MyWikiRenameService(fileManager: .default).rename(
            huangShan,
            to: "H. Shan",
            aliases: ["黄山", "huang-shan"],
            summary: "Updated summary.",
            projectRoot: root
        )
        XCTAssertEqual(renameResult, .renamed)

        snapshot = try store.loadDashboard(projectRoot: root)
        let renamed = try XCTUnwrap(snapshot.people.first { $0.id == "huang-shan" })
        XCTAssertEqual(renamed.title, "H. Shan")
        XCTAssertTrue(renamed.aliases.contains("Huang Shan"))
        XCTAssertTrue(renamed.summary.contains("Updated summary."))

        let conflict = try MyWikiRenameService(fileManager: .default).rename(
            renamed,
            to: "Billy",
            aliases: renamed.aliases,
            summary: renamed.summary,
            projectRoot: root
        )
        XCTAssertEqual(conflict, .conflict(existingTitle: "Billy"))
    }

    func testDuplicateServiceFindsAliasOverlapAndMergesConfirmedGroup() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        let people = root.appending(path: "wiki/people", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: people, withIntermediateDirectories: true)
        try page(
            title: "Huang Shan",
            aliases: ["黄山"],
            related: ["lenovo"],
            sources: ["knowyou-diary-2026-05-14.md"],
            body: "Hardware platform owner."
        ).write(to: people.appending(path: "huang-shan.md"), atomically: true, encoding: .utf8)
        try page(
            title: "黄山",
            aliases: ["huang-shan"],
            related: ["cloud-platform"],
            sources: ["knowyou-diary-2026-05-07.md"],
            body: "Platform certification owner."
        ).write(to: people.appending(path: "huang-shan-cn.md"), atomically: true, encoding: .utf8)

        let service = MyWikiDuplicateService(fileManager: .default)
        let suggestions = try service.findDuplicateSuggestions(projectRoot: root)

        XCTAssertEqual(suggestions.first?.entries.map(\.id).sorted(), ["huang-shan", "huang-shan-cn"])

        try service.merge(
            suggestion: try XCTUnwrap(suggestions.first),
            canonicalID: "huang-shan",
            projectRoot: root
        )

        let snapshot = try MyWikiMarkdownStore().loadDashboard(projectRoot: root)
        let merged = try XCTUnwrap(snapshot.people.first { $0.id == "huang-shan" })
        XCTAssertEqual(snapshot.people.count, 1)
        XCTAssertTrue(merged.aliases.contains("黄山"))
        XCTAssertTrue(merged.aliases.contains("huang-shan"))
        XCTAssertEqual(Set(merged.sourceNames), ["knowyou-diary-2026-05-14.md", "knowyou-diary-2026-05-07.md"])
        XCTAssertEqual(Set(merged.related), ["lenovo", "cloud-platform"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appending(path: ".llm-wiki/page-history").path))
    }

    func testDuplicateServiceFindsSameTitlePagesWithDifferentSlugs() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        let people = root.appending(path: "wiki/people", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: people, withIntermediateDirectories: true)
        try page(
            title: "郭强",
            aliases: [],
            related: ["my-ai-builder"],
            sources: ["knowyou-diary-2026-04-28.md"],
            body: "Asked about My AI Builder positioning."
        ).write(to: people.appending(path: "guo-qiang.md"), atomically: true, encoding: .utf8)
        try page(
            title: "郭强",
            aliases: [],
            related: ["field-data-engineering"],
            sources: ["knowyou-diary-2026-05-14.md"],
            body: "Defined the FDE three-layer closed loop."
        ).write(to: people.appending(path: "qiang-guo.md"), atomically: true, encoding: .utf8)

        let suggestions = try MyWikiDuplicateService().findDuplicateSuggestions(projectRoot: root)

        XCTAssertEqual(suggestions.first?.entries.map(\.id).sorted(), ["guo-qiang", "qiang-guo"])
    }

    private func page(
        title: String,
        aliases: [String],
        related: [String] = [],
        sources: [String] = [],
        body: String
    ) -> String {
        """
        ---
        type: person
        title: \(title)
        aliases: [\(aliases.map { "\"\($0)\"" }.joined(separator: ", "))]
        related: [\(related.map { "\"\($0)\"" }.joined(separator: ", "))]
        sources: [\(sources.map { "\"\($0)\"" }.joined(separator: ", "))]
        confidence: medium
        ---

        # \(title)

        \(body)
        """
    }
}
