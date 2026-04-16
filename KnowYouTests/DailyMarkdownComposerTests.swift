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

    func testDefaultStoryPromptMatchesLegacyStoryPromptOutput() {
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
                contentHash: "prompt-default-check"
            )
        ]

        XCTAssertEqual(
            composer.storyPrompt(dayKey: "2026-04-08", events: events),
            composer.defaultStoryPrompt(dayKey: "2026-04-08", events: events)
        )
    }

    func testDefaultStoryPromptPreviewUsesCanonicalEnglishSeedData() {
        let composer = DailyMarkdownComposer()
        let preview = composer.defaultStoryPromptPreview(language: .english)

        XCTAssertTrue(preview.contains("# You did a good job today"), preview)
        XCTAssertTrue(preview.contains("AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"), preview)
        XCTAssertTrue(preview.contains("BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB"), preview)
        XCTAssertTrue(preview.contains("Drafted a stable preview for the daily story prompt"), preview)
    }

    func testDefaultStoryPromptPreviewUsesCanonicalChineseSeedData() {
        let composer = DailyMarkdownComposer()
        let preview = composer.defaultStoryPromptPreview(language: .chinese)

        XCTAssertTrue(preview.contains("# 你今天做得很棒"), preview)
        XCTAssertTrue(preview.contains("11111111-1111-1111-1111-111111111111"), preview)
        XCTAssertTrue(preview.contains("22222222-2222-2222-2222-222222222222"), preview)
        XCTAssertTrue(preview.contains("整理今天的日记预览内容"), preview)
    }

    func testStoryPromptUsesCanonicalDefaultPrompt() {
        let composer = DailyMarkdownComposer()
        let events = [
            EventRecord(
                id: UUID(),
                sourceType: .clipboard,
                sourceApp: "Notes",
                capturedAt: Date(timeIntervalSince1970: 1_775_000_000),
                dayKey: "2026-04-08",
                text: "Explicit nil should use the canonical default prompt",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "prompt-override-nil"
            )
        ]

        XCTAssertEqual(
            composer.storyPrompt(dayKey: "2026-04-08", events: events),
            composer.defaultStoryPrompt(dayKey: "2026-04-08", events: events)
        )
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

    func testComposeFlattensMultilineAndMarkdownShapedSourceNotes() {
        let composer = DailyMarkdownComposer()
        let events = [
            EventRecord(
                id: UUID(),
                sourceType: .clipboard,
                sourceApp: "Notes",
                capturedAt: Date(timeIntervalSince1970: 1_775_000_000),
                dayKey: "2026-04-08",
                text: """
                Drafted a diary source note
                ## Injected heading
                - [ ] Injected task
                """,
                auditText: nil,
                privacyAction: .keep,
                contentHash: "source-note-compose"
            )
        ]
        let story = composer.fallbackStory(dayKey: "2026-04-08", events: events)

        let markdown = composer.compose(dayKey: "2026-04-08", events: events, story: story)

        XCTAssertTrue(markdown.contains("Drafted a diary source note ## Injected heading - [ ] Injected task"), markdown)
        XCTAssertFalse(markdown.contains("\n## Injected heading"), markdown)
        XCTAssertFalse(markdown.contains("\n- [ ] Injected task"), markdown)
    }

    func testSourceNotesMarkdownFlattensMultilineAndMarkdownShapedSourceNotes() {
        let composer = DailyMarkdownComposer()
        let events = [
            EventRecord(
                id: UUID(),
                sourceType: .clipboard,
                sourceApp: "Notes",
                capturedAt: Date(timeIntervalSince1970: 1_775_000_000),
                dayKey: "2026-04-08",
                text: """
                Drafted a diary source note
                ## Injected heading
                - [ ] Injected task
                """,
                auditText: nil,
                privacyAction: .keep,
                contentHash: "source-note-notes"
            )
        ]

        let markdown = composer.sourceNotesMarkdown(for: events)

        XCTAssertTrue(markdown.contains("Drafted a diary source note ## Injected heading - [ ] Injected task"), markdown)
        XCTAssertFalse(markdown.contains("\n## Injected heading"), markdown)
        XCTAssertFalse(markdown.contains("\n- [ ] Injected task"), markdown)
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

    func testIncrementalPromptUsesExistingStoryAndNewEventsForReplacementAndAppendContract() {
        let composer = DailyMarkdownComposer()
        let oldID = UUID()
        let newID = UUID()
        let fallbackID = UUID()
        let existingStory = DailyStory(
            dayKey: "2026-04-12",
            generatedAt: Date(timeIntervalSince1970: 1_775_000_000),
            sections: [
                DailyStorySection(
                    id: "daily-journal",
                    title: "",
                    paragraphs: [
                        DailyStoryParagraph(
                            id: "daily-journal-encouragement",
                            text: "# You did a good job today\n\nKeep going.",
                            sourceEventIDs: [oldID]
                        ),
                        DailyStoryParagraph(
                            id: "daily-journal-summary",
                            text: "# Summary\n\n- Finished the morning pass",
                            sourceEventIDs: [oldID]
                        ),
                        DailyStoryParagraph(
                            id: "daily-journal-details-0",
                            text: "# Details\n\n## Main Thread\n\nClosed one core workflow.",
                            sourceEventIDs: [oldID]
                        ),
                        DailyStoryParagraph(
                            id: "daily-journal-todo",
                            text: "# To-do\n\n- [ ] Follow up",
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
        let fallbackEvent = EventRecord(
            id: fallbackID,
            sourceType: .clipboard,
            sourceApp: "终端",
            capturedAt: Date(timeIntervalSince1970: 1_775_000_400),
            dayKey: "2026-04-12",
            text: "补充整理中文线索，用来测试回退语言判定",
            auditText: nil,
            privacyAction: .keep,
            contentHash: "fallback"
        )

        let prompt = composer.incrementalPrompt(
            dayKey: "2026-04-12",
            existingStory: existingStory,
            newEvents: [newEvent],
            allEvents: [fallbackEvent]
        )

        XCTAssertTrue(prompt.contains(newID.uuidString), prompt)
        XCTAssertFalse(prompt.contains("app: Notes"), prompt)
        XCTAssertTrue(prompt.contains("Existing encouragement anchor"), prompt)
        XCTAssertTrue(prompt.contains("Existing summary anchor"), prompt)
        XCTAssertTrue(prompt.contains("Existing details anchor"), prompt)
        XCTAssertTrue(prompt.contains("Existing todo anchor"), prompt)
        XCTAssertTrue(prompt.contains("Already used sourceEventIDs"), prompt)
        XCTAssertTrue(prompt.contains(oldID.uuidString), prompt)
        XCTAssertTrue(prompt.contains("Customer approved the next revision"), prompt)
        XCTAssertTrue(prompt.contains("\"encouragementToReplace\""), prompt)
        XCTAssertTrue(prompt.contains("\"summaryBulletsToReplace\""), prompt)
        XCTAssertTrue(prompt.contains("\"detailBlocksToAppend\""), prompt)
        XCTAssertTrue(prompt.contains("\"todoItemsToReplace\""), prompt)
        XCTAssertTrue(prompt.localizedCaseInsensitiveContains("rewrite \"# Summary\" as the current full summary state"), prompt)
        XCTAssertTrue(prompt.localizedCaseInsensitiveContains("append only the new markdown blocks needed for \"# Details\""), prompt)
        XCTAssertTrue(prompt.localizedCaseInsensitiveContains("rewrite \"# To-do\" as the current full to-do state"), prompt)
        XCTAssertFalse(prompt.contains("all events"), prompt)
        XCTAssertFalse(prompt.contains("# 你今天做得很棒"), prompt)
    }

    func testStoryPromptRequestsReasonableDetailsParagraphSplits() {
        let composer = DailyMarkdownComposer()
        let events = [
            EventRecord(
                id: UUID(),
                sourceType: .clipboard,
                sourceApp: "Notes",
                capturedAt: Date(timeIntervalSince1970: 1_775_000_000),
                dayKey: "2026-04-10",
                text: "Refined the prompt to split details into reasonable workstreams",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "prompt-details-split"
            )
        ]

        let prompt = composer.storyPrompt(dayKey: "2026-04-10", events: events)

        XCTAssertTrue(prompt.localizedCaseInsensitiveContains("each details workstream should be its own paragraph"), prompt)
        XCTAssertTrue(prompt.localizedCaseInsensitiveContains("do not fragment the day into tiny paragraphs"), prompt)
    }

    func testParseIncrementalUpdateRequiresReplacementAndAppendPayloadAtomically() {
        let composer = DailyMarkdownComposer()
        let encouragementID = UUID()
        let summaryID = UUID()
        let detailID = UUID()
        let todoID = UUID()

        let validUpdate = composer.parseIncrementalUpdate(
            raw: """
            {
              "encouragementToReplace": {
                "text": "You kept the day moving even after the late change.",
                "sourceEventIDs": ["\(encouragementID.uuidString)"]
              },
              "summaryBulletsToReplace": [
                { "text": "- Closed the follow-up review", "sourceEventIDs": ["\(summaryID.uuidString)"] }
              ],
              "detailBlocksToAppend": [
                { "text": "## Follow-up\\n\\nHandled the customer feedback loop.", "sourceEventIDs": ["\(detailID.uuidString)"] }
              ],
              "todoItemsToReplace": [
                { "text": "- [ ] Queue the final handoff", "sourceEventIDs": ["\(todoID.uuidString)"] }
              ]
            }
            """
        )

        XCTAssertNotNil(validUpdate)
        XCTAssertEqual(validUpdate?.encouragementToReplace.text, "You kept the day moving even after the late change.")
        XCTAssertEqual(validUpdate?.summaryBulletsToReplace.map(\.text), ["- Closed the follow-up review"])
        XCTAssertEqual(validUpdate?.detailBlocksToAppend.map(\.text), ["## Follow-up\n\nHandled the customer feedback loop."])
        XCTAssertEqual(validUpdate?.todoItemsToReplace.map(\.text), ["- [ ] Queue the final handoff"])

        let missingField = composer.parseIncrementalUpdate(
            raw: """
            {
              "encouragementToReplace": {
                "text": "You kept the day moving even after the late change.",
                "sourceEventIDs": ["\(encouragementID.uuidString)"]
              },
              "summaryBulletsToReplace": [
                { "text": "- Closed the follow-up review", "sourceEventIDs": ["\(summaryID.uuidString)"] }
              ],
              "detailBlocksToAppend": [
                { "text": "## Follow-up\\n\\nHandled the customer feedback loop.", "sourceEventIDs": ["\(detailID.uuidString)"] }
              ]
            }
            """
        )

        XCTAssertNil(missingField)

        let invalidNestedField = composer.parseIncrementalUpdate(
            raw: """
            {
              "encouragementToReplace": {
                "text": "",
                "sourceEventIDs": ["\(encouragementID.uuidString)"]
              },
              "summaryBulletsToReplace": [
                { "text": "- Closed the follow-up review", "sourceEventIDs": ["\(summaryID.uuidString)"] }
              ],
              "detailBlocksToAppend": [
                { "text": "## Follow-up\\n\\nHandled the customer feedback loop.", "sourceEventIDs": ["\(detailID.uuidString)"] }
              ],
              "todoItemsToReplace": [
                { "text": "- [ ] Queue the final handoff", "sourceEventIDs": ["\(todoID.uuidString)"] }
              ]
            }
            """
        )

        XCTAssertNil(invalidNestedField)
    }

    func testParseIncrementalUpdateRejectsMixedValidAndInvalidUUIDStrings() {
        let composer = DailyMarkdownComposer()
        let validID = UUID()

        let update = composer.parseIncrementalUpdate(
            raw: """
            {
              "encouragementToReplace": {
                "text": "You kept the day moving even after the late change.",
                "sourceEventIDs": ["\(validID.uuidString)", "not-a-uuid"]
              },
              "summaryBulletsToReplace": [
                { "text": "- Closed the follow-up review", "sourceEventIDs": ["\(validID.uuidString)"] }
              ],
              "detailBlocksToAppend": [
                { "text": "## Follow-up\\n\\nHandled the customer feedback loop.", "sourceEventIDs": ["\(validID.uuidString)"] }
              ],
              "todoItemsToReplace": [
                { "text": "- [ ] Queue the final handoff", "sourceEventIDs": ["\(validID.uuidString)"] }
              ]
            }
            """
        )

        XCTAssertNil(update)
    }

    func testValidatedIncrementalUpdateRejectsReplacementRefsOutsideDayEventSet() {
        let composer = DailyMarkdownComposer()
        let validID = UUID()
        let invalidID = UUID()
        let parsed = composer.parseIncrementalUpdate(
            raw: """
            {
              "encouragementToReplace": {
                "text": "You kept the day moving even after the late change.",
                "sourceEventIDs": ["\(validID.uuidString)"]
              },
              "summaryBulletsToReplace": [
                { "text": "- Closed the follow-up review", "sourceEventIDs": ["\(invalidID.uuidString)"] }
              ],
              "detailBlocksToAppend": [
                { "text": "## Follow-up\\n\\nHandled the customer feedback loop.", "sourceEventIDs": ["\(validID.uuidString)"] }
              ],
              "todoItemsToReplace": [
                { "text": "- [ ] Queue the final handoff", "sourceEventIDs": ["\(validID.uuidString)"] }
              ]
            }
            """
        )

        let validated = composer.validatedIncrementalUpdate(
            try! XCTUnwrap(parsed),
            allowedSourceEventIDs: Set([validID]),
            allowedDetailSourceEventIDs: Set([validID])
        )

        XCTAssertNil(validated)
    }

    func testValidatedIncrementalUpdateDropsDetailRefsOutsideNewEventSet() {
        let composer = DailyMarkdownComposer()
        let validOldID = UUID()
        let validNewID = UUID()
        let invalidDetailID = UUID()
        let parsed = composer.parseIncrementalUpdate(
            raw: """
            {
              "encouragementToReplace": {
                "text": "You kept the day moving even after the late change.",
                "sourceEventIDs": ["\(validOldID.uuidString)", "\(validNewID.uuidString)"]
              },
              "summaryBulletsToReplace": [
                { "text": "- Closed the follow-up review", "sourceEventIDs": ["\(validNewID.uuidString)"] }
              ],
              "detailBlocksToAppend": [
                { "text": "## Follow-up\\n\\nHandled the customer feedback loop.", "sourceEventIDs": ["\(validNewID.uuidString)"] },
                { "text": "## Invalid\\n\\nThis should be dropped.", "sourceEventIDs": ["\(invalidDetailID.uuidString)"] }
              ],
              "todoItemsToReplace": [
                { "text": "- [ ] Queue the final handoff", "sourceEventIDs": ["\(validNewID.uuidString)"] }
              ]
            }
            """
        )

        let validated = composer.validatedIncrementalUpdate(
            try! XCTUnwrap(parsed),
            allowedSourceEventIDs: Set([validOldID, validNewID]),
            allowedDetailSourceEventIDs: Set([validNewID])
        )

        XCTAssertEqual(validated?.detailBlocksToAppend.map(\.text), ["## Follow-up\n\nHandled the customer feedback loop."])
        XCTAssertEqual(validated?.summaryBulletsToReplace.map(\.text), ["- Closed the follow-up review"])
        XCTAssertEqual(validated?.todoItemsToReplace.map(\.text), ["- [ ] Queue the final handoff"])
    }

    func testMergeIncrementalUpdateReplacesEncouragementSummaryTodoAndAppendsDetailsAsSeparateParagraphs() {
        let composer = DailyMarkdownComposer()
        let oldID = UUID()
        let encouragementID = UUID()
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
                            id: "daily-journal-encouragement",
                            text: "# You did a good job today\n\nKeep the steady pace.",
                            sourceEventIDs: [oldID]
                        ),
                        DailyStoryParagraph(
                            id: "daily-journal-summary",
                            text: "# Summary\n\n- Wrapped the first pass",
                            sourceEventIDs: [oldID]
                        ),
                        DailyStoryParagraph(
                            id: "daily-journal-details-0",
                            text: "# Details\n\n## Existing Thread\n\nShipped the first iteration.",
                            sourceEventIDs: [oldID]
                        ),
                        DailyStoryParagraph(
                            id: "daily-journal-todo",
                            text: "# To-do\n\n- [ ] Send recap",
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
              "encouragementToReplace": {
                "text": "You stayed steady once the feedback loop tightened.",
                "sourceEventIDs": ["\(encouragementID.uuidString)"]
              },
              "summaryBulletsToReplace": [
                { "text": "- Landed the follow-up review", "sourceEventIDs": ["\(newSummaryID.uuidString)"] }
              ],
              "detailBlocksToAppend": [
                { "text": "## Follow-up\\n\\nHandled the customer feedback loop.", "sourceEventIDs": ["\(newDetailID.uuidString)"] }
              ],
              "todoItemsToReplace": [
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
        XCTAssertEqual(paragraphs.count, 5)
        XCTAssertEqual(paragraphs[0].text, "# You did a good job today\n\nYou stayed steady once the feedback loop tightened.")
        XCTAssertEqual(paragraphs[1].text, "# Summary\n\n- Landed the follow-up review")
        XCTAssertEqual(paragraphs[2].text, "# Details\n\n## Existing Thread\n\nShipped the first iteration.")
        XCTAssertEqual(paragraphs[3].text, "## Follow-up\n\nHandled the customer feedback loop.")
        XCTAssertEqual(paragraphs[4].text, "# To-do\n\n- [ ] Queue the final handoff")
        XCTAssertEqual(paragraphs[0].sourceEventIDs, [encouragementID])
        XCTAssertEqual(paragraphs[1].sourceEventIDs, [newSummaryID])
        XCTAssertEqual(paragraphs[2].sourceEventIDs, [oldID])
        XCTAssertEqual(paragraphs[3].sourceEventIDs, [newDetailID])
        XCTAssertEqual(paragraphs[4].sourceEventIDs, [newTodoID])
        XCTAssertEqual(merged.provenance?.engineLabel, "Claude CLI")
    }

    func testMergeIncrementalUpdatePreservesExistingStandaloneDetailParagraphsAcrossRepeatedRefreshes() {
        let composer = DailyMarkdownComposer()
        let firstID = UUID()
        let secondID = UUID()
        let thirdID = UUID()
        let fourthID = UUID()
        let fifthID = UUID()
        let sixthID = UUID()

        let existingStory = DailyStory(
            dayKey: "2026-04-12",
            generatedAt: Date(timeIntervalSince1970: 1_775_000_000),
            sections: [
                DailyStorySection(
                    id: "daily-journal",
                    title: "",
                    paragraphs: [
                        DailyStoryParagraph(
                            id: "daily-journal-encouragement",
                            text: "# You did a good job today\n\nKeep the steady pace.",
                            sourceEventIDs: [firstID]
                        ),
                        DailyStoryParagraph(
                            id: "daily-journal-summary",
                            text: "# Summary\n\n- Wrapped the first pass",
                            sourceEventIDs: [firstID]
                        ),
                        DailyStoryParagraph(
                            id: "daily-journal-details-0",
                            text: "# Details\n\n## Existing Thread\n\nShipped the first iteration.",
                            sourceEventIDs: [firstID]
                        ),
                        DailyStoryParagraph(
                            id: "daily-journal-details-1",
                            text: "## Follow-up\n\nHandled the first feedback loop.",
                            sourceEventIDs: [secondID]
                        ),
                        DailyStoryParagraph(
                            id: "daily-journal-todo",
                            text: "# To-do\n\n- [ ] Send recap",
                            sourceEventIDs: [thirdID]
                        )
                    ]
                )
            ]
        )

        let update = composer.parseIncrementalUpdate(
            raw: """
            {
              "encouragementToReplace": {
                "text": "You kept the thread moving into the second pass.",
                "sourceEventIDs": ["\(fourthID.uuidString)"]
              },
              "summaryBulletsToReplace": [
                { "text": "- Closed the second review pass", "sourceEventIDs": ["\(fifthID.uuidString)"] }
              ],
              "detailBlocksToAppend": [
                { "text": "## Final polish\\n\\nQueued the last cleanup before handoff.", "sourceEventIDs": ["\(sixthID.uuidString)"] }
              ],
              "todoItemsToReplace": [
                { "text": "- [ ] Send the final handoff", "sourceEventIDs": ["\(sixthID.uuidString)"] }
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
                curatedEventCount: 6
            )
        )

        let paragraphs = merged.sections.flatMap(\.paragraphs)
        XCTAssertEqual(paragraphs.map(\.text), [
            "# You did a good job today\n\nYou kept the thread moving into the second pass.",
            "# Summary\n\n- Closed the second review pass",
            "# Details\n\n## Existing Thread\n\nShipped the first iteration.",
            "## Follow-up\n\nHandled the first feedback loop.",
            "## Final polish\n\nQueued the last cleanup before handoff.",
            "# To-do\n\n- [ ] Send the final handoff"
        ])
        XCTAssertEqual(paragraphs[2].sourceEventIDs, [firstID])
        XCTAssertEqual(paragraphs[3].sourceEventIDs, [secondID])
        XCTAssertEqual(paragraphs[4].sourceEventIDs, [sixthID])
    }

    func testMergeIncrementalUpdateUsesIncrementalUpdateContentForLanguageFallbackInsteadOfAllEvents() {
        let composer = DailyMarkdownComposer()
        let encouragementID = UUID()
        let summaryID = UUID()
        let detailID = UUID()
        let todoID = UUID()
        let englishEvent = EventRecord(
            id: UUID(),
            sourceType: .clipboard,
            sourceApp: "Notes",
            capturedAt: Date(timeIntervalSince1970: 1_775_000_000),
            dayKey: "2026-04-12",
            text: "English fallback signal that should not drive merge language.",
            auditText: nil,
            privacyAction: .keep,
            contentHash: "merge-language-fallback"
        )

        let update = composer.parseIncrementalUpdate(
            raw: """
            {
              "encouragementToReplace": {
                "text": "你把最后一轮也稳稳接住了。",
                "sourceEventIDs": ["\(encouragementID.uuidString)"]
              },
              "summaryBulletsToReplace": [
                { "text": "- 完成最后一轮确认", "sourceEventIDs": ["\(summaryID.uuidString)"] }
              ],
              "detailBlocksToAppend": [
                { "text": "## 收尾\\n\\n把最后的交付线索整理清楚。", "sourceEventIDs": ["\(detailID.uuidString)"] }
              ],
              "todoItemsToReplace": [
                { "text": "- [ ] 发出最终交接", "sourceEventIDs": ["\(todoID.uuidString)"] }
              ]
            }
            """
        )

        XCTAssertNotNil(update)

        let merged = composer.mergeIncrementalUpdate(
            dayKey: "2026-04-12",
            existingStory: DailyStory(dayKey: "2026-04-12", generatedAt: Date(), sections: []),
            update: update!,
            allEvents: [englishEvent],
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
        XCTAssertEqual(paragraphs[0].text, "# 你今天做得很棒\n\n你把最后一轮也稳稳接住了。")
        XCTAssertEqual(paragraphs[1].text, "# 今日总结\n\n- 完成最后一轮确认")
        XCTAssertEqual(paragraphs[2].text, "# 详情\n\n## 收尾\n\n把最后的交付线索整理清楚。")
        XCTAssertEqual(paragraphs[3].text, "# 待办事项\n\n- [ ] 发出最终交接")
    }

    func testMergeIncrementalUpdatePreservesMalformedLegacyDetailsBlockBeforeAppendingNewDetails() {
        let composer = DailyMarkdownComposer()
        let oldID = UUID()
        let newEncouragementID = UUID()
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
                            id: "daily-journal-encouragement",
                            text: "# You did a good job today\n\nKeep the steady pace.",
                            sourceEventIDs: [oldID]
                        ),
                        DailyStoryParagraph(
                            id: "daily-journal-summary",
                            text: "# Summary\n\n- Wrapped the first pass",
                            sourceEventIDs: [oldID]
                        ),
                        DailyStoryParagraph(
                            id: "daily-journal-weird",
                            text: """
                            Stray lead-in

                            # Details

                            Legacy thread that still needs to survive.
                            """,
                            sourceEventIDs: [oldID]
                        ),
                        DailyStoryParagraph(
                            id: "daily-journal-todo",
                            text: "# To-do\n\n- [ ] Send recap",
                            sourceEventIDs: [oldID]
                        )
                    ]
                )
            ]
        )

        let update = composer.parseIncrementalUpdate(
            raw: """
            {
              "encouragementToReplace": {
                "text": "You kept the old thread intact while moving the day forward.",
                "sourceEventIDs": ["\(newEncouragementID.uuidString)"]
              },
              "summaryBulletsToReplace": [
                { "text": "- Closed the second review pass", "sourceEventIDs": ["\(newSummaryID.uuidString)"] }
              ],
              "detailBlocksToAppend": [
                { "text": "## Follow-up\\n\\nAdded the final customer response.", "sourceEventIDs": ["\(newDetailID.uuidString)"] }
              ],
              "todoItemsToReplace": [
                { "text": "- [ ] Send the final handoff", "sourceEventIDs": ["\(newTodoID.uuidString)"] }
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
                curatedEventCount: 5
            )
        )

        let paragraphs = merged.sections.flatMap(\.paragraphs)
        XCTAssertEqual(paragraphs.map(\.text), [
            "# You did a good job today\n\nYou kept the old thread intact while moving the day forward.",
            "# Summary\n\n- Closed the second review pass",
            "# Details\n\nLegacy thread that still needs to survive.",
            "## Follow-up\n\nAdded the final customer response.",
            "# To-do\n\n- [ ] Send the final handoff"
        ])
        XCTAssertEqual(paragraphs[2].sourceEventIDs, [oldID])
        XCTAssertEqual(paragraphs[3].sourceEventIDs, [newDetailID])
    }

    func testNormalizeStorySplitsLegacyDetailsParagraphAndNarrowsSourcesByAppMatch() {
        let composer = DailyMarkdownComposer()
        let figmaID = UUID()
        let notionID = UUID()
        let terminalID = UUID()
        let dayKey = "2026-04-10"
        let events = [
            EventRecord(
                id: figmaID,
                sourceType: .clipboard,
                sourceApp: "Figma",
                capturedAt: Date(timeIntervalSince1970: 1_775_000_000),
                dayKey: dayKey,
                text: "Adjusted onboarding preview spacing.",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "legacy-details-figma"
            ),
            EventRecord(
                id: notionID,
                sourceType: .clipboard,
                sourceApp: "Notion",
                capturedAt: Date(timeIntervalSince1970: 1_775_000_100),
                dayKey: dayKey,
                text: "Compressed the demo into a cleaner narrative.",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "legacy-details-notion"
            ),
            EventRecord(
                id: terminalID,
                sourceType: .clipboard,
                sourceApp: "Terminal",
                capturedAt: Date(timeIntervalSince1970: 1_775_000_200),
                dayKey: dayKey,
                text: "Ran the final verification build.",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "legacy-details-terminal"
            ),
        ]
        let story = DailyStory(
            dayKey: dayKey,
            generatedAt: Date(timeIntervalSince1970: 1_775_000_500),
            sections: [
                DailyStorySection(
                    id: "daily-journal",
                    title: "",
                    paragraphs: [
                        DailyStoryParagraph(
                            id: "daily-journal-2",
                            text: """
                            # Details

                            ## Demo polish
                            In Figma I refined the onboarding preview.

                            ## Live narrative
                            Notion helped keep the walkthrough honest.

                            ## Recording readiness
                            Terminal gave me the final verification pass.
                            """,
                            sourceEventIDs: [figmaID, notionID, terminalID]
                        )
                    ]
                )
            ]
        )

        let normalized = composer.normalizeStory(story, events: events)
        let paragraphs = normalized.sections.flatMap(\.paragraphs)

        XCTAssertEqual(paragraphs.count, 3)
        XCTAssertEqual(paragraphs[0].id, "daily-journal-2-detail-0")
        XCTAssertTrue(paragraphs[0].text.contains("# Details"))
        XCTAssertEqual(paragraphs[0].sourceEventIDs, [figmaID])
        XCTAssertFalse(paragraphs[1].text.contains("# Details"))
        XCTAssertTrue(paragraphs[1].text.contains("## Live narrative"))
        XCTAssertEqual(paragraphs[1].sourceEventIDs, [notionID])
        XCTAssertEqual(paragraphs[2].sourceEventIDs, [terminalID])
    }

    func testNormalizeStoryKeepsOriginalSourcesWhenLegacyDetailsSubsectionHasNoMatch() {
        let composer = DailyMarkdownComposer()
        let firstID = UUID()
        let secondID = UUID()
        let dayKey = "2026-04-10"
        let events = [
            EventRecord(
                id: firstID,
                sourceType: .clipboard,
                sourceApp: "Figma",
                capturedAt: Date(timeIntervalSince1970: 1_775_000_000),
                dayKey: dayKey,
                text: "Adjusted the layout rhythm.",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "legacy-details-fallback-1"
            ),
            EventRecord(
                id: secondID,
                sourceType: .clipboard,
                sourceApp: "Terminal",
                capturedAt: Date(timeIntervalSince1970: 1_775_000_100),
                dayKey: dayKey,
                text: "Ran a final build.",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "legacy-details-fallback-2"
            ),
        ]
        let story = DailyStory(
            dayKey: dayKey,
            generatedAt: Date(timeIntervalSince1970: 1_775_000_500),
            sections: [
                DailyStorySection(
                    id: "daily-journal",
                    title: "",
                    paragraphs: [
                        DailyStoryParagraph(
                            id: "daily-journal-2",
                            text: """
                            # Details

                            ## Unmatched thread
                            This subsection never names a source app directly.

                            ## Recording readiness
                            Terminal gave me the final verification pass.
                            """,
                            sourceEventIDs: [firstID, secondID]
                        )
                    ]
                )
            ]
        )

        let normalized = composer.normalizeStory(story, events: events)
        let paragraphs = normalized.sections.flatMap(\.paragraphs)

        XCTAssertEqual(paragraphs.count, 2)
        XCTAssertEqual(paragraphs[0].sourceEventIDs, [firstID, secondID])
        XCTAssertEqual(paragraphs[1].sourceEventIDs, [secondID])
    }

    func testComposeKeepsSingleDetailsHeadingAfterNormalization() {
        let composer = DailyMarkdownComposer()
        let figmaID = UUID()
        let terminalID = UUID()
        let dayKey = "2026-04-10"
        let events = [
            EventRecord(
                id: figmaID,
                sourceType: .clipboard,
                sourceApp: "Figma",
                capturedAt: Date(timeIntervalSince1970: 1_775_000_000),
                dayKey: dayKey,
                text: "Refined the onboarding preview cues.",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "compose-details-1"
            ),
            EventRecord(
                id: terminalID,
                sourceType: .clipboard,
                sourceApp: "Terminal",
                capturedAt: Date(timeIntervalSince1970: 1_775_000_100),
                dayKey: dayKey,
                text: "Ran the final build verification.",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "compose-details-2"
            ),
        ]
        let story = DailyStory(
            dayKey: dayKey,
            generatedAt: Date(timeIntervalSince1970: 1_775_000_500),
            sections: [
                DailyStorySection(
                    id: "daily-journal",
                    title: "",
                    paragraphs: [
                        DailyStoryParagraph(
                            id: "daily-journal-2",
                            text: """
                            # Details

                            ## Demo polish
                            Figma helped refine the onboarding preview.

                            ## Recording readiness
                            Terminal handled the last verification pass.
                            """,
                            sourceEventIDs: [figmaID, terminalID]
                        )
                    ]
                )
            ]
        )

        let normalized = composer.normalizeStory(story, events: events)
        let markdown = composer.compose(dayKey: dayKey, events: events, story: normalized)

        XCTAssertEqual(markdown.components(separatedBy: "# Details").count - 1, 1, markdown)
        XCTAssertTrue(markdown.contains("## Demo polish"), markdown)
        XCTAssertTrue(markdown.contains("## Recording readiness"), markdown)
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
