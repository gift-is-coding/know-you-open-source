import XCTest
@testable import KnowYou

final class KnowledgeOntologyPanelTests: XCTestCase {
    func testMyWikiCategoryLabelsAreUserFacing() {
        XCTAssertEqual(MyWikiCategory.source.displayTitle, "Sources")
        XCTAssertEqual(MyWikiCategory.entity.displayTitle, "Entities")
        XCTAssertEqual(MyWikiCategory.concept.displayTitle, "Concepts")
    }

    func testLegacyMyWikiCategoryLabelsRemainAvailableForExistingPages() {
        XCTAssertEqual(MyWikiCategory.person.displayTitle, "People")
        XCTAssertEqual(MyWikiCategory.project.displayTitle, "Projects")
        XCTAssertEqual(MyWikiCategory.theme.displayTitle, "Topics")
        XCTAssertEqual(MyWikiCategory.preference.displayTitle, "Patterns")
        XCTAssertEqual(MyWikiCategory.openLoop.displayTitle, "Follow-ups")
        XCTAssertEqual(MyWikiCategory.summary.displayTitle, "Summaries")
    }

    func testDefaultMyWikiCopyDescribesNativeLlmWikiCategories() {
        let copy = [
            MyWikiUserFacingCopy.overviewSubtitle,
            MyWikiUserFacingCopy.duplicateSuggestionSubtitle,
            MyWikiUserFacingCopy.detailPlaceholder,
        ].joined(separator: " ")

        XCTAssertTrue(copy.contains("sources"))
        XCTAssertTrue(copy.contains("entities"))
        XCTAssertTrue(copy.contains("concepts"))
        XCTAssertFalse(copy.localizedCaseInsensitiveContains("people, projects"))
        XCTAssertFalse(copy.localizedCaseInsensitiveContains("topics, patterns"))
        XCTAssertFalse(copy.localizedCaseInsensitiveContains("follow-ups"))
    }

    func testIndexSectionPresentationSupportsInlineShowMoreStates() {
        let entries = (1...6).map { index in
            MyWikiEntry(
                id: "person-\(index)",
                title: "Person \(index)",
                category: .person,
                summary: "Summary \(index)",
                sourceNames: []
            )
        }

        let expanded = MyWikiIndexSectionPresentation(
            title: "People",
            entries: entries,
            isExpanded: true,
            previewLimit: 3,
            isShowingAll: false
        )
        XCTAssertEqual(expanded.visibleEntries.map(\.title), ["Person 1", "Person 2", "Person 3"])
        XCTAssertTrue(expanded.canShowMore)
        XCTAssertEqual(expanded.hiddenCount, 3)
        XCTAssertEqual(expanded.showMoreTitle, "Show more (3)")

        let showingAll = MyWikiIndexSectionPresentation(
            title: "People",
            entries: entries,
            isExpanded: true,
            previewLimit: 3,
            isShowingAll: true
        )
        XCTAssertEqual(showingAll.visibleEntries.map(\.title), entries.map(\.title))
        XCTAssertTrue(showingAll.canShowLess)
        XCTAssertEqual(showingAll.showMoreTitle, "Show less")
    }

    func testIndexSectionsComeFromSchemaCategories() {
        let relationshipCategory = MyWikiCategoryDefinition(
            id: "relationships",
            displayName: "Relationships",
            singularName: "Relationship",
            directory: "wiki/relationships",
            frontmatterTypes: ["relationship"],
            extractionGuidance: "Relationships between entities.",
            detailSections: ["Summary"]
        )
        let memoriesCategory = MyWikiCategoryDefinition(
            id: "memories",
            displayName: "Memories",
            singularName: "Memory",
            directory: "wiki/memories",
            frontmatterTypes: ["memory"],
            extractionGuidance: "Personal memory records.",
            detailSections: ["Summary"]
        )
        let schema = MyWikiSchemaConfig(
            id: "custom",
            displayName: "Custom",
            categories: [relationshipCategory, memoriesCategory],
            views: []
        )
        let entry = MyWikiEntry(
            id: "huang-shan-lenovo",
            title: "Huang Shan and Lenovo",
            category: MyWikiCategory(definition: relationshipCategory),
            summary: "Relationship summary",
            sourceNames: []
        )
        let snapshot = MyWikiDashboardSnapshot(
            schema: schema,
            entriesByCategoryID: ["relationships": [entry]]
        )

        let sections = MyWikiIndexSectionsBuilder().categorySections(
            snapshot: snapshot,
            query: "",
            expandedCategoryIDs: ["relationships"],
            previewLimit: 4
        )

        XCTAssertEqual(sections.map(\.category.id), ["relationships", "memories"])
        XCTAssertEqual(sections.first?.presentation.title, "Relationships")
        XCTAssertEqual(sections.first?.presentation.visibleEntries.map(\.title), ["Huang Shan and Lenovo"])
    }

    func testDefaultIndexSectionsPrioritizeEntitiesAndConceptsBeforeSources() throws {
        let schema = try MyWikiSchemaConfig.defaultPersonalContext()
        let sourceEntries = makeEntries(prefix: "Source", category: .source, count: 12)
        let entityEntries = makeEntries(prefix: "Entity", category: .entity, count: 12)
        let conceptEntries = makeEntries(prefix: "Concept", category: .concept, count: 12)
        let snapshot = MyWikiDashboardSnapshot(
            schema: schema,
            entriesByCategoryID: [
                MyWikiCategory.source.id: sourceEntries,
                MyWikiCategory.entity.id: entityEntries,
                MyWikiCategory.concept.id: conceptEntries,
            ]
        )

        let sections = MyWikiIndexSectionsBuilder().categorySections(
            snapshot: snapshot,
            query: "",
            expandedCategoryIDs: [MyWikiCategory.source.id, MyWikiCategory.entity.id, MyWikiCategory.concept.id],
            previewLimit: 4
        )

        XCTAssertEqual(sections.map(\.category.id), [
            MyWikiCategory.entity.id,
            MyWikiCategory.concept.id,
            MyWikiCategory.source.id,
        ])
        XCTAssertEqual(sections[0].presentation.visibleEntries.count, 10)
        XCTAssertEqual(sections[1].presentation.visibleEntries.count, 10)
        XCTAssertEqual(sections[2].presentation.visibleEntries.count, 10)
    }

    func testMyWikiPanelDoesNotRunPipelineOnAppear() {
        XCTAssertEqual(MyWikiPanelLifecyclePolicy.onAppearActions, [.loadDashboard])
        XCTAssertFalse(MyWikiPanelLifecyclePolicy.onAppearActions.contains(.syncDiaries))
    }

    func testMainWindowLaunchPolicyUsesPresentedSingleWindow() {
        XCTAssertEqual(KnowYouMainWindowLaunchPolicy.title, "KnowYou")
        XCTAssertFalse(KnowYouMainWindowLaunchPolicy.usesSwiftUIWindowScene)
        XCTAssertTrue(KnowYouMainWindowLaunchPolicy.usesAppKitPresenter)
    }

    func testMainWindowWorkspacePolicyKeepsToolbarStableAcrossSidebarModes() {
        XCTAssertTrue(MainWindowWorkspacePolicy.usesUnifiedNavigationSplitViewAcrossModes)
        XCTAssertTrue(MainWindowWorkspacePolicy.keepsEngineSelectorInGlobalToolbar)
    }

    func testDetailPresentationShowsMarkdownPageByDefault() {
        let entry = MyWikiEntry(
            id: "adam-wu",
            title: "Adam Wu",
            category: .person,
            summary: "Adam coordinates the knowledge-platform workstream.",
            sourceNames: ["knowyou-diary-2026-05-06.md"],
            markdownBody: "# Adam Wu\n\nFull markdown body."
        )

        let presentation = MyWikiDetailPresentation(entry: entry)

        XCTAssertTrue(presentation.showsMarkdownPage)
        XCTAssertEqual(presentation.markdownText, "# Adam Wu\n\nFull markdown body.")
    }

    func testDetailLayoutDoesNotRepeatStandaloneSummaryCard() {
        XCTAssertFalse(MyWikiDetailLayoutPolicy.showsStandaloneSummaryCard)
    }

    func testIndexRowUsesSimpleNameOnlyPolicy() {
        XCTAssertTrue(MyWikiIndexRowHitTargetPolicy.usesFullRowContentShape)
        XCTAssertFalse(MyWikiIndexRowHitTargetPolicy.showsSummary)
        XCTAssertFalse(MyWikiIndexRowHitTargetPolicy.showsCategoryBadge)
        XCTAssertEqual(MyWikiIndexRowHitTargetPolicy.minHeight, 34)
    }

    func testEntityFacetsUseUserFacingLabelsAndTagExamples() {
        XCTAssertEqual(MyWikiEntityFacet.defaults.map(\.title), ["人物", "项目", "组织", "其他"])
        XCTAssertTrue(MyWikiEntityFacet.people.matches(entity(tags: ["person"])))
        XCTAssertTrue(MyWikiEntityFacet.people.matches(entity(tags: ["people", "leader"])))
        XCTAssertTrue(MyWikiEntityFacet.projects.matches(entity(tags: ["project"])))
        XCTAssertTrue(MyWikiEntityFacet.projects.matches(entity(tags: ["platform"])))
        XCTAssertTrue(MyWikiEntityFacet.organizations.matches(entity(tags: ["organization"])))
        XCTAssertTrue(MyWikiEntityFacet.organizations.matches(entity(tags: ["company"])))
        XCTAssertTrue(MyWikiEntityFacet.other.matches(entity(tags: ["tool"])))
    }

    func testEntityFacetFilteringOnlyAppliesToEntities() throws {
        let schema = try MyWikiSchemaConfig.defaultPersonalContext()
        let people = entity(id: "adam", title: "Adam", tags: ["person"])
        let project = entity(id: "token-hub", title: "Token Hub", tags: ["project"])
        let concept = MyWikiEntry(
            id: "strategy",
            title: "Strategy",
            category: .concept,
            summary: "Concept summary",
            sourceNames: [],
            tags: ["person"]
        )
        let snapshot = MyWikiDashboardSnapshot(
            schema: schema,
            entriesByCategoryID: [
                MyWikiCategory.entity.id: [people, project],
                MyWikiCategory.concept.id: [concept],
            ]
        )

        let sections = MyWikiIndexSectionsBuilder().categorySections(
            snapshot: snapshot,
            query: "",
            expandedCategoryIDs: [MyWikiCategory.entity.id, MyWikiCategory.concept.id],
            selectedEntityFacetID: MyWikiEntityFacet.people.id,
            previewLimit: 10
        )

        XCTAssertEqual(sections.first { $0.category == .entity }?.presentation.visibleEntries.map(\.title), ["Adam"])
        XCTAssertEqual(sections.first { $0.category == .concept }?.presentation.visibleEntries.map(\.title), ["Strategy"])
    }

    func testIndexNavigationUsesInlineShowMoreInsteadOfFullListNavigation() {
        XCTAssertTrue(MyWikiIndexNavigationPolicy.usesInlineShowMore)
        XCTAssertFalse(MyWikiIndexNavigationPolicy.usesFullListNavigation)
    }

    func testDetailMoreMenuIncludesSourceManagementAction() {
        XCTAssertTrue(MyWikiDetailMoreMenuPolicy.includesSourceLibrary)
    }

    func testSourceLibraryEntryUsesExplicitManageSourcesButton() {
        XCTAssertTrue(MyWikiSourceLibraryEntryPolicy.showsManageSourcesButton)
        XCTAssertFalse(MyWikiSourceLibraryEntryPolicy.progressCardOpensSourceLibrary)
        XCTAssertGreaterThanOrEqual(MyWikiSourceLibraryEntryPolicy.manageButtonMinWidth, 160)
        XCTAssertGreaterThanOrEqual(MyWikiSourceLibraryEntryPolicy.manageButtonMinHeight, 40)
    }

    func testDetailMoreMenuIncludesAgentContextAction() {
        XCTAssertTrue(MyWikiDetailMoreMenuPolicy.includesAgentContext)
    }

    func testProgressRefreshRunsWhilePipelineIsActive() {
        XCTAssertTrue(MyWikiProgressRefreshPolicy.shouldRefresh(isSyncing: true, progressState: nil))
        XCTAssertTrue(MyWikiProgressRefreshPolicy.shouldRefresh(isSyncing: false, progressState: .running))
        XCTAssertFalse(MyWikiProgressRefreshPolicy.shouldRefresh(isSyncing: false, progressState: .succeeded))
    }

    func testDetailMaintenanceCardOnlyAppearsForDuplicateSuggestions() {
        XCTAssertFalse(MyWikiDetailMaintenancePolicy.showsDuplicateSuggestionCard(duplicateSuggestionCount: 0))
        XCTAssertTrue(MyWikiDetailMaintenancePolicy.showsDuplicateSuggestionCard(duplicateSuggestionCount: 2))
    }

    func testDuplicateDiscoveryRunsWhenDashboardLoads() {
        XCTAssertTrue(MyWikiDuplicateDiscoveryPolicy.scansOnDashboardLoad)
    }

    func testRecentExportPresentationLimitsVisibleFilesAndSummarizesHiddenCount() {
        let fileNames = (1...28).map { "knowyou-diary-2026-04-\(String(format: "%02d", $0)).md" }

        let presentation = KnowledgeOntologyRecentExportPresentation(
            exportedFileNames: fileNames,
            maxVisibleCount: 8
        )

        XCTAssertEqual(presentation.visibleFileNames, Array(fileNames.prefix(8)))
        XCTAssertEqual(presentation.hiddenCount, 20)
        XCTAssertEqual(presentation.summaryText, "20 more files were synced. You can review them in My Wiki sources.")
    }

    func testRecentExportSummaryUsesMyWikiLanguage() {
        let names = (1...28).map { "knowyou-diary-2026-05-\(String(format: "%02d", $0)).md" }

        let presentation = KnowledgeOntologyRecentExportPresentation(exportedFileNames: names)

        XCTAssertEqual(presentation.visibleFileNames.count, 8)
        XCTAssertEqual(presentation.hiddenCount, 20)
        XCTAssertEqual(presentation.summaryText, "20 more files were synced. You can review them in My Wiki sources.")
    }

    func testRecentExportPresentationShowsAllFilesWhenWithinLimit() {
        let fileNames = [
            "knowyou-diary-2026-05-07.md",
            "knowyou-diary-2026-05-06.md",
            "knowyou-diary-2026-04-29.md",
        ]

        let presentation = KnowledgeOntologyRecentExportPresentation(
            exportedFileNames: fileNames,
            maxVisibleCount: 8
        )

        XCTAssertEqual(presentation.visibleFileNames, fileNames)
        XCTAssertEqual(presentation.hiddenCount, 0)
        XCTAssertNil(presentation.summaryText)
    }

    private func makeEntries(prefix: String, category: MyWikiCategory, count: Int) -> [MyWikiEntry] {
        (1...count).map { index in
            MyWikiEntry(
                id: "\(category.id)-\(index)",
                title: "\(prefix) \(index)",
                category: category,
                summary: "Summary \(index)",
                sourceNames: []
            )
        }
    }

    private func entity(id: String = "entity", title: String = "Entity", tags: [String]) -> MyWikiEntry {
        MyWikiEntry(
            id: id,
            title: title,
            category: .entity,
            summary: "Summary",
            sourceNames: [],
            tags: tags
        )
    }
}
