import XCTest
@testable import KnowYou

final class KnowledgeOntologyPanelTests: XCTestCase {
    func testMyWikiCategoryLabelsAreNativeLlmWikiCategoriesOnly() {
        XCTAssertEqual(MyWikiCategory.nativeCategories.map(\.id), ["sources", "entities", "concepts"])
        XCTAssertEqual(MyWikiCategory.source.displayTitle, "Sources")
        XCTAssertEqual(MyWikiCategory.entity.displayTitle, "Entities")
        XCTAssertEqual(MyWikiCategory.concept.displayTitle, "Concepts")
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
                id: "entity-\(index)",
                title: "Entity \(index)",
                category: .entity,
                summary: "Summary \(index)",
                sourceNames: []
            )
        }

        let expanded = MyWikiIndexSectionPresentation(
            title: "Entities",
            entries: entries,
            isExpanded: true,
            previewLimit: 3,
            isShowingAll: false
        )
        XCTAssertEqual(expanded.visibleEntries.map(\.title), ["Entity 1", "Entity 2", "Entity 3"])
        XCTAssertTrue(expanded.canShowMore)
        XCTAssertEqual(expanded.hiddenCount, 3)
        XCTAssertEqual(expanded.showMoreTitle, "Show more (3)")

        let showingAll = MyWikiIndexSectionPresentation(
            title: "Entities",
            entries: entries,
            isExpanded: true,
            previewLimit: 3,
            isShowingAll: true
        )
        XCTAssertEqual(showingAll.visibleEntries.map(\.title), entries.map(\.title))
        XCTAssertTrue(showingAll.canShowLess)
        XCTAssertEqual(showingAll.showMoreTitle, "Show less")
    }

    func testDefaultIndexSectionsPrioritizeEntitiesAndConceptsBeforeSources() {
        let sourceEntries = makeEntries(prefix: "Source", category: .source, count: 12)
        let entityEntries = makeEntries(prefix: "Entity", category: .entity, count: 12)
        let conceptEntries = makeEntries(prefix: "Concept", category: .concept, count: 12)
        let snapshot = MyWikiDashboardSnapshot(
            sources: sourceEntries,
            entities: entityEntries,
            concepts: conceptEntries
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
        XCTAssertTrue(KnowYouMainWindowLaunchPolicy.showsAppIconInTitlebar)
        XCTAssertEqual(KnowYouMainWindowLaunchPolicy.titlebarIconSize, 30)
        XCTAssertEqual(KnowYouMainWindowLaunchPolicy.titlebarTitleFontSize, 21)
    }

    func testMainWindowWorkspacePolicyKeepsToolbarStableAcrossSidebarModes() {
        XCTAssertTrue(MainWindowWorkspacePolicy.usesUnifiedNavigationSplitViewAcrossModes)
        XCTAssertTrue(MainWindowWorkspacePolicy.keepsEngineSelectorInGlobalToolbar)
        XCTAssertTrue(MainWindowWorkspacePolicy.showsPrivacyMessageOutsideEngineSelector)
        XCTAssertEqual(MainWindowWorkspacePolicy.privacyMessage, "Your data stays local. No backend server.")
        XCTAssertEqual(MainWindowWorkspacePolicy.privacyMessageFontSize, 14)
    }

    func testDetailPresentationShowsMarkdownPageByDefault() {
        let entry = MyWikiEntry(
            id: "adam-wu",
            title: "Adam Wu",
            category: .entity,
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

    func testDynamicTagFacetsUseCurrentEntriesOnlyAndSortByFrequency() {
        let facets = MyWikiTagFacet.facets(for: [
            entity(id: "token-hub", title: "Token Hub", tags: ["platform", "agent"]),
            entity(id: "ai-force", title: "AI Force", tags: ["platform"]),
            entity(id: "adapter", title: "Adapter", tags: ["agent"]),
            entity(id: "untagged", title: "Untagged", tags: []),
            entity(id: "security", title: "Security", tags: ["risk"]),
        ])

        XCTAssertEqual(facets.map(\.title), ["agent", "platform", "risk"])
        XCTAssertEqual(facets.map(\.count), [2, 2, 1])
    }

    func testDynamicTagFacetsKeepOtherAfterSpecificTagsEvenWhenFrequent() {
        let facets = MyWikiTagFacet.facets(for: [
            entity(id: "one", title: "One", tags: ["other", "platform"]),
            entity(id: "two", title: "Two", tags: ["Other"]),
            entity(id: "three", title: "Three", tags: ["OTHER"]),
            entity(id: "four", title: "Four", tags: ["agent"]),
            entity(id: "five", title: "Five", tags: ["platform"]),
        ])

        XCTAssertEqual(facets.map(\.title), ["platform", "agent", "other"])
        XCTAssertEqual(facets.map(\.count), [2, 1, 3])
    }

    func testTagFacetDisplayDefaultsToSixAndCanExpand() {
        let facets = (1...8).map { index in
            MyWikiTagFacet(tag: "tag-\(index)", title: "tag-\(index)", count: 10 - index)
        }

        XCTAssertEqual(MyWikiTagFacetDisplayPolicy.defaultVisibleLimit, 6)
        XCTAssertEqual(
            MyWikiTagFacetDisplayPolicy.visibleFacets(facets, isExpanded: false).map(\.title),
            ["tag-1", "tag-2", "tag-3", "tag-4", "tag-5", "tag-6"]
        )
        XCTAssertEqual(MyWikiTagFacetDisplayPolicy.hiddenCount(for: facets, isExpanded: false), 2)
        XCTAssertTrue(MyWikiTagFacetDisplayPolicy.canExpand(facets, isExpanded: false))
        XCTAssertEqual(MyWikiTagFacetDisplayPolicy.toggleTitle(for: facets, isExpanded: false), "+2 more")

        XCTAssertEqual(MyWikiTagFacetDisplayPolicy.visibleFacets(facets, isExpanded: true).count, 8)
        XCTAssertTrue(MyWikiTagFacetDisplayPolicy.canCollapse(facets, isExpanded: true))
        XCTAssertEqual(MyWikiTagFacetDisplayPolicy.toggleTitle(for: facets, isExpanded: true), "Show less")
    }

    func testTagFilteringAppliesPerCategory() {
        let platformEntity = entity(id: "token-hub", title: "Token Hub", tags: ["platform"])
        let agentEntity = entity(id: "codex", title: "Codex", tags: ["agent"])
        let concept = MyWikiEntry(
            id: "strategy",
            title: "Strategy",
            category: .concept,
            summary: "Concept summary",
            sourceNames: [],
            tags: ["platform"]
        )
        let snapshot = MyWikiDashboardSnapshot(
            sources: [],
            entities: [platformEntity, agentEntity],
            concepts: [concept]
        )

        let sections = MyWikiIndexSectionsBuilder().categorySections(
            snapshot: snapshot,
            query: "",
            expandedCategoryIDs: [MyWikiCategory.entity.id, MyWikiCategory.concept.id],
            selectedTagByCategoryID: [MyWikiCategory.entity.id: "platform"],
            previewLimit: 10
        )

        XCTAssertEqual(sections.first { $0.category == .entity }?.presentation.visibleEntries.map(\.title), ["Token Hub"])
        XCTAssertEqual(sections.first { $0.category == .concept }?.presentation.visibleEntries.map(\.title), ["Strategy"])
        XCTAssertEqual(sections.first { $0.category == .entity }?.tagFacets.map(\.title), ["agent", "platform"])
        XCTAssertEqual(sections.first { $0.category == .concept }?.tagFacets.map(\.title), ["platform"])
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
        XCTAssertEqual(MyWikiSourceLibraryEntryPolicy.manageButtonTitle, "Set Digest Files")
        XCTAssertLessThanOrEqual(MyWikiSourceLibraryEntryPolicy.manageButtonIconSize, 14)
        XCTAssertGreaterThanOrEqual(MyWikiSourceLibraryEntryPolicy.manageButtonMinWidth, 144)
        XCTAssertGreaterThanOrEqual(MyWikiSourceLibraryEntryPolicy.manageButtonMinHeight, 34)
    }

    func testDigestSchedulePresentationExplainsManualTriggerAndLastRunTime() {
        let progress = MyWikiIngestProgress(
            state: .succeeded,
            message: "My Wiki pipeline completed.",
            updatedAt: "2026-06-01T07:30:00Z",
            sourcesProcessed: 2,
            totalSources: 2
        )

        let presentation = MyWikiDigestSchedulePresentation(
            ingestProgress: progress,
            nextRunDate: DateComponents(calendar: Calendar(identifier: .gregorian), timeZone: TimeZone(secondsFromGMT: 0), year: 2026, month: 6, day: 1, hour: 15, minute: 30).date!,
            displayTimeZone: TimeZone(secondsFromGMT: 0)!
        )

        XCTAssertEqual(presentation.title, "My Wiki digest")
        XCTAssertEqual(presentation.triggerText, "Updates daily after Diary and Todo are ready.")
        XCTAssertEqual(presentation.lastRunTitle, "Last update")
        XCTAssertEqual(presentation.lastRunValue, "7:30 AM")
        XCTAssertEqual(presentation.nextRunTitle, "Next update")
        XCTAssertEqual(presentation.nextRunValue, "3:30 PM")
        XCTAssertEqual(presentation.updateNowTitle, "Update Now")
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
        XCTAssertFalse(
            MyWikiDetailMaintenancePolicy.showsDuplicateSuggestionCard(
                duplicateSuggestionCount: 0,
                isCurrentEntryAffected: true
            )
        )
        XCTAssertFalse(
            MyWikiDetailMaintenancePolicy.showsDuplicateSuggestionCard(
                duplicateSuggestionCount: 2,
                isCurrentEntryAffected: false
            )
        )
        XCTAssertTrue(
            MyWikiDetailMaintenancePolicy.showsDuplicateSuggestionCard(
                duplicateSuggestionCount: 2,
                isCurrentEntryAffected: true
            )
        )
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
