import XCTest
@testable import KnowYou

final class MyWikiMarkdownStoreTests: XCTestCase {
    func testLoadsOnlyNativeLlmWikiDirectoriesAndIgnoresSchemaAndLegacyDirectories() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try """
        {"categories":[{"id":"relationships","displayName":"Relationships","singularName":"Relationship","directory":"wiki/relationships","frontmatterTypes":["relationship"],"extractionGuidance":"Custom guidance","detailSections":["Summary"]}]}
        """.write(to: root.appending(path: "mywiki.schema.json"), atomically: true, encoding: .utf8)

        try FileManager.default.createDirectory(at: root.appending(path: "wiki/entities"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appending(path: "wiki/concepts"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appending(path: "wiki/sources"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appending(path: "wiki/people"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appending(path: "wiki/relationships"), withIntermediateDirectories: true)

        try page(type: "entity", title: "Huang Shan", body: "Huang Shan coordinates hardware acceleration boundaries.")
            .write(to: root.appending(path: "wiki/entities/huang-shan.md"), atomically: true, encoding: .utf8)
        try page(type: "concept", title: "Agentic Engineering", body: "Agentic engineering is a recurring working pattern.")
            .write(to: root.appending(path: "wiki/concepts/agentic-engineering.md"), atomically: true, encoding: .utf8)
        try page(type: "source", title: "Diary 2026-05-14", body: "Source summary.")
            .write(to: root.appending(path: "wiki/sources/knowyou-diary-2026-05-14.md"), atomically: true, encoding: .utf8)
        try page(type: "person", title: "Alex", body: "Legacy people pages are ignored.")
            .write(to: root.appending(path: "wiki/people/alex.md"), atomically: true, encoding: .utf8)
        try page(type: "relationship", title: "Huang Shan and Lenovo", body: "Custom schema pages are ignored.")
            .write(to: root.appending(path: "wiki/relationships/huang-shan-lenovo.md"), atomically: true, encoding: .utf8)

        let snapshot = try MyWikiMarkdownStore(fileManager: .default).loadDashboard(projectRoot: root)

        XCTAssertEqual(snapshot.categories.map(\.id), ["sources", "entities", "concepts"])
        XCTAssertEqual(snapshot.sources.map(\.title), ["Diary 2026-05-14"])
        XCTAssertEqual(snapshot.entities.map(\.title), ["Huang Shan"])
        XCTAssertEqual(snapshot.concepts.map(\.title), ["Agentic Engineering"])
        XCTAssertEqual(snapshot.primaryEntries.map(\.category.id).sorted(), ["concepts", "entities"])
        XCTAssertTrue(snapshot.entries(for: "relationships").isEmpty)
        XCTAssertTrue(snapshot.entries(for: "people").isEmpty)
    }

    func testLoadsAliasesRelatedMentionsAndMarkdownBodyFromNativeEntityPage() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: root.appending(path: "wiki/entities"), withIntermediateDirectories: true)
        try """
        ---
        type: entity
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
        """.write(to: root.appending(path: "wiki/entities/huang-shan.md"), atomically: true, encoding: .utf8)

        let snapshot = try MyWikiMarkdownStore(fileManager: .default).loadDashboard(projectRoot: root)

        let entry = try XCTUnwrap(snapshot.entities.first)
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

        try FileManager.default.createDirectory(at: root.appending(path: "wiki/entities"), withIntermediateDirectories: true)
        try """
        ---
        type: entity
        title: Adam Wu
        description: Adam coordinates the Lenovo knowledge-platform workstream.
        sources: ["knowyou-diary-2026-05-06.md"]
        ---

        # Adam Wu

        This longer body should not replace the explicit description.
        """.write(to: root.appending(path: "wiki/entities/adam-wu.md"), atomically: true, encoding: .utf8)

        let snapshot = try MyWikiMarkdownStore(fileManager: .default).loadDashboard(projectRoot: root)

        XCTAssertEqual(snapshot.entities.first?.summary, "Adam coordinates the Lenovo knowledge-platform workstream.")
    }

    func testLoadDashboardUsesSummarySectionBeforeBodyFallback() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: root.appending(path: "wiki/entities"), withIntermediateDirectories: true)
        try """
        ---
        type: entity
        title: Adam Wu
        sources: ["knowyou-diary-2026-05-06.md"]
        ---

        # Adam Wu

        ## Summary

        Adam connects CTO, DT, and external vendor discussions for the knowledge-platform collaboration.

        ## Recent Mentions

        - 2026-05-06: Adam agreed to include the right colleagues.
        """.write(to: root.appending(path: "wiki/entities/adam-wu.md"), atomically: true, encoding: .utf8)

        let snapshot = try MyWikiMarkdownStore(fileManager: .default).loadDashboard(projectRoot: root)

        XCTAssertEqual(
            snapshot.entities.first?.summary,
            "Adam connects CTO, DT, and external vendor discussions for the knowledge-platform collaboration."
        )
    }

    func testLoadDashboardFallsBackToFirstBodyParagraph() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: root.appending(path: "wiki/entities"), withIntermediateDirectories: true)
        try """
        ---
        type: entity
        title: Adam Wu
        sources: ["knowyou-diary-2026-05-06.md"]
        ---

        # Adam Wu

        Adam helps connect knowledge-platform planning across teams.

        A second paragraph has extra detail that should stay in the markdown body.
        """.write(to: root.appending(path: "wiki/entities/adam-wu.md"), atomically: true, encoding: .utf8)

        let snapshot = try MyWikiMarkdownStore(fileManager: .default).loadDashboard(projectRoot: root)

        XCTAssertEqual(snapshot.entities.first?.summary, "Adam helps connect knowledge-platform planning across teams.")
    }

    func testLoadsStarterMetadataAndAiToolPagesFromNativeDirectories() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: root.appending(path: "wiki/entities"), withIntermediateDirectories: true)
        try page(title: "Codex", tags: ["agent"], body: "Codex agent appears in journals.")
            .replacingOccurrences(of: "confidence: medium", with: "confidence: medium\ngenerated_by: KnowYou My Wiki starter extractor")
            .write(to: root.appending(path: "wiki/entities/codex.md"), atomically: true, encoding: .utf8)

        let snapshot = try MyWikiMarkdownStore().loadDashboard(projectRoot: root)

        XCTAssertEqual(snapshot.entities.map(\.title), ["Codex"])
    }

    func testMarkdownPreviewCapsLargeEntryBodiesForResponsiveSelection() {
        let largeBody = String(repeating: "A", count: 9_000)
        let entry = MyWikiEntry(
            id: "large",
            title: "Large Page",
            category: .concept,
            summary: "Summary",
            sourceNames: [],
            markdownBody: largeBody
        )

        let presentation = MyWikiDetailPresentation(entry: entry, markdownPreviewLimit: 512)

        XCTAssertEqual(presentation.markdownText.count, 512)
        XCTAssertTrue(presentation.isMarkdownTruncated)
    }

    func testDynamicTagFacetsComeFromFrontmatterAndSortByFrequency() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        let entities = root.appending(path: "wiki/entities", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: entities, withIntermediateDirectories: true)
        try page(title: "Token Hub", tags: ["platform", "agent"], body: "Token Hub is a platform project.")
            .write(to: entities.appending(path: "token-hub.md"), atomically: true, encoding: .utf8)
        try page(title: "AI Force", tags: ["platform"], body: "AI Force is reused as a platform foundation.")
            .write(to: entities.appending(path: "ai-force.md"), atomically: true, encoding: .utf8)
        try page(title: "No Tags", tags: [], body: "This entry has no tags.")
            .write(to: entities.appending(path: "no-tags.md"), atomically: true, encoding: .utf8)

        let snapshot = try MyWikiMarkdownStore().loadDashboard(projectRoot: root)
        let facets = MyWikiTagFacet.facets(for: snapshot.entities)

        XCTAssertEqual(facets.map(\.title), ["platform", "agent"])
        XCTAssertEqual(facets.map(\.count), [2, 1])
        XCTAssertTrue(facets[0].matches(snapshot.entities.first { $0.title == "Token Hub" }!))
        XCTAssertFalse(facets[1].matches(snapshot.entities.first { $0.title == "AI Force" }!))
    }

    func testRenameServiceUpdatesTitleAliasesAndDetectsNameConflict() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        let entities = root.appending(path: "wiki/entities", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: entities, withIntermediateDirectories: true)
        try page(title: "Huang Shan", aliases: ["黄山"], body: "Original summary.")
            .write(to: entities.appending(path: "huang-shan.md"), atomically: true, encoding: .utf8)
        try page(title: "Billy", aliases: [], body: "Existing entity.")
            .write(to: entities.appending(path: "billy.md"), atomically: true, encoding: .utf8)

        let store = MyWikiMarkdownStore(fileManager: .default)
        var snapshot = try store.loadDashboard(projectRoot: root)
        let huangShan = try XCTUnwrap(snapshot.entities.first { $0.id == "huang-shan" })

        let renameResult = try MyWikiRenameService(fileManager: .default).rename(
            huangShan,
            to: "H. Shan",
            aliases: ["黄山", "huang-shan"],
            summary: "Updated summary.",
            projectRoot: root
        )
        XCTAssertEqual(renameResult, .renamed)

        snapshot = try store.loadDashboard(projectRoot: root)
        let renamed = try XCTUnwrap(snapshot.entities.first { $0.id == "huang-shan" })
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

        let entities = root.appending(path: "wiki/entities", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: entities, withIntermediateDirectories: true)
        try page(
            title: "Huang Shan",
            aliases: ["黄山"],
            related: ["lenovo"],
            sources: ["knowyou-diary-2026-05-14.md"],
            body: "Hardware platform owner."
        ).write(to: entities.appending(path: "huang-shan.md"), atomically: true, encoding: .utf8)
        try page(
            title: "黄山",
            aliases: ["huang-shan"],
            related: ["cloud-platform"],
            sources: ["knowyou-diary-2026-05-07.md"],
            body: "Platform certification owner."
        ).write(to: entities.appending(path: "huang-shan-cn.md"), atomically: true, encoding: .utf8)

        let service = MyWikiDuplicateService(fileManager: .default)
        let suggestions = try service.findDuplicateSuggestions(projectRoot: root)

        XCTAssertEqual(suggestions.first?.entries.map(\.id).sorted(), ["huang-shan", "huang-shan-cn"])

        try service.merge(
            suggestion: try XCTUnwrap(suggestions.first),
            canonicalID: "huang-shan",
            projectRoot: root
        )

        let snapshot = try MyWikiMarkdownStore().loadDashboard(projectRoot: root)
        let merged = try XCTUnwrap(snapshot.entities.first { $0.id == "huang-shan" })
        XCTAssertEqual(snapshot.entities.count, 1)
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

        let entities = root.appending(path: "wiki/entities", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: entities, withIntermediateDirectories: true)
        try page(
            title: "郭强",
            aliases: [],
            related: ["my-ai-builder"],
            sources: ["knowyou-diary-2026-04-28.md"],
            body: "Asked about My AI Builder positioning."
        ).write(to: entities.appending(path: "guo-qiang.md"), atomically: true, encoding: .utf8)
        try page(
            title: "郭强",
            aliases: [],
            related: ["field-data-engineering"],
            sources: ["knowyou-diary-2026-05-14.md"],
            body: "Defined the FDE three-layer closed loop."
        ).write(to: entities.appending(path: "qiang-guo.md"), atomically: true, encoding: .utf8)

        let suggestions = try MyWikiDuplicateService().findDuplicateSuggestions(projectRoot: root)

        XCTAssertEqual(suggestions.first?.entries.map(\.id).sorted(), ["guo-qiang", "qiang-guo"])
    }

    private func page(
        type: String = "entity",
        title: String,
        aliases: [String] = [],
        related: [String] = [],
        sources: [String] = [],
        tags: [String] = [],
        body: String
    ) -> String {
        """
        ---
        type: \(type)
        title: \(title)
        aliases: [\(aliases.map { "\"\($0)\"" }.joined(separator: ", "))]
        related: [\(related.map { "\"\($0)\"" }.joined(separator: ", "))]
        tags: [\(tags.map { "\"\($0)\"" }.joined(separator: ", "))]
        sources: [\(sources.map { "\"\($0)\"" }.joined(separator: ", "))]
        confidence: medium
        ---

        # \(title)

        \(body)
        """
    }
}
