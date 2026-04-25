import XCTest
@testable import KnowYou

final class DailyMarkdownViewTests: XCTestCase {
    func testDateSidebarPresentationGroupsDatesByEnglishMonth() {
        let presentation = DateSidebarPresentation(
            dates: ["2026-04-24", "2026-04-23", "2026-03-31", "demo-day"],
            selectedDate: nil,
            today: makeDate(year: 2026, month: 4, day: 24),
            calendar: gregorianCalendar
        )

        XCTAssertEqual(presentation.sections.map(\.title), ["April 2026", "March 2026", nil])
        XCTAssertEqual(presentation.sections[0].items.map(\.id), ["2026-04-24", "2026-04-23"])
        XCTAssertEqual(presentation.sections[1].items.map(\.id), ["2026-03-31"])
        XCTAssertEqual(presentation.sections[2].items.map(\.id), ["demo-day"])
    }

    func testDateSidebarPresentationOpensCurrentMonthAndCollapsesOlderMonths() {
        let presentation = DateSidebarPresentation(
            dates: ["2026-04-24", "2026-03-31"],
            selectedDate: nil,
            today: makeDate(year: 2026, month: 4, day: 24),
            calendar: gregorianCalendar
        )

        XCTAssertTrue(presentation.sections[0].isExpandedByDefault)
        XCTAssertFalse(presentation.sections[1].isExpandedByDefault)
    }

    func testDateSidebarPresentationOpensSelectedOlderMonth() {
        let presentation = DateSidebarPresentation(
            dates: ["2026-04-24", "2026-03-31"],
            selectedDate: "2026-03-31",
            today: makeDate(year: 2026, month: 4, day: 24),
            calendar: gregorianCalendar
        )

        XCTAssertTrue(presentation.sections[0].isExpandedByDefault)
        XCTAssertTrue(presentation.sections[1].isExpandedByDefault)
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

    private func makeDate(year: Int, month: Int, day: Int) -> Date {
        DateComponents(
            calendar: gregorianCalendar,
            timeZone: TimeZone(secondsFromGMT: 0),
            year: year,
            month: month,
            day: day
        ).date!
    }
}
