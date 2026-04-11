import XCTest
@testable import KnowYou

final class DailyMarkdownViewTests: XCTestCase {
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
        XCTAssertEqual(brand.glyph, .asset(.chatGPT))
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

    func testMarkdownRendererKeepsDetailsParagraphAsSingleMarkdownBlockSequence() {
        let markdown = """
        # 详情

        ## 软件研发智能体沟通

        第一段内容。

        ## Know You 产品与定位

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
        XCTAssertEqual(thirdHeading.plainText, "Know You 产品与定位")
    }
}
