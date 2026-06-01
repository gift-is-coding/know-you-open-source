import XCTest
@testable import KnowYou

final class DailyMarkdownViewTests: XCTestCase {
    func testDateSidebarPresentationGroupsDatesByEnglishMonth() {
        let presentation = DateSidebarPresentation(
            dates: ["2026-04-24", "2026-04-23", "2026-03-31", "demo-day"],
            selectedItemID: nil,
            knowledgeImportConfig: .default,
            today: makeDate(year: 2026, month: 4, day: 24),
            calendar: gregorianCalendar
        )

        XCTAssertEqual(presentation.sections.map(\.title), ["April 2026", "March 2026", nil])
        XCTAssertEqual(presentation.sections[0].items.map(\.id), ["diary:2026-04-24", "diary:2026-04-23"])
        XCTAssertEqual(presentation.sections[1].items.map(\.id), ["diary:2026-03-31"])
        XCTAssertEqual(presentation.sections[2].items.map(\.id), ["diary:demo-day"])
    }

    func testDateSidebarPresentationOpensCurrentMonthAndCollapsesOlderMonths() {
        let presentation = DateSidebarPresentation(
            dates: ["2026-04-24", "2026-03-31"],
            selectedItemID: nil,
            knowledgeImportConfig: .default,
            today: makeDate(year: 2026, month: 4, day: 24),
            calendar: gregorianCalendar
        )

        XCTAssertTrue(presentation.sections[0].isExpandedByDefault)
        XCTAssertFalse(presentation.sections[1].isExpandedByDefault)
    }

    func testDateSidebarPresentationOpensSelectedOlderMonth() {
        let presentation = DateSidebarPresentation(
            dates: ["2026-04-24", "2026-03-31"],
            selectedItemID: "diary:2026-03-31",
            knowledgeImportConfig: .default,
            today: makeDate(year: 2026, month: 4, day: 24),
            calendar: gregorianCalendar
        )

        XCTAssertTrue(presentation.sections[0].isExpandedByDefault)
        XCTAssertTrue(presentation.sections[1].isExpandedByDefault)
    }

    func testSidebarPresentationShowsUnifiedRootItemsBeforeDates() {
        let presentation = DateSidebarPresentation(
            dates: ["2026-05-23", "2026-05-22"],
            selectedItemID: "diary:2026-05-23",
            knowledgeImportConfig: .default,
            today: makeDate(year: 2026, month: 5, day: 23),
            calendar: gregorianCalendar
        )

        XCTAssertEqual(presentation.homeRootItem.id, "home")
        XCTAssertEqual(presentation.homeRootItem.title, "Home")
        XCTAssertEqual(presentation.homeRootItem.selectionAction, .home)
        XCTAssertFalse(presentation.homeRootItem.showsAddButton)
        XCTAssertFalse(presentation.homeRootItem.isExpandable)
        XCTAssertEqual(presentation.myWikiRootItem.id, "my-wiki")
        XCTAssertEqual(presentation.myWikiRootItem.title, "My Wiki")
        XCTAssertFalse(presentation.myWikiRootItem.showsAddButton)
        XCTAssertFalse(presentation.myWikiRootItem.isExpandable)
        XCTAssertEqual(presentation.sourceRootItem.id, "add-source")
        XCTAssertEqual(presentation.sourceRootItem.title, "Other Source")
        XCTAssertFalse(presentation.sourceRootItem.showsAddButton)
        XCTAssertFalse(presentation.sourceRootItem.isExpandable)
        XCTAssertEqual(presentation.networkingRootItem.id, "networking")
        XCTAssertEqual(presentation.networkingRootItem.title, "Networking (Coming soon)")
        XCTAssertFalse(presentation.networkingRootItem.showsAddButton)
        XCTAssertFalse(presentation.networkingRootItem.isExpandable)
        XCTAssertEqual(presentation.diaryRootItem.id, "diary-root")
        XCTAssertEqual(presentation.diaryRootItem.title, "My Diary")
        XCTAssertEqual(Array(presentation.rootItems.prefix(6)).map(\.id), ["home", "networking", "todo-root", "my-wiki", "diary-root", "add-source"])
        XCTAssertEqual(presentation.diarySections.first?.items.map(\.title), ["Today", "Yesterday"])
    }

    func testSidebarPresentationShowsTodoRootAboveSourcesWithOpenCount() {
        let presentation = DateSidebarPresentation(
            dates: ["2026-05-23"],
            selectedItemID: "todo-root",
            todoOpenCount: 2,
            knowledgeImportConfig: .default,
            today: makeDate(year: 2026, month: 5, day: 23),
            calendar: gregorianCalendar
        )

        XCTAssertEqual(presentation.todoRootItem.id, "todo-root")
        XCTAssertEqual(presentation.todoRootItem.title, "Todo")
        XCTAssertEqual(presentation.todoRootItem.badgeCount, 2)
        XCTAssertEqual(presentation.todoRootItem.selectionAction, .todo)
        XCTAssertTrue(presentation.todoRootItem.isSelected)
        XCTAssertEqual(Array(presentation.rootItems.prefix(6)).map(\.id), ["home", "networking", "todo-root", "my-wiki", "diary-root", "add-source"])
    }

    func testSidebarPresentationShowsHomeBeforeNetworking() {
        let presentation = DateSidebarPresentation(
            dates: [],
            selectedItemID: "home",
            knowledgeImportConfig: .default,
            today: makeDate(year: 2026, month: 5, day: 23),
            calendar: gregorianCalendar
        )

        XCTAssertEqual(presentation.homeRootItem.title, "Home")
        XCTAssertEqual(presentation.homeRootItem.selectionAction, .home)
        XCTAssertTrue(presentation.homeRootItem.isSelected)
        XCTAssertEqual(Array(presentation.rootItems.prefix(2)).map(\.id), ["home", "networking"])
    }

    func testSidebarPresentationShowsNetworkingComingSoonRootItem() {
        let presentation = DateSidebarPresentation(
            dates: [],
            selectedItemID: "networking",
            knowledgeImportConfig: .default,
            today: makeDate(year: 2026, month: 5, day: 23),
            calendar: gregorianCalendar
        )

        XCTAssertEqual(presentation.networkingRootItem.id, "networking")
        XCTAssertEqual(presentation.networkingRootItem.title, "Networking (Coming soon)")
        XCTAssertEqual(presentation.networkingRootItem.selectionAction, .networkingComingSoon)
        XCTAssertTrue(presentation.networkingRootItem.isSelected)
        XCTAssertFalse(presentation.homeRootItem.isSelected)
        XCTAssertFalse(presentation.todoRootItem.isSelected)
        XCTAssertFalse(presentation.myWikiRootItem.isSelected)
        XCTAssertFalse(presentation.sourceRootItem.isSelected)
        XCTAssertFalse(presentation.diaryRootItem.isSelected)
    }

    func testJournalListOrderingShowsOnlyTodayAndLastThreeDays() {
        let today = makeDate(year: 2026, month: 5, day: 23)
        let dates = Set([
            "2026-05-23",
            "2026-05-22",
            "2026-05-21",
            "2026-05-20",
            "2026-05-19",
            "2026-05-18",
            "2026-05-17",
        ])

        let orderedDates = JournalListOrdering.orderedDates(
            noteDays: dates,
            includeDemoDay: false,
            today: today,
            calendar: gregorianCalendar
        )

        XCTAssertEqual(orderedDates, ["2026-05-23", "2026-05-22", "2026-05-21", "2026-05-20"])
    }

    func testSidebarPresentationSelectsMyWikiAsPeerRootItem() {
        let presentation = DateSidebarPresentation(
            dates: [],
            selectedItemID: "my-wiki",
            knowledgeImportConfig: .default,
            today: makeDate(year: 2026, month: 5, day: 23),
            calendar: gregorianCalendar
        )

        XCTAssertTrue(presentation.myWikiRootItem.isSelected)
        XCTAssertEqual(presentation.myWikiRootItem.selectionAction, .knowledgeOntology)
        XCTAssertFalse(presentation.todoRootItem.isSelected)
        XCTAssertFalse(presentation.sourceRootItem.isSelected)
        XCTAssertFalse(presentation.diaryRootItem.isSelected)
    }

    func testSidebarPresentationAddsConnectorInstancesAsRootItems() {
        let config = KnowledgeImportConfig(
            isImportEnabled: true,
            dailyImportHour: 7,
            dailyImportMinute: 30,
            connectorInstances: [
                KnowledgeConnectorInstanceConfig(
                    id: "feishu-main",
                    connectorID: .feishuImport,
                    displayName: "飞书文档",
                    sourcePath: "doc-token",
                    isEnabled: true
                ),
                KnowledgeConnectorInstanceConfig(
                    id: "drive-main",
                    connectorID: .googleDriveImport,
                    displayName: "Google Drive",
                    accountID: "me@example.com",
                    isEnabled: false
                ),
            ]
        )

        let presentation = DateSidebarPresentation(
            dates: [],
            selectedItemID: "connector:feishu-main",
            knowledgeImportConfig: config,
            knowledgeDocumentsByConnector: [
                "feishu-main": [
                    makeKnowledgeDocument(
                        id: "feishu-doc",
                        connectorInstanceID: "feishu-main",
                        title: "Feishu Doc",
                        sourcePath: "doc-token/doc.md"
                    ),
                ],
                "drive-main": [
                    makeKnowledgeDocument(
                        id: "drive-doc",
                        connectorInstanceID: "drive-main",
                        title: "Drive Doc",
                        sourcePath: "drive.md"
                    ),
                ],
            ],
            today: makeDate(year: 2026, month: 5, day: 23),
            calendar: gregorianCalendar
        )

        XCTAssertEqual(
            presentation.sourceItems.map(\.id),
            ["connector:feishu-main", "connector:drive-main"]
        )
        XCTAssertEqual(presentation.sourceItems.map(\.title), ["飞书文档", "Google Drive"])
        XCTAssertEqual(presentation.sourceItems.map(\.systemImage), ["doc.richtext", "externaldrive"])
        XCTAssertEqual(presentation.sourceItems.map(\.brandAssetName), ["SourceLogoFeishu", "SourceLogoGoogleDrive"])
        XCTAssertTrue(presentation.sourceItems[0].isEnabled)
        XCTAssertFalse(presentation.sourceItems[1].isEnabled)
        XCTAssertTrue(presentation.sourceItems.allSatisfy(\.isExpandable))
    }

    func testSidebarPresentationBuildsConnectorDocumentTreeFromImportedDocumentPaths() throws {
        let root = "/Users/me/Library/Application Support/KnowYou/ExternalSources/feishu"
        let config = KnowledgeImportConfig(
            connectorInstances: [
                KnowledgeConnectorInstanceConfig(
                    id: "feishu-main",
                    connectorID: .feishuImport,
                    displayName: "Feishu Docs",
                    sourcePath: root,
                    isEnabled: true
                )
            ]
        )
        let documents = [
            makeKnowledgeDocument(
                id: "doc-alpha",
                connectorInstanceID: "feishu-main",
                title: "Alpha",
                sourcePath: "\(root)/Projects/Alpha.md"
            ),
            makeKnowledgeDocument(
                id: "doc-beta",
                connectorInstanceID: "feishu-main",
                title: "Beta",
                sourcePath: "\(root)/Projects/Nested/Beta.md"
            ),
        ]

        let presentation = DateSidebarPresentation(
            dates: [],
            selectedItemID: "document:feishu-main:doc-beta",
            knowledgeImportConfig: config,
            knowledgeDocumentsByConnector: ["feishu-main": documents],
            today: makeDate(year: 2026, month: 5, day: 23),
            calendar: gregorianCalendar
        )

        let connector = try XCTUnwrap(presentation.sourceItems.first)
        XCTAssertEqual(connector.children.map(\.title), ["Projects"])
        let projects = try XCTUnwrap(connector.children.first)
        XCTAssertEqual(projects.children.map(\.title), ["Alpha", "Nested"])
        let nested = try XCTUnwrap(projects.children.first { $0.title == "Nested" })
        XCTAssertEqual(nested.children.map(\.id), ["document:feishu-main:doc-beta"])
        XCTAssertEqual(nested.children.first?.selectionAction, .knowledgeDocument("feishu-main", "doc-beta"))
    }

    func testSidebarPresentationDoesNotShowDuplicateConnectorRootFolder() throws {
        let root = "/Users/me/Documents/obsidian-folder"
        let config = KnowledgeImportConfig(
            connectorInstances: [
                KnowledgeConnectorInstanceConfig(
                    id: "obsidian-main",
                    connectorID: .obsidianImport,
                    displayName: "Obsidian Vault",
                    sourcePath: root,
                    isEnabled: true
                )
            ]
        )
        let document = makeKnowledgeDocument(
            id: "obsidian-doc",
            connectorInstanceID: "obsidian-main",
            title: "Daily Note",
            sourcePath: "\(root)/obsidian-folder/Daily Note.md"
        )

        let presentation = DateSidebarPresentation(
            dates: [],
            selectedItemID: nil,
            knowledgeImportConfig: config,
            knowledgeDocumentsByConnector: ["obsidian-main": [document]],
            today: makeDate(year: 2026, month: 5, day: 23),
            calendar: gregorianCalendar
        )

        let connector = try XCTUnwrap(presentation.sourceItems.first)
        XCTAssertEqual(connector.brandAssetName, "SourceLogoObsidian")
        XCTAssertEqual(connector.children.map(\.title), ["Daily Note"])
        XCTAssertEqual(connector.children.first?.id, "document:obsidian-main:obsidian-doc")
    }

    @MainActor
    func testSidebarDoubleClickTogglesExpandableConnectorAndFolderRowsOnly() throws {
        let root = "/Users/me/Library/Application Support/KnowYou/ExternalSources/feishu"
        let config = KnowledgeImportConfig(
            connectorInstances: [
                KnowledgeConnectorInstanceConfig(
                    id: "feishu-main",
                    connectorID: .feishuImport,
                    displayName: "Feishu Docs",
                    sourcePath: root,
                    isEnabled: true
                )
            ]
        )
        let document = makeKnowledgeDocument(
            id: "feishu-doc",
            connectorInstanceID: "feishu-main",
            title: "Alpha",
            sourcePath: "\(root)/Projects/Alpha.md"
        )

        let presentation = DateSidebarPresentation(
            dates: [],
            selectedItemID: nil,
            knowledgeImportConfig: config,
            knowledgeDocumentsByConnector: ["feishu-main": [document]],
            today: makeDate(year: 2026, month: 5, day: 23),
            calendar: gregorianCalendar
        )

        let connector = try XCTUnwrap(presentation.sourceItems.first)
        let folder = try XCTUnwrap(connector.children.first)
        let leaf = try XCTUnwrap(folder.children.first)

        XCTAssertEqual(DateSidebarView.doubleClickExpansionID(for: connector), "connector:feishu-main")
        XCTAssertEqual(DateSidebarView.doubleClickExpansionID(for: folder), folder.id)
        XCTAssertNil(DateSidebarView.doubleClickExpansionID(for: leaf))
    }

    @MainActor
    func testSidebarDoubleClickTreatsDiaryRootAsExpandableDisclosure() {
        let presentation = DateSidebarPresentation(
            dates: ["2026-05-23"],
            selectedItemID: nil,
            knowledgeImportConfig: .default,
            today: makeDate(year: 2026, month: 5, day: 23),
            calendar: gregorianCalendar
        )

        XCTAssertEqual(DateSidebarView.doubleClickExpansionID(for: presentation.diaryRootItem), "diary-root")
    }

    @MainActor
    func testSidebarRowsExposeSelectionIDsForBlueClickFeedback() throws {
        let root = "/Users/me/Library/Application Support/KnowYou/ExternalSources/feishu"
        let config = KnowledgeImportConfig(
            connectorInstances: [
                KnowledgeConnectorInstanceConfig(
                    id: "feishu-main",
                    connectorID: .feishuImport,
                    displayName: "Feishu Docs",
                    sourcePath: root,
                    isEnabled: true
                )
            ]
        )
        let document = makeKnowledgeDocument(
            id: "feishu-doc",
            connectorInstanceID: "feishu-main",
            title: "Alpha",
            sourcePath: "\(root)/Projects/Alpha.md"
        )

        let presentation = DateSidebarPresentation(
            dates: [],
            selectedItemID: nil,
            knowledgeImportConfig: config,
            knowledgeDocumentsByConnector: ["feishu-main": [document]],
            today: makeDate(year: 2026, month: 5, day: 23),
            calendar: gregorianCalendar
        )

        let connector = try XCTUnwrap(presentation.sourceItems.first)
        let folder = try XCTUnwrap(connector.children.first)
        let leaf = try XCTUnwrap(folder.children.first)

        XCTAssertEqual(DateSidebarView.sidebarSelectionID(for: connector), "connector:feishu-main")
        XCTAssertEqual(DateSidebarView.sidebarSelectionID(for: folder), folder.id)
        XCTAssertEqual(DateSidebarView.sidebarSelectionID(for: leaf), "document:feishu-main:feishu-doc")
    }

    @MainActor
    func testSidebarBrandLogoMetricsKeepFeishuFromRenderingLargerThanObsidian() {
        let feishu = DateSidebarView.sidebarIconMetrics(forBrandAssetName: "SourceLogoFeishu")
        let obsidian = DateSidebarView.sidebarIconMetrics(forBrandAssetName: "SourceLogoObsidian")

        XCTAssertEqual(feishu.frameSize, obsidian.frameSize)
        XCTAssertLessThan(feishu.contentSize, obsidian.contentSize)
    }

    func testSidebarPresentationMarksAddSourceAction() throws {
        let presentation = DateSidebarPresentation(
            dates: [],
            selectedItemID: "add-source",
            knowledgeImportConfig: .default,
            today: makeDate(year: 2026, month: 5, day: 23),
            calendar: gregorianCalendar
        )

        XCTAssertFalse(presentation.sourceRootItem.showsAddButton)
        XCTAssertTrue(presentation.sourceRootItem.isSelected)
    }

    @MainActor
    func testDateSidebarViewOnlyTreatsDiarySelectionIDsAsDayKeys() {
        XCTAssertEqual(DateSidebarView.dayKeyForSelection("diary:2026-05-23"), "2026-05-23")
        XCTAssertNil(DateSidebarView.dayKeyForSelection("my-wiki"))
        XCTAssertNil(DateSidebarView.dayKeyForSelection("add-source"))
        XCTAssertNil(DateSidebarView.dayKeyForSelection("connector:drive-main"))
    }

    @MainActor
    func testDateSidebarSelectionActionRoutesRootAndConnectorIDs() {
        XCTAssertEqual(DateSidebarView.selectionAction(for: "home"), .home)
        XCTAssertEqual(DateSidebarView.selectionAction(for: "todo-root"), .todo)
        XCTAssertEqual(DateSidebarView.selectionAction(for: "diary:2026-05-23"), .diaryDate("2026-05-23"))
        XCTAssertEqual(DateSidebarView.selectionAction(for: "my-wiki"), .knowledgeOntology)
        XCTAssertEqual(DateSidebarView.selectionAction(for: "add-source"), .otherSource(focusAddConnector: false))
        XCTAssertEqual(DateSidebarView.selectionAction(for: "networking"), .networkingComingSoon)
        XCTAssertNil(DateSidebarView.selectionAction(for: "connector:feishu-main"))
        XCTAssertEqual(
            DateSidebarView.selectionAction(for: "document:feishu-main:doc-alpha"),
            .knowledgeDocument("feishu-main", "doc-alpha")
        )
        XCTAssertNil(DateSidebarView.selectionAction(for: "diary-root"))
        XCTAssertNil(DateSidebarView.selectionAction(for: "settings"))
    }

    func testHomeDashboardPresentationKeepsCopyShortVisualAndActionable() {
        let presentation = HomeDashboardPresentation(
            nextDiaryCheckDate: makeDate(year: 2026, month: 5, day: 23, hour: 15, minute: 0),
            now: makeDate(year: 2026, month: 5, day: 23, hour: 14, minute: 12),
            missingRecentDayCount: 2,
            jobSnapshots: [
                AutomationJobSnapshot(
                    kind: .diary,
                    status: .running,
                    detail: "Refreshing today",
                    progress: 0.4,
                    lastRunAt: nil,
                    nextRunAt: makeDate(year: 2026, month: 5, day: 23, hour: 15, minute: 0)
                ),
                AutomationJobSnapshot(
                    kind: .todo,
                    status: .scheduled,
                    detail: "After Diary is ready",
                    progress: nil,
                    lastRunAt: nil,
                    nextRunAt: makeDate(year: 2026, month: 5, day: 23, hour: 15, minute: 10)
                ),
                AutomationJobSnapshot(
                    kind: .wiki,
                    status: .completed,
                    detail: "Updated 2 sources",
                    progress: 1,
                    lastRunAt: makeDate(year: 2026, month: 5, day: 23, hour: 12, minute: 30),
                    nextRunAt: makeDate(year: 2026, month: 5, day: 24, hour: 15, minute: 30)
                ),
            ],
            displayTimeZone: TimeZone(secondsFromGMT: 0)!
        )

        XCTAssertEqual(presentation.heroTitle, "KnowYou works quietly in the background.")
        XCTAssertEqual(presentation.nextCheckTitle, "Automatic Diary update")
        XCTAssertEqual(presentation.nextCheckValue, "3:00 PM")
        XCTAssertEqual(presentation.generateTodayActionTitle, "Generate Now")
        XCTAssertEqual(presentation.primaryActionTitle, "Generate Last 3 Days")
        XCTAssertTrue(presentation.showsRecentHistoryAction)
        XCTAssertEqual(presentation.visualAssetName, "HomeDashboardHero")
        XCTAssertEqual(presentation.featureCards.map(\.title), ["Networking (Coming soon)", "Todo", "My Wiki", "Today’s Diary", "Other Source"])
        XCTAssertEqual(presentation.featureCards.map(\.id), ["networking", "todo", "wiki", "today", "sources"])
        XCTAssertTrue(presentation.featureCards.allSatisfy { $0.subtitle.count > 42 })
        XCTAssertEqual(presentation.activeJobsTitle, "Updating")
        XCTAssertEqual(presentation.jobRows.map(\.title), ["Diary"])
        XCTAssertEqual(presentation.jobRows.map(\.statusText), ["Running"])
        XCTAssertEqual(presentation.jobRows[0].nextRunText, "Next 3:00 PM")
    }

    func testHomeDashboardHidesIdleJobsAndShowsAttentionJobsOnly() {
        let presentation = HomeDashboardPresentation(
            nextDiaryCheckDate: makeDate(year: 2026, month: 5, day: 23, hour: 15, minute: 0),
            now: makeDate(year: 2026, month: 5, day: 23, hour: 14, minute: 12),
            missingRecentDayCount: 0,
            jobSnapshots: [
                AutomationJobSnapshot(
                    kind: .diary,
                    status: .scheduled,
                    detail: "Every 3 hours",
                    progress: 0,
                    lastRunAt: nil,
                    nextRunAt: makeDate(year: 2026, month: 5, day: 23, hour: 15, minute: 0)
                ),
                AutomationJobSnapshot(
                    kind: .todo,
                    status: .completed,
                    detail: "Todo is up to date.",
                    progress: 1,
                    lastRunAt: makeDate(year: 2026, month: 5, day: 23, hour: 12, minute: 10),
                    nextRunAt: makeDate(year: 2026, month: 5, day: 23, hour: 15, minute: 10)
                ),
                AutomationJobSnapshot(
                    kind: .wiki,
                    status: .degraded,
                    detail: "My Wiki needs attention.",
                    progress: 1,
                    lastRunAt: makeDate(year: 2026, month: 5, day: 23, hour: 12, minute: 30),
                    nextRunAt: makeDate(year: 2026, month: 5, day: 24, hour: 15, minute: 30)
                ),
            ],
            displayTimeZone: TimeZone(secondsFromGMT: 0)!
        )

        XCTAssertEqual(presentation.jobRows.map(\.title), ["My Wiki"])
        XCTAssertEqual(presentation.jobRows.map(\.statusText), ["Needs attention"])
        XCTAssertEqual(presentation.jobRows[0].lastRunText, "Last 12:30 PM")
    }

    func testHomeDashboardHidesLastThreeDaysActionWhenRecentHistoryIsComplete() {
        let presentation = HomeDashboardPresentation(
            nextDiaryCheckDate: makeDate(year: 2026, month: 5, day: 23, hour: 15, minute: 0),
            now: makeDate(year: 2026, month: 5, day: 23, hour: 14, minute: 12),
            missingRecentDayCount: 0,
            displayTimeZone: TimeZone(secondsFromGMT: 0)!
        )

        XCTAssertFalse(presentation.showsRecentHistoryAction)
    }

    func testTodoAutomationPresentationShowsNextUpdateAndManualAction() {
        let presentation = TodoAutomationPresentation(
            nextUpdateDate: makeDate(year: 2026, month: 5, day: 23, hour: 15, minute: 10),
            lastUpdateDate: makeDate(year: 2026, month: 5, day: 23, hour: 12, minute: 10),
            statusMessage: "Todo automation degraded: no available LLM result; manual add still works.",
            displayTimeZone: TimeZone(secondsFromGMT: 0)!
        )

        XCTAssertEqual(presentation.title, "Todo automation")
        XCTAssertEqual(presentation.nextUpdateTitle, "Next update")
        XCTAssertEqual(presentation.nextUpdateValue, "3:10 PM")
        XCTAssertEqual(presentation.lastUpdateTitle, "Last update")
        XCTAssertEqual(presentation.lastUpdateValue, "12:10 PM")
        XCTAssertEqual(presentation.updateNowTitle, "Update Now")
        XCTAssertFalse(presentation.isUpdateNowDisabled)
        XCTAssertEqual(presentation.statusMessage, "Todo automation degraded: no available LLM result; manual add still works.")
    }

    func testTodoAutomationPresentationShowsUpdatingState() {
        let presentation = TodoAutomationPresentation(
            nextUpdateDate: makeDate(year: 2026, month: 5, day: 23, hour: 15, minute: 10),
            lastUpdateDate: nil,
            statusMessage: nil,
            isUpdating: true,
            displayTimeZone: TimeZone(secondsFromGMT: 0)!
        )

        XCTAssertEqual(presentation.updateNowTitle, "Updating...")
        XCTAssertTrue(presentation.isUpdateNowDisabled)
        XCTAssertEqual(presentation.statusMessage, "Updating Todo...")
    }

    func testNetworkingPreviewPresentationExplainsProfilesAndIdentityWithImageAssets() {
        let presentation = NetworkingPreviewPresentation()

        XCTAssertEqual(presentation.title, "Networking (Coming soon)")
        XCTAssertEqual(presentation.status, "Coming soon")
        XCTAssertEqual(presentation.visualAssetName, "NetworkingPreviewHero")
        XCTAssertTrue(presentation.statements.contains("Create profiles for different contexts."))
        XCTAssertTrue(presentation.statements.contains("Use them for jobs, networking, and social discovery."))
        XCTAssertFalse(presentation.statements.joined(separator: "\n").localizedCaseInsensitiveContains("clear identity"))
        XCTAssertFalse(presentation.statements.joined(separator: "\n").localizedCaseInsensitiveContains("identity stays clear"))
    }

    func testTodoInboxCopyContainsNoChineseUserFacingLabels() {
        let visibleCopy = TodoInboxCopy.visibleStrings.joined(separator: "\n")

        XCTAssertFalse(visibleCopy.contains("输入"))
        XCTAssertFalse(visibleCopy.contains("待选"))
        XCTAssertFalse(visibleCopy.contains("推荐关闭"))
        XCTAssertTrue(visibleCopy.contains("Add a task to keep tracking across days"))
        XCTAssertTrue(visibleCopy.contains("Candidates"))
        XCTAssertTrue(visibleCopy.contains("Ready to close"))
    }

    @MainActor
    func testDateSidebarViewAcceptsKnowledgeImportConfig() {
        let config = KnowledgeImportConfig(
            connectorInstances: [
                KnowledgeConnectorInstanceConfig(
                    id: "drive-main",
                    connectorID: .googleDriveImport,
                    displayName: "Google Drive",
                    isEnabled: true
                ),
            ]
        )

        let view = DateSidebarView(
            dates: [],
            selectedDate: nil,
            selectedItemID: nil,
            knowledgeImportConfig: config,
            knowledgeDocumentsByConnector: [:],
            isActive: true,
            isKnowledgeOntologySelected: false,
            todoOpenCount: 0,
            onOpenHome: {},
            onSelectDiaryDate: { _ in },
            onOpenTodo: {},
            onSelectOtherSource: { _ in },
            onSelectKnowledgeConnector: { _ in },
            onSelectKnowledgeDocument: { _, _ in },
            onOpenKnowledgeOntology: {},
            onOpenNetworkingComingSoon: {},
            onOpenSyncMemory: {}
        )

        XCTAssertEqual(view.knowledgeImportConfig.connectorInstances.map(\KnowledgeConnectorInstanceConfig.id), ["drive-main"])
    }

    private func makeKnowledgeDocument(
        id: String,
        connectorInstanceID: String,
        title: String,
        sourcePath: String
    ) -> ImportedKnowledgeDocument {
        ImportedKnowledgeDocument(
            id: id,
            connectorInstanceID: connectorInstanceID,
            connectorID: .feishuImport,
            remoteID: String(sourcePath.split(separator: "/").suffix(2).joined(separator: "/")),
            title: title,
            sourcePath: sourcePath,
            remoteURL: nil,
            mimeType: "text/markdown",
            contentHash: "hash-\(id)",
            remoteUpdatedAt: nil,
            firstImportedAt: Date(timeIntervalSince1970: 1_778_000_000),
            lastSyncedAt: Date(timeIntervalSince1970: 1_778_000_100),
            deletedAt: nil,
            localContentPath: "/tmp/\(id).md",
            localMetadataPath: "/tmp/\(id).json",
            normalizationVersion: 1,
            originKind: "feishu-local-file"
        )
    }

    func testRefreshProgressPresentationMarksCompletedAndCurrentSteps() {
        let job = DayRefreshJob(
            dayKey: "2026-04-09",
            stage: .generatingStory,
            detail: "Calling Codex (CLI)...",
            error: nil,
            completedStages: [.syncingNotifications, .loadingEvents, .preparingStory],
            summary: nil
        )

        let presentation = DayRefreshProgressPresentation(refreshJob: job)

        XCTAssertTrue(presentation.showsSteps)
        XCTAssertEqual(
            presentation.steps.map(\.state),
            [.completed, .completed, .completed, .current, .pending]
        )
        XCTAssertEqual(presentation.currentDetail, "Calling Codex (CLI)...")
        XCTAssertNil(presentation.summaryText)
    }

    func testRefreshProgressPresentationCollapsesToTerminalSummary() {
        let job = DayRefreshJob(
            dayKey: "2026-04-09",
            stage: .completed,
            detail: nil,
            error: nil,
            completedStages: [.syncingNotifications, .loadingEvents, .preparingStory, .generatingStory, .writingFiles],
            summary: "Completed · Codex (CLI) returned successfully"
        )

        let presentation = DayRefreshProgressPresentation(refreshJob: job)

        XCTAssertFalse(presentation.showsSteps)
        XCTAssertEqual(presentation.summaryText, "Completed · Codex (CLI) returned successfully")
        XCTAssertNil(presentation.currentDetail)
    }

    func testSourceBrandResolvesKnownSemanticIdentity() {
        let brand = SourceBrandResolver.resolve(appName: "ChatGPT")

        XCTAssertEqual(brand.identity, .chatGPT)
        XCTAssertEqual(brand.glyph, .asset("SourceLogoChatGPT"))
    }

    func testSourceBrandResolvesKnownBrandAsset() {
        let brand = SourceBrandResolver.resolve(appName: "ChatGPT")

        XCTAssertEqual(brand.assetName, "SourceLogoChatGPT")
    }

    func testSourceBrandNormalizesOpenAIChatGPTAlias() {
        let brand = SourceBrandResolver.resolve(appName: "OpenAI ChatGPT")

        XCTAssertEqual(brand.assetName, "SourceLogoChatGPT")
        XCTAssertEqual(brand.fallbackSymbolName, "app.fill")
    }

    func testSourceBrandFallsBackForUnknownApp() {
        let brand = SourceBrandResolver.resolve(appName: "Completely Unknown App")

        XCTAssertNil(brand.assetName)
        XCTAssertEqual(brand.fallbackSymbolName, "app.fill")
    }

    func testSourceBrandResolvesAppleAppsToDedicatedAssets() {
        XCTAssertEqual(SourceBrandResolver.resolve(appName: "Notes").assetName, "SourceLogoNotes")
        XCTAssertEqual(SourceBrandResolver.resolve(appName: "Mail").assetName, "SourceLogoMail")
        XCTAssertEqual(SourceBrandResolver.resolve(appName: "Calendar").assetName, "SourceLogoCalendar")
    }

    func testSourceBrandResolvesLocalizedAndToolAliasesToDedicatedAssets() {
        XCTAssertEqual(SourceBrandResolver.resolve(appName: "微信").assetName, "SourceLogoWeChat")
        XCTAssertEqual(SourceBrandResolver.resolve(appName: "飞书").assetName, "SourceLogoFeishu")
        XCTAssertEqual(SourceBrandResolver.resolve(appName: "com.microsoft.teams2").assetName, "SourceLogoTeams")
        XCTAssertEqual(SourceBrandResolver.resolve(appName: "Taio").assetName, "SourceLogoTaio")
        XCTAssertEqual(SourceBrandResolver.resolve(appName: "Ghostty").assetName, "SourceLogoGhostty")
    }

    func testSourceBrandResolvesBundleStyleAliasesToDedicatedAssets() {
        XCTAssertEqual(SourceBrandResolver.resolve(appName: "com.tencent.xinWeChat").assetName, "SourceLogoWeChat")
        XCTAssertEqual(SourceBrandResolver.resolve(appName: "com.apple.Notes").assetName, "SourceLogoNotes")
        XCTAssertEqual(SourceBrandResolver.resolve(appName: "com.apple.mail").assetName, "SourceLogoMail")
        XCTAssertEqual(SourceBrandResolver.resolve(appName: "com.apple.MobileSMS").assetName, "SourceLogoMessages")
    }

    func testSourceBrandResolvesChromeAndFinderAssets() {
        XCTAssertEqual(SourceBrandResolver.resolve(appName: "Google Chrome").assetName, "SourceLogoChrome")
        XCTAssertEqual(SourceBrandResolver.resolve(appName: "Chrome").assetName, "SourceLogoChrome")
        XCTAssertEqual(SourceBrandResolver.resolve(appName: "com.google.Chrome").assetName, "SourceLogoChrome")
        XCTAssertEqual(SourceBrandResolver.resolve(appName: "Safari").assetName, "SourceLogoSafari")
        XCTAssertEqual(SourceBrandResolver.resolve(appName: "Finder").assetName, "SourceLogoFinder")
    }

    func testSourceBrandResolvesOfficeAndProgrammingAssets() {
        XCTAssertEqual(SourceBrandResolver.resolve(appName: "Microsoft Word").assetName, "SourceLogoWord")
        XCTAssertEqual(SourceBrandResolver.resolve(appName: "Excel").assetName, "SourceLogoExcel")
        XCTAssertEqual(SourceBrandResolver.resolve(appName: "com.microsoft.Excel").assetName, "SourceLogoExcel")
        XCTAssertEqual(SourceBrandResolver.resolve(appName: "PowerPoint").assetName, "SourceLogoPowerPoint")
        XCTAssertEqual(SourceBrandResolver.resolve(appName: "Outlook").assetName, "SourceLogoOutlook")
        XCTAssertEqual(SourceBrandResolver.resolve(appName: "Visual Studio Code").assetName, "SourceLogoVSCode")
        XCTAssertEqual(SourceBrandResolver.resolve(appName: "iTerm2").assetName, "SourceLogoITerm")
        XCTAssertEqual(SourceBrandResolver.resolve(appName: "Xcode").assetName, "SourceLogoXcode")
        XCTAssertEqual(SourceBrandResolver.resolve(appName: "Docker Desktop").assetName, "SourceLogoDocker")
    }

    func testSourceBrandResolvesAntigravityAssets() {
        XCTAssertEqual(SourceBrandResolver.resolve(appName: "Antigravity").assetName, "SourceLogoAntigravity")
        XCTAssertEqual(SourceBrandResolver.resolve(appName: "com.google.antigravity").assetName, "SourceLogoAntigravity")
    }

    func testSourceBrandResolvesGlobalNotificationAppAssets() {
        XCTAssertEqual(SourceBrandResolver.resolve(appName: "OneDrive").assetName, "SourceLogoOneDrive")
        XCTAssertEqual(SourceBrandResolver.resolve(appName: "zoom.us").assetName, "SourceLogoZoom")
        XCTAssertEqual(SourceBrandResolver.resolve(appName: "OBS Studio").assetName, "SourceLogoOBS")
        XCTAssertEqual(SourceBrandResolver.resolve(appName: "DB Browser for SQLite").assetName, "SourceLogoDBBrowser")
        XCTAssertEqual(SourceBrandResolver.resolve(appName: "Cisco Secure Client").assetName, "SourceLogoCisco")
        XCTAssertEqual(SourceBrandResolver.resolve(appName: "Figma").assetName, "SourceLogoFigma")
    }

    func testSourceBrandResolvesExpandedTopGlobalAppAssets() {
        XCTAssertEqual(SourceBrandResolver.resolve(appName: "Arc").assetName, "SourceLogoArc")
        XCTAssertEqual(SourceBrandResolver.resolve(appName: "Mozilla Firefox").assetName, "SourceLogoFirefox")
        XCTAssertEqual(SourceBrandResolver.resolve(appName: "Brave Browser").assetName, "SourceLogoBrave")
        XCTAssertEqual(SourceBrandResolver.resolve(appName: "Discord").assetName, "SourceLogoDiscord")
        XCTAssertEqual(SourceBrandResolver.resolve(appName: "Linear").assetName, "SourceLogoLinear")
        XCTAssertEqual(SourceBrandResolver.resolve(appName: "Jira").assetName, "SourceLogoJira")
        XCTAssertEqual(SourceBrandResolver.resolve(appName: "Confluence").assetName, "SourceLogoConfluence")
        XCTAssertEqual(SourceBrandResolver.resolve(appName: "Google Meet").assetName, "SourceLogoGoogleMeet")
        XCTAssertEqual(SourceBrandResolver.resolve(appName: "Signal").assetName, "SourceLogoSignal")
        XCTAssertEqual(SourceBrandResolver.resolve(appName: "Sketch").assetName, "SourceLogoSketch")
        XCTAssertEqual(SourceBrandResolver.resolve(appName: "Framer").assetName, "SourceLogoFramer")
        XCTAssertEqual(SourceBrandResolver.resolve(appName: "Reddit").assetName, "SourceLogoReddit")
        XCTAssertEqual(SourceBrandResolver.resolve(appName: "YouTube").assetName, "SourceLogoYouTube")
        XCTAssertEqual(SourceBrandResolver.resolve(appName: "Instagram").assetName, "SourceLogoInstagram")
        XCTAssertEqual(SourceBrandResolver.resolve(appName: "TikTok").assetName, "SourceLogoTikTok")
        XCTAssertEqual(SourceBrandResolver.resolve(appName: "Gemini").assetName, "SourceLogoGemini")
        XCTAssertEqual(SourceBrandResolver.resolve(appName: "GitHub Copilot").assetName, "SourceLogoCopilot")
        XCTAssertEqual(SourceBrandResolver.resolve(appName: "Poe").assetName, "SourceLogoPoe")
        XCTAssertEqual(SourceBrandResolver.resolve(appName: "Postman").assetName, "SourceLogoPostman")
        XCTAssertEqual(SourceBrandResolver.resolve(appName: "Warp").assetName, "SourceLogoWarp")
        XCTAssertEqual(SourceBrandResolver.resolve(appName: "Raycast").assetName, "SourceLogoRaycast")
        XCTAssertEqual(SourceBrandResolver.resolve(appName: "Dropbox").assetName, "SourceLogoDropbox")
        XCTAssertEqual(SourceBrandResolver.resolve(appName: "Google Drive").assetName, "SourceLogoGoogleDrive")
    }

    func testSourceBrandResolvesMacOSSystemAppAssets() {
        XCTAssertEqual(SourceBrandResolver.resolve(appName: "Messages").assetName, "SourceLogoMessages")
        XCTAssertEqual(SourceBrandResolver.resolve(appName: "Preview").assetName, "SourceLogoPreview")
        XCTAssertEqual(SourceBrandResolver.resolve(appName: "System Settings").assetName, "SourceLogoSystemSettings")
        XCTAssertEqual(SourceBrandResolver.resolve(appName: "Activity Monitor").assetName, "SourceLogoActivityMonitor")
        XCTAssertEqual(SourceBrandResolver.resolve(appName: "Reminders").assetName, "SourceLogoReminders")
        XCTAssertEqual(SourceBrandResolver.resolve(appName: "Contacts").assetName, "SourceLogoContacts")
        XCTAssertEqual(SourceBrandResolver.resolve(appName: "QuickTime Player").assetName, "SourceLogoQuickTime")
        XCTAssertEqual(SourceBrandResolver.resolve(appName: "App Store").assetName, "SourceLogoAppStore")
    }

    func testPresentationShowsEmptyStateWhenStoryIsMissing() {
        let presentation = DailyMarkdownPresentation(story: nil)

        XCTAssertTrue(presentation.showsEmptyState)
    }

    func testPresentationShowsEmptyStateWhenStoryHasNoParagraphs() {
        let story = DailyStory(
            dayKey: "2026-04-08",
            generatedAt: Date(timeIntervalSince1970: 0),
            sections: [
                DailyStorySection(id: "summary", title: "Summary", paragraphs: [])
            ]
        )
        let presentation = DailyMarkdownPresentation(story: story)

        XCTAssertTrue(presentation.showsEmptyState)
    }

    func testPresentationUsesChineseStoryHeadingForChineseParagraphs() {
        let paragraph = DailyStoryParagraph(
            id: "daily-journal-0",
            text: "今天主要在处理发货和确认时间。",
            sourceEventIDs: [UUID()]
        )
        let story = DailyStory(
            dayKey: "2026-04-08",
            generatedAt: Date(timeIntervalSince1970: 0),
            sections: [
                DailyStorySection(id: "daily-journal", title: "", paragraphs: [paragraph])
            ]
        )

        let presentation = DailyMarkdownPresentation(story: story)

        XCTAssertEqual(presentation.storyHeading, "今日小记")
        XCTAssertFalse(presentation.showsEmptyState)
    }

    func testPresentationUsesEnglishStoryHeadingForEnglishParagraphs() {
        let first = DailyStoryParagraph(
            id: "daily-journal-0",
            text: "First paragraph",
            sourceEventIDs: [UUID()]
        )
        let second = DailyStoryParagraph(
            id: "daily-journal-1",
            text: "Second paragraph",
            sourceEventIDs: [UUID()]
        )
        let story = DailyStory(
            dayKey: "2026-04-08",
            generatedAt: Date(timeIntervalSince1970: 0),
            sections: [
                DailyStorySection(id: "summary", title: "Summary", paragraphs: [first, second])
            ]
        )
        let presentation = DailyMarkdownPresentation(story: story)

        XCTAssertEqual(presentation.storyHeading, "Story")
        XCTAssertEqual(presentation.paragraphs, [first, second])
    }

    func testPresentationUsesSelectedParagraphAsScrollTarget() {
        let first = DailyStoryParagraph(
            id: "daily-journal-0",
            text: "First paragraph",
            sourceEventIDs: [UUID()]
        )
        let second = DailyStoryParagraph(
            id: "daily-journal-1",
            text: "Second paragraph",
            sourceEventIDs: [UUID()]
        )
        let story = DailyStory(
            dayKey: "2026-04-08",
            generatedAt: Date(timeIntervalSince1970: 0),
            sections: [
                DailyStorySection(id: "summary", title: "Summary", paragraphs: [first, second])
            ]
        )

        let presentation = DailyMarkdownPresentation(
            story: story,
            selectedParagraphID: "daily-journal-1"
        )

        XCTAssertEqual(presentation.scrollTargetParagraphID, "daily-journal-1")
        XCTAssertEqual(presentation.initialScrollParagraphID, "daily-journal-1")
    }

    func testPresentationFallsBackToFirstParagraphWhenSelectionMissing() {
        let first = DailyStoryParagraph(
            id: "daily-journal-0",
            text: "First paragraph",
            sourceEventIDs: [UUID()]
        )
        let second = DailyStoryParagraph(
            id: "daily-journal-1",
            text: "Second paragraph",
            sourceEventIDs: [UUID()]
        )
        let story = DailyStory(
            dayKey: "2026-04-08",
            generatedAt: Date(timeIntervalSince1970: 0),
            sections: [
                DailyStorySection(id: "summary", title: "Summary", paragraphs: [first, second])
            ]
        )

        let presentation = DailyMarkdownPresentation(
            story: story,
            selectedParagraphID: "missing-id"
        )

        XCTAssertEqual(presentation.selectedParagraphID, "missing-id")
        XCTAssertEqual(presentation.scrollTargetParagraphID, "daily-journal-0")
        XCTAssertEqual(presentation.initialScrollParagraphID, "daily-journal-0")
    }

    func testMarkdownRendererParsesHeadingBulletAndTaskBlocks() {
        let markdown = """
        # 今日总结

        - 第一项
        - 第二项

        - [ ] 跟进会议
        - [x] 完成文档
        """

        let blocks = DailyMarkdownRenderer.blocks(from: markdown)

        XCTAssertEqual(blocks.count, 3)

        guard case .heading(let level, let heading) = blocks[0] else {
            return XCTFail("Expected heading block")
        }
        XCTAssertEqual(level, 1)
        XCTAssertEqual(heading.plainText, "今日总结")

        guard case .bulletList(let bullets) = blocks[1] else {
            return XCTFail("Expected bullet list block")
        }
        XCTAssertEqual(bullets.map(\.plainText), ["第一项", "第二项"])

        guard case .taskList(let tasks) = blocks[2] else {
            return XCTFail("Expected task list block")
        }
        XCTAssertEqual(tasks.map(\.isCompleted), [false, true])
        XCTAssertEqual(tasks.map(\.content.plainText), ["跟进会议", "完成文档"])
    }

    func testDailyTodoCandidateExtractorReadsOpenTasksFromTodoParagraphs() throws {
        let sourceEventID = UUID()
        let story = DailyStory(
            dayKey: "2026-05-27",
            generatedAt: Date(timeIntervalSince1970: 1_778_000_000),
            sections: [
                DailyStorySection(
                    id: "daily-journal",
                    title: "",
                    paragraphs: [
                        DailyStoryParagraph(
                            id: "daily-journal-todo",
                            text: """
                            # To-do

                            - [ ] Send the investor recap
                            - [x] Confirmed the already-done item
                            - [ ] 约定周五会议时间
                            """,
                            sourceEventIDs: [sourceEventID]
                        )
                    ]
                )
            ]
        )

        let candidates = DailyTodoCandidate.extract(from: story)

        XCTAssertEqual(candidates.map(\.title), ["Send the investor recap", "约定周五会议时间"])
        XCTAssertEqual(candidates.map(\.paragraphID), ["daily-journal-todo", "daily-journal-todo"])
        XCTAssertEqual(candidates.first?.sourceDayKey, "2026-05-27")
        XCTAssertEqual(candidates.first?.sourceEventIDs, [sourceEventID])
    }

    func testDailyTodoCandidatePresentationMarksTrackedItems() {
        let tracked = DailyTodoCandidate(
            id: "tracked",
            title: "Send the investor recap",
            normalizedTitle: "send the investor recap",
            sourceDayKey: "2026-05-27",
            sourceEventIDs: [],
            paragraphID: "daily-journal-todo"
        )
        let untracked = DailyTodoCandidate(
            id: "untracked",
            title: "约定周五会议时间",
            normalizedTitle: "约定周五会议时间",
            sourceDayKey: "2026-05-27",
            sourceEventIDs: [],
            paragraphID: "daily-journal-todo"
        )

        let presentations = DailyTodoCandidatePresentation.make(
            candidates: [tracked, untracked],
            trackedCandidateIDs: Set(["tracked"])
        )

        XCTAssertEqual(presentations.map(\.title), ["Send the investor recap", "约定周五会议时间"])
        XCTAssertEqual(presentations.map(\.statusTitle), ["In Todo", "Add to Todo"])
        XCTAssertEqual(presentations.map(\.isTracked), [true, false])
    }

    func testMarkdownRendererParsesPipeTables() {
        let markdown = """
        | Date | Source claim | Implication |
        | --- | --- | --- |
        | 2026-04-28 | AI Force was reused by johnson-gq1-cheng. | Platform base. |
        | 2026-05-14 | AI Force relates to workflow and agents. | Training system. |
        """

        let blocks = DailyMarkdownRenderer.blocks(from: markdown)

        XCTAssertEqual(blocks.count, 1)
        guard case .table(let table) = blocks[0] else {
            return XCTFail("Expected table block")
        }
        XCTAssertEqual(table.headers.map(\.plainText), ["Date", "Source claim", "Implication"])
        XCTAssertEqual(table.rows.count, 2)
        XCTAssertEqual(table.rows.first?.map(\.plainText), [
            "2026-04-28",
            "AI Force was reused by johnson-gq1-cheng.",
            "Platform base."
        ])
    }

    func testMarkdownRendererPreservesLegacyDetailsMarkdownInsideOneParagraph() {
        let markdown = """
        # 详情

        ## 软件研发智能体沟通

        第一段内容。

        ## KnowYou 产品与定位

        第二段内容。
        """

        let paragraph = DailyStoryParagraph(
            id: "daily-journal-2",
            text: markdown,
            sourceEventIDs: [UUID(), UUID()]
        )
        let story = DailyStory(
            dayKey: "2026-04-09",
            generatedAt: Date(timeIntervalSince1970: 0),
            sections: [
                DailyStorySection(id: "daily-journal", title: "", paragraphs: [paragraph])
            ]
        )

        let presentation = DailyMarkdownPresentation(story: story)
        let blocks = DailyMarkdownRenderer.blocks(from: paragraph.text)

        XCTAssertEqual(presentation.paragraphs.count, 1)
        XCTAssertEqual(presentation.paragraphs.first?.id, "daily-journal-2")
        XCTAssertEqual(blocks.count, 5)

        guard case .heading(let firstLevel, let firstHeading) = blocks[0] else {
            return XCTFail("Expected first heading")
        }
        XCTAssertEqual(firstLevel, 1)
        XCTAssertEqual(firstHeading.plainText, "详情")

        guard case .heading(let secondLevel, let secondHeading) = blocks[1] else {
            return XCTFail("Expected second heading")
        }
        XCTAssertEqual(secondLevel, 2)
        XCTAssertEqual(secondHeading.plainText, "软件研发智能体沟通")

        guard case .heading(let thirdLevel, let thirdHeading) = blocks[3] else {
            return XCTFail("Expected third heading")
        }
        XCTAssertEqual(thirdLevel, 2)
        XCTAssertEqual(thirdHeading.plainText, "KnowYou 产品与定位")
    }

    private var gregorianCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func makeDate(year: Int, month: Int, day: Int, hour: Int = 0, minute: Int = 0) -> Date {
        DateComponents(
            calendar: gregorianCalendar,
            timeZone: TimeZone(secondsFromGMT: 0),
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        ).date!
    }
}
