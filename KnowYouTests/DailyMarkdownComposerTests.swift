import XCTest
@testable import KnowYou

final class DailyMarkdownComposerTests: XCTestCase {
    func testComposerProducesStoryFirstSections() {
        let composer = DailyMarkdownComposer()
        let events = [
            EventRecord(
                id: UUID(),
                sourceType: .clipboard,
                sourceApp: "Drafts",
                capturedAt: Date(timeIntervalSince1970: 1_775_000_000),
                dayKey: "2026-04-07",
                text: "Wrote investor update",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "a"
            ),
            EventRecord(
                id: UUID(),
                sourceType: .notification,
                sourceApp: "Calendar",
                capturedAt: Date(timeIntervalSince1970: 1_775_000_100),
                dayKey: "2026-04-07",
                text: "Meeting in 10 minutes",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "b"
            ),
        ]
        let story = composer.fallbackStory(dayKey: "2026-04-07", events: events)

        let markdown = composer.compose(dayKey: "2026-04-07", events: events, story: story)

        XCTAssertTrue(markdown.contains("## Story"), markdown)
        XCTAssertTrue(markdown.contains("## Source Notes"), markdown)
        XCTAssertFalse(markdown.contains("### Main Thread"), markdown)
        XCTAssertFalse(markdown.contains("### Key Progress"), markdown)
    }

    func testFallbackStoryCreatesSourceLinkedParagraphs() {
        let composer = DailyMarkdownComposer()
        let eventID = UUID()
        let events = [
            EventRecord(
                id: eventID,
                sourceType: .clipboard,
                sourceApp: "Drafts",
                capturedAt: Date(timeIntervalSince1970: 1_775_000_000),
                dayKey: "2026-04-07",
                text: "Wrote investor update",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "a"
            ),
        ]

        let story = composer.fallbackStory(dayKey: "2026-04-07", events: events)
        let linkedIDs = story.sections.flatMap(\.paragraphs).flatMap(\.sourceEventIDs)

        XCTAssertTrue(linkedIDs.contains(eventID))
        XCTAssertFalse(story.sections.flatMap(\.paragraphs).isEmpty)
    }

    func testStoryPromptRequestsSingleJournalNarrative() {
        let composer = DailyMarkdownComposer()
        let events = [
            EventRecord(
                id: UUID(),
                sourceType: .clipboard,
                sourceApp: "Ghostty",
                capturedAt: Date(timeIntervalSince1970: 1_775_000_000),
                dayKey: "2026-04-08",
                text: "Implemented the daily story reader",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "prompt-check"
            )
        ]

        let prompt = composer.storyPrompt(dayKey: "2026-04-08", events: events)

        XCTAssertTrue(prompt.contains("\"id\": \"daily-journal\""), prompt)
        XCTAssertTrue(prompt.localizedCaseInsensitiveContains("diary"), prompt)
        XCTAssertTrue(prompt.localizedCaseInsensitiveContains("single section id"), prompt)
        XCTAssertTrue(prompt.localizedCaseInsensitiveContains("same dominant language"), prompt)
        XCTAssertTrue(prompt.localizedCaseInsensitiveContains("first person"), prompt)
        XCTAssertTrue(prompt.localizedCaseInsensitiveContains("major threads or workstreams"), prompt)
        XCTAssertFalse(prompt.contains("\"main-thread\""), prompt)
    }

    func testStoryPromptRequestsStructuredMarkdownDiarySections() {
        let composer = DailyMarkdownComposer()
        let events = [
            EventRecord(
                id: UUID(),
                sourceType: .notification,
                sourceApp: "com.microsoft.teams2",
                capturedAt: Date(timeIntervalSince1970: 1_775_000_000),
                dayKey: "2026-04-09",
                text: "讨论新财年的软件研发智能体需求",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "prompt-structure-check"
            )
        ]

        let prompt = composer.storyPrompt(dayKey: "2026-04-09", events: events)

        XCTAssertTrue(prompt.contains("# 你今天做得很棒"), prompt)
        XCTAssertTrue(prompt.contains("# 今日总结"), prompt)
        XCTAssertTrue(prompt.contains("# 详情"), prompt)
        XCTAssertTrue(prompt.contains("# 待办事项"), prompt)
        XCTAssertTrue(prompt.localizedCaseInsensitiveContains("do not include # 今日节奏"), prompt)
        XCTAssertTrue(prompt.localizedCaseInsensitiveContains("task list"), prompt)
        XCTAssertTrue(prompt.localizedCaseInsensitiveContains("markdown"), prompt)
        XCTAssertTrue(prompt.localizedCaseInsensitiveContains("must contain exactly one sentence"), prompt)
        XCTAssertTrue(prompt.localizedCaseInsensitiveContains("like a short inspirational quote"), prompt)
        XCTAssertTrue(prompt.localizedCaseInsensitiveContains("do not add a quote author"), prompt)
    }

    func testStoryPromptUsesEnglishDiaryHeadingsForEnglishDominantDay() {
        let composer = DailyMarkdownComposer()
        let events = [
            EventRecord(
                id: UUID(),
                sourceType: .clipboard,
                sourceApp: "Notes",
                capturedAt: Date(timeIntervalSince1970: 1_775_000_000),
                dayKey: "2026-04-10",
                text: "Refined the prompt to switch headings by language",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "prompt-english-headings"
            )
        ]

        let prompt = composer.storyPrompt(dayKey: "2026-04-10", events: events)

        XCTAssertTrue(prompt.contains("# You did a good job today"), prompt)
        XCTAssertTrue(prompt.contains("# Summary"), prompt)
        XCTAssertTrue(prompt.contains("# Details"), prompt)
        XCTAssertTrue(prompt.contains("# To-do"), prompt)
        XCTAssertFalse(prompt.contains("# 你今天做得很棒"), prompt)
        XCTAssertTrue(prompt.localizedCaseInsensitiveContains("same dominant language"), prompt)
    }

    func testStoryPromptMakesEncouragementSectionAQuoteStyleSentence() {
        let composer = DailyMarkdownComposer()
        let events = [
            EventRecord(
                id: UUID(),
                sourceType: .clipboard,
                sourceApp: "Ghostty",
                capturedAt: Date(timeIntervalSince1970: 1_775_000_000),
                dayKey: "2026-04-11",
                text: "Keep the first section inspiring instead of repeating the day's tasks",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "prompt-quote-style"
            )
        ]

        let prompt = composer.storyPrompt(dayKey: "2026-04-11", events: events)

        XCTAssertTrue(prompt.localizedCaseInsensitiveContains("must contain exactly one sentence"), prompt)
        XCTAssertTrue(prompt.localizedCaseInsensitiveContains("short inspirational quote"), prompt)
        XCTAssertTrue(prompt.localizedCaseInsensitiveContains("not a recap of tasks"), prompt)
        XCTAssertTrue(prompt.localizedCaseInsensitiveContains("do not retell the chronology"), prompt)
        XCTAssertTrue(prompt.localizedCaseInsensitiveContains("do not add a quote author"), prompt)
        XCTAssertTrue(prompt.localizedCaseInsensitiveContains("do not use quotation marks"), prompt)
    }

    func testStoryPromptExplicitlyTiesOutputLanguageToInputLanguage() {
        let composer = DailyMarkdownComposer()
        let events = [
            EventRecord(
                id: UUID(),
                sourceType: .clipboard,
                sourceApp: "Notes",
                capturedAt: Date(timeIntervalSince1970: 1_775_000_000),
                dayKey: "2026-04-10",
                text: "Refined the prompt to switch headings by language",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "prompt-language-rule"
            )
        ]

        let prompt = composer.storyPrompt(dayKey: "2026-04-10", events: events)

        XCTAssertTrue(prompt.localizedCaseInsensitiveContains("determine whether the day is mainly English or mainly Chinese"), prompt)
        XCTAssertTrue(prompt.localizedCaseInsensitiveContains("use English for all diary prose and headings"), prompt)
        XCTAssertTrue(prompt.localizedCaseInsensitiveContains("use Chinese for all diary prose and headings"), prompt)
    }

    func testStoryPromptRendersConcreteEventLinesInsteadOfSQLDebugDescriptions() {
        let composer = DailyMarkdownComposer()
        let eventID = UUID()
        let events = [
            EventRecord(
                id: eventID,
                sourceType: .clipboard,
                sourceApp: "Ghostty",
                capturedAt: Date(timeIntervalSince1970: 1_775_000_000),
                dayKey: "2026-04-11",
                text: "为什么都是红的？理论上讲，除了 OpenAI API 之外，其余应该都是可以被调通的呀？",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "prompt-event-lines"
            )
        ]

        let prompt = composer.storyPrompt(dayKey: "2026-04-11", events: events)

        XCTAssertTrue(prompt.contains("- id: \(eventID.uuidString)"), prompt)
        XCTAssertTrue(prompt.contains("app: Ghostty"), prompt)
        XCTAssertTrue(prompt.contains("text: 为什么都是红的？理论上讲，除了 OpenAI API 之外，其余应该都是可以被调通的呀？"), prompt)
        XCTAssertFalse(prompt.contains("SQL(elements:"), prompt)
        XCTAssertFalse(prompt.contains("GRDB.SQL.Element"), prompt)
    }

    func testComposerAddsLightweightMarkdownStructure() {
        let composer = DailyMarkdownComposer()
        let paragraph = DailyStoryParagraph(
            id: "daily-journal-0",
            text: "I kept moving through the main tasks and left a few **important** notes for later.",
            sourceEventIDs: [UUID()]
        )
        let story = DailyStory(
            dayKey: "2026-04-08",
            generatedAt: Date(timeIntervalSince1970: 1_775_000_000),
            sections: [DailyStorySection(id: "daily-journal", title: "", paragraphs: [paragraph])]
        )
        let events = [
            EventRecord(
                id: UUID(),
                sourceType: .clipboard,
                sourceApp: "Notes",
                capturedAt: Date(timeIntervalSince1970: 1_775_000_000),
                dayKey: "2026-04-08",
                text: "Important note",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "markdown-structure"
            )
        ]

        let markdown = composer.compose(dayKey: "2026-04-08", events: events, story: story)

        XCTAssertTrue(markdown.contains("## Story"), markdown)
        XCTAssertTrue(markdown.contains("---\n\n## Source Notes"), markdown)
        XCTAssertFalse(markdown.contains("A softer story pass"), markdown)
    }

    func testFallbackStoryUsesChineseNarrationForChineseDominantDay() {
        let composer = DailyMarkdownComposer()
        let events = [
            EventRecord(
                id: UUID(),
                sourceType: .clipboard,
                sourceApp: "微信",
                capturedAt: Date(timeIntervalSince1970: 1_775_000_000),
                dayKey: "2026-04-08",
                text: "整理今天的发布文案，并和团队确认排期",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "zh-1"
            ),
            EventRecord(
                id: UUID(),
                sourceType: .notification,
                sourceApp: "飞书",
                capturedAt: Date(timeIntervalSince1970: 1_775_000_300),
                dayKey: "2026-04-08",
                text: "下午三点同步版本细节",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "zh-2"
            ),
        ]

        let story = composer.fallbackStory(dayKey: "2026-04-08", events: events)
        let combined = story.sections.flatMap(\.paragraphs).map(\.text).joined(separator: "\n")

        XCTAssertTrue(combined.contains(where: \.isChineseIdeograph), combined)
        XCTAssertFalse(combined.localizedCaseInsensitiveContains("the day mostly revolved around"), combined)
        XCTAssertFalse(combined.localizedCaseInsensitiveContains("later on"), combined)
    }

    func testFallbackStoryCompressesNoisyDaysIntoFewDiaryParagraphs() {
        let composer = DailyMarkdownComposer()
        let baseDate = Date(timeIntervalSince1970: 1_775_000_000)
        let events: [EventRecord] = [
            makeEvent(app: "Ghostty", offset: 0, text: "Implemented story-first reader"),
            makeEvent(app: "Ghostty", offset: 60, text: "Refined paragraph selection behavior"),
            makeEvent(app: "Google Chrome", offset: 120, text: "https://github.com/gift-is-coding/know-you/pull/1"),
            makeEvent(app: "Google Chrome", offset: 180, text: "https://github.com/steipete/CodexBar?tab=readme-ov-file"),
            makeEvent(app: "WeChat", offset: 240, text: "你看看去哪呀？"),
            makeEvent(app: "Feishu", offset: 300, text: "仓库\t快递单号\t货物概述"),
            makeEvent(app: "Ghostty", offset: 360, text: "KnowYou clipboard sentinel: knowyou-verify-20260408T132014"),
            makeEvent(app: "Ghostty", offset: 420, text: "KnowYou clipboard sentinel: knowyou-verify-20260408T132021"),
            makeEvent(app: "Finder", offset: 480, text: "/Users/wutianfu/Code/know-you"),
            makeEvent(app: "Google Chrome", offset: 540, text: "Av. Paulista, 2537 - Bela Vista"),
        ].enumerated().map { index, event in
            EventRecord(
                id: UUID(),
                sourceType: .clipboard,
                sourceApp: event.sourceApp,
                capturedAt: baseDate.addingTimeInterval(TimeInterval(index * 60)),
                dayKey: "2026-04-08",
                text: event.text,
                auditText: nil,
                privacyAction: .keep,
                contentHash: "hash-\(index)"
            )
        }

        let story = composer.fallbackStory(dayKey: "2026-04-08", events: events)
        let journal = story.sections.first(where: { $0.id == "daily-journal" })

        XCTAssertNotNil(journal)
        XCTAssertLessThanOrEqual(journal?.paragraphs.count ?? .max, 4)
        XCTAssertTrue(
            journal?.paragraphs.contains(where: { $0.text.localizedCaseInsensitiveContains("verification") }) ?? false,
            "Expected noisy verification sentinels to be summarized into the diary narrative"
        )
        XCTAssertTrue(
            journal?.paragraphs.contains(where: { $0.text.localizedCaseInsensitiveContains("reference") || $0.text.localizedCaseInsensitiveContains("materials") }) ?? false,
            "Expected loose links to be summarized into the diary narrative"
        )
    }

    func testIncrementalPromptUsesOnlyNewEventsAndCompressedAnchors() {
        let composer = DailyMarkdownComposer()
        let oldID = UUID()
        let newID = UUID()
        let existingStory = DailyStory(
            dayKey: "2026-04-12",
            generatedAt: Date(timeIntervalSince1970: 1_775_000_000),
            sections: [
                DailyStorySection(
                    id: "daily-journal",
                    title: "",
                    paragraphs: [
                        DailyStoryParagraph(
                            id: "daily-journal-0",
                            text: """
                            # You did a good job today

                            Keep going.

                            # Summary

                            - Finished the morning pass

                            # Details

                            ## Main Thread

                            Closed one core workflow.

                            # To-do

                            - [ ] Follow up
                            """,
                            sourceEventIDs: [oldID]
                        )
                    ]
                )
            ],
            provenance: StoryProvenance(
                generationMode: .model,
                engineKind: "codexCLI",
                engineLabel: "Codex CLI",
                model: nil,
                pipelineVersion: "diary-story-v1",
                curatedEventCount: 1
            )
        )
        let oldEvent = EventRecord(
            id: oldID,
            sourceType: .clipboard,
            sourceApp: "Notes",
            capturedAt: Date(timeIntervalSince1970: 1_775_000_000),
            dayKey: "2026-04-12",
            text: "Finished the morning pass",
            auditText: nil,
            privacyAction: .keep,
            contentHash: "old"
        )
        let newEvent = EventRecord(
            id: newID,
            sourceType: .notification,
            sourceApp: "Mail",
            capturedAt: Date(timeIntervalSince1970: 1_775_000_300),
            dayKey: "2026-04-12",
            text: "Customer approved the next revision",
            auditText: nil,
            privacyAction: .keep,
            contentHash: "new"
        )

        let prompt = composer.incrementalPrompt(
            dayKey: "2026-04-12",
            existingStory: existingStory,
            newEvents: [newEvent],
            allEvents: [oldEvent, newEvent]
        )

        XCTAssertTrue(prompt.contains(newID.uuidString), prompt)
        XCTAssertFalse(prompt.contains("Finished the morning pass\n              text"), prompt)
        XCTAssertTrue(prompt.contains("Existing encouragement anchor"), prompt)
        XCTAssertTrue(prompt.contains("Existing summary anchor"), prompt)
        XCTAssertTrue(prompt.contains("Already used sourceEventIDs"), prompt)
        XCTAssertTrue(prompt.contains(oldID.uuidString), prompt)
        XCTAssertTrue(prompt.contains("Customer approved the next revision"), prompt)
        XCTAssertFalse(prompt.contains("Do not rewrite or re-summarize the whole day.") == false)
    }

    func testMergeIncrementalUpdatePreservesEncouragementAndAppendsSections() {
        let composer = DailyMarkdownComposer()
        let oldID = UUID()
        let newSummaryID = UUID()
        let newDetailID = UUID()
        let newTodoID = UUID()
        let existingStory = DailyStory(
            dayKey: "2026-04-12",
            generatedAt: Date(timeIntervalSince1970: 1_775_000_000),
            sections: [
                DailyStorySection(
                    id: "daily-journal",
                    title: "",
                    paragraphs: [
                        DailyStoryParagraph(
                            id: "daily-journal-0",
                            text: """
                            # You did a good job today

                            Keep the steady pace.

                            # Summary

                            - Wrapped the first pass

                            # Details

                            ## Existing Thread

                            Shipped the first iteration.

                            # To-do

                            - [ ] Send recap
                            """,
                            sourceEventIDs: [oldID]
                        )
                    ]
                )
            ],
            provenance: StoryProvenance(
                generationMode: .model,
                engineKind: "codexCLI",
                engineLabel: "Codex CLI",
                model: nil,
                pipelineVersion: "diary-story-v1",
                curatedEventCount: 1
            )
        )
        let update = composer.parseIncrementalUpdate(
            raw: """
            {
              "summaryBulletsToAppend": [
                { "text": "- Landed the follow-up review", "sourceEventIDs": ["\(newSummaryID.uuidString)"] }
              ],
              "detailBlocksToAppend": [
                { "text": "## Follow-up\\n\\nHandled the customer feedback loop.", "sourceEventIDs": ["\(newDetailID.uuidString)"] }
              ],
              "todoItemsToAppend": [
                { "text": "- [ ] Queue the final handoff", "sourceEventIDs": ["\(newTodoID.uuidString)"] }
              ]
            }
            """
        )

        XCTAssertNotNil(update)

        let merged = composer.mergeIncrementalUpdate(
            dayKey: "2026-04-12",
            existingStory: existingStory,
            update: update!,
            allEvents: [],
            provenance: StoryProvenance(
                generationMode: .model,
                engineKind: "claudeCLI",
                engineLabel: "Claude CLI",
                model: nil,
                pipelineVersion: "diary-story-v1",
                curatedEventCount: 4
            )
        )

        let paragraphs = merged.sections.flatMap(\.paragraphs)
        XCTAssertEqual(paragraphs.count, 4)
        XCTAssertEqual(paragraphs[0].text, "# You did a good job today\n\nKeep the steady pace.")
        XCTAssertTrue(paragraphs[1].text.contains("- Wrapped the first pass"))
        XCTAssertTrue(paragraphs[1].text.contains("- Landed the follow-up review"))
        XCTAssertTrue(paragraphs[2].text.contains("## Existing Thread"))
        XCTAssertTrue(paragraphs[2].text.contains("## Follow-up"))
        XCTAssertTrue(paragraphs[3].text.contains("- [ ] Send recap"))
        XCTAssertTrue(paragraphs[3].text.contains("- [ ] Queue the final handoff"))
        XCTAssertEqual(Set(paragraphs[0].sourceEventIDs), [oldID])
        XCTAssertEqual(Set(paragraphs[1].sourceEventIDs), [oldID, newSummaryID])
        XCTAssertEqual(Set(paragraphs[2].sourceEventIDs), [oldID, newDetailID])
        XCTAssertEqual(Set(paragraphs[3].sourceEventIDs), [oldID, newTodoID])
        XCTAssertEqual(merged.provenance?.engineLabel, "Claude CLI")
    }

    private func makeEvent(app: String, offset: Int, text: String) -> EventRecord {
        EventRecord(
            id: UUID(),
            sourceType: .clipboard,
            sourceApp: app,
            capturedAt: Date(timeIntervalSince1970: 1_775_000_000 + TimeInterval(offset)),
            dayKey: "2026-04-08",
            text: text,
            auditText: nil,
            privacyAction: .keep,
            contentHash: UUID().uuidString
        )
    }
}

private extension Character {
    var isChineseIdeograph: Bool {
        unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(scalar.value)
        }
    }
}
