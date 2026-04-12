import Foundation

struct DailyMarkdownComposer {
    private static let sectionTemplates: [(id: String, title: String)] = [
        ("daily-journal", ""),
    ]
    private static let englishSourceNotesHeading = "## Source Notes"
    private static let chineseSourceNotesHeading = "## 线索来源"

    func compose(dayKey: String, events: [EventRecord], story: DailyStory) -> String {
        let language = dominantNarrativeLanguage(for: events)
        let storyHeading = storyHeading(for: events)
        let sourcesHeading = sourceNotesHeading(for: events)
        let storySections = story.sections
            .map { section in
                let paragraphTexts: [String] = section.paragraphs
                    .map { $0.text }
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                let paragraphs = paragraphTexts.joined(separator: "\n\n")
                guard !paragraphs.isEmpty else {
                    return language == .chinese ? "_今天还没有可读的小记_" : "_No story for this day_"
                }
                guard !section.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    return paragraphs
                }
                return "### " + section.title + "\n\n" + paragraphs
            }
            .joined(separator: "\n\n")
        let sourceLines = bulletList(
            for: events.map { event in
                "[\(Self.timeFormatter.string(from: event.capturedAt))] \(event.sourceApp) (\(event.sourceType.rawValue)): \(event.sanitizedSourceNoteText)"
            },
            emptyState: sourceNotesEmptyState(for: events)
        )
        return """
        # \(dayKey)

        \(storyHeading)

        \(storySections)

        ---

        \(sourcesHeading)

        \(sourceLines)
        """
    }

    func storyHeading(for events: [EventRecord]) -> String {
        dominantNarrativeLanguage(for: events) == .chinese ? "## 今日小记" : "## Story"
    }

    func sourceNotesHeading(for events: [EventRecord]) -> String {
        dominantNarrativeLanguage(for: events) == .chinese ? Self.chineseSourceNotesHeading : Self.englishSourceNotesHeading
    }

    func sourceNotesEmptyState(for events: [EventRecord]) -> String {
        dominantNarrativeLanguage(for: events) == .chinese ? "_暂无记录_" : "_No entries_"
    }

    func sourceNotesMarkdown(for events: [EventRecord]) -> String {
        let lines = events.map { event in
            "- [\(Self.timeFormatter.string(from: event.capturedAt))] \(event.sourceApp) (\(event.sourceType.rawValue)): \(event.sanitizedSourceNoteText)"
        }
        let body = lines.isEmpty ? sourceNotesEmptyState(for: events) : lines.joined(separator: "\n")
        return "\(sourceNotesHeading(for: events))\n\n\(body)"
    }

    func defaultStoryPrompt(dayKey: String, events: [EventRecord]) -> String {
        let language = dominantNarrativeLanguage(for: events)
        let journalHeadings = journalHeadings(for: language)
        let forbiddenHeading = language == .chinese ? "# 今日节奏" : "# Today's Rhythm"
        let eventLines = events.enumerated().map { _, event in
            let eventID = event.id.uuidString
            return """
            - id: \(eventID)
              time: \(Self.timeFormatter.string(from: event.capturedAt))
              app: \(event.sourceApp)
              source: \(event.sourceType.rawValue)
              text: \(event.displayText)
            """
        }.joined(separator: "\n")

        return """
        You are turning one day of raw computer context into a first-person diary entry written by the person who lived that day.

        Return strict JSON only. Do not use markdown fences.

        Required JSON shape:
        {
          "sections": [
            { "id": "daily-journal", "paragraphs": [{ "text": "...", "sourceEventIDs": ["uuid"] }] }
          ]
        }

        Rules:
        - Keep the single section id exactly as given.
        - Write in first person (I / 我). Never describe the user in third person. Write as if the user is writing their own diary.
        - Base the content strictly on the source events. Do not invent, infer, or embellish anything not directly supported by the events.
        - Follow the actual chronology at the thread level, but you may merge related events into the same workstream when it reads more naturally.
        - Determine whether the day is mainly English or mainly Chinese from the source events.
        - Write all diary prose and all diary headings in that same dominant language.
        - If the day is mainly English, use English for all diary prose and headings.
        - If the day is mainly Chinese, use Chinese for all diary prose and headings.
        - Do not mix Chinese and English in the diary except for app names or product names that already appear in the source material.
        - The final combined markdown across paragraph texts must render exactly these first-level headings, in this order:
          1. \(journalHeadings.encouragement)
          2. \(journalHeadings.summary)
          3. \(journalHeadings.details)
          4. \(journalHeadings.todo)
        - Do not emit any other first-level heading. In particular, do not include \(forbiddenHeading).
        - The "\(journalHeadings.encouragement)" section must contain exactly one sentence.
        - That sentence should read like a short inspirational quote for the person who lived the day, not a recap of tasks.
        - It should feel warm, distilled, and encouraging, but still loosely grounded in the overall pattern of the source events.
        - Do not retell the chronology or summarize what the person did step by step in this section.
        - Avoid app names, file names, branch names, URLs, tool instructions, and other concrete technical debris in this section unless absolutely necessary.
        - Do not add a quote author, do not use quotation marks, and do not format it as a citation.
        - Keep the wording in the same dominant language as the rest of the diary.
        - The "\(journalHeadings.summary)" section should use markdown bullet points.
        - The "\(journalHeadings.details)" section should use markdown second-level headings (##) for the main workstreams or threads of the day.
        - The "\(journalHeadings.todo)" section should use markdown task list items like - [ ].
        - Markdown headings, bullet lists, and task lists are allowed inside paragraph text and should be used deliberately.
        - Only reference sourceEventIDs that appear below.
        - Put all narrative paragraphs inside the single daily-journal section.
        - Organize the day by major threads or workstreams, not by raw fragment order.
        - Notifications, meetings, task reminders, and incoming messages are important when they changed the day's priorities or pushed work forward. Integrate them into the relevant thread instead of dumping them as noise.
        - Do not copy file paths, branch names, commit hashes, URLs, file names, or tool instructions into the diary unless they are absolutely central. Abstract technical debris into normal diary language.
        - Prefer summarizing the main work, coordination, decisions, and next steps instead of listing every fragment.
        - Use natural transitions between blocks, but never introduce facts, emotions, or context that are not present in the source events.

        Day: \(dayKey)
        Source events:
        \(eventLines)
        """
    }

    func defaultStoryPromptPreview(language: NarrativeLanguage) -> String {
        let seed = Self.previewSeedData(for: language)
        return defaultStoryPrompt(dayKey: seed.dayKey, events: seed.events)
    }

    func extractSourceNotesSection(from markdown: String) -> String? {
        let lines = markdown.components(separatedBy: .newlines)
        let headings = Self.sourceNotesSectionHeadings

        guard let startIndex = lines.firstIndex(where: { headings.contains($0.trimmingCharacters(in: .whitespaces)) }) else {
            return nil
        }

        let endIndex = lines[(startIndex + 1)...].firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces).hasPrefix("## ")
        }) ?? lines.endIndex

        let section = lines[startIndex..<endIndex].joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return section.isEmpty ? nil : section
    }

    static var sourceNotesSectionHeadings: [String] {
        [englishSourceNotesHeading, chineseSourceNotesHeading]
    }

    func fallbackStory(dayKey: String, events: [EventRecord]) -> DailyStory {
        let language = dominantNarrativeLanguage(for: events)
        let allEvents = events.sorted { $0.capturedAt < $1.capturedAt }
        let meaningfulWorkEvents = allEvents.filter { event in
            let theme = event.fallbackTheme
            return event.sourceType == .clipboard && theme != .reference && theme != .verification && theme != .logistics
        }
        let communicationCandidates = allEvents.filter { $0.sourceType == .notification || $0.fallbackTheme == .communication }

        var usedIDs = Set<UUID>()

        let mainThreadEvents = Array((meaningfulWorkEvents.isEmpty ? allEvents : meaningfulWorkEvents).prefix(2))
        usedIDs.formUnion(mainThreadEvents.map(\.id))

        let keyProgressEvents = Array(
            meaningfulWorkEvents
                .filter { !usedIDs.contains($0.id) }
                .prefix(3)
        )
        usedIDs.formUnion(keyProgressEvents.map(\.id))

        let communicationEvents = Array(
            communicationCandidates
                .filter { !usedIDs.contains($0.id) }
                .prefix(3)
        )
        usedIDs.formUnion(communicationEvents.map(\.id))

        let looseFragmentGroups = groupedLooseFragments(
            from: allEvents.filter { !usedIDs.contains($0.id) }
        )
        var paragraphs: [DailyStoryParagraph] = []
        let journalGroups = [mainThreadEvents, keyProgressEvents, communicationEvents]
            .filter { !$0.isEmpty } + looseFragmentGroups.filter { !$0.isEmpty }

        for (index, group) in journalGroups.enumerated() {
            paragraphs.append(
                DailyStoryParagraph(
                    id: "daily-journal-\(index)",
                    text: journalParagraphText(index: index, mainEvents: mainThreadEvents, group: group, language: language),
                    sourceEventIDs: group.map(\.id)
                )
            )
        }

        let sections = [
            DailyStorySection(
                id: "daily-journal",
                title: "",
                paragraphs: paragraphs
            )
        ]

        return DailyStory(dayKey: dayKey, generatedAt: Date(), sections: sections)
    }

    func storyPrompt(dayKey: String, events: [EventRecord]) -> String {
        defaultStoryPrompt(dayKey: dayKey, events: events)
    }

    func storyPrompt(dayKey: String, events: [EventRecord], globalOverride: String?) -> String {
        guard let globalOverride, !globalOverride.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return defaultStoryPrompt(dayKey: dayKey, events: events)
        }

        return globalOverride
    }

    private func journalHeadings(for language: NarrativeLanguage) -> (
        encouragement: String,
        summary: String,
        details: String,
        todo: String
    ) {
        switch language {
        case .english:
            return (
                encouragement: "# You did a good job today",
                summary: "# Summary",
                details: "# Details",
                todo: "# To-do"
            )
        case .chinese:
            return (
                encouragement: "# 你今天做得很棒",
                summary: "# 今日总结",
                details: "# 详情",
                todo: "# 待办事项"
            )
        }
    }

    private static func previewSeedData(for language: NarrativeLanguage) -> (dayKey: String, events: [EventRecord]) {
        let isChinese: Bool
        switch language {
        case .english:
            isChinese = false
        case .chinese:
            isChinese = true
        }

        if isChinese {
            return (
                dayKey: "preview-zh",
                events: [
                    EventRecord(
                        id: Self.previewUUID("11111111-1111-1111-1111-111111111111"),
                        sourceType: .clipboard,
                        sourceApp: "备忘录",
                        capturedAt: Date(timeIntervalSince1970: 1_775_000_000),
                        dayKey: "preview-zh",
                        text: "整理今天的日记预览内容",
                        auditText: nil,
                        privacyAction: .keep,
                        contentHash: "preview-zh-1"
                    ),
                    EventRecord(
                        id: Self.previewUUID("22222222-2222-2222-2222-222222222222"),
                        sourceType: .notification,
                        sourceApp: "日历",
                        capturedAt: Date(timeIntervalSince1970: 1_775_000_120),
                        dayKey: "preview-zh",
                        text: "下午确认日记生成预览",
                        auditText: nil,
                        privacyAction: .keep,
                        contentHash: "preview-zh-2"
                    )
                ]
            )
        }

        return (
            dayKey: "preview-en",
            events: [
                EventRecord(
                    id: Self.previewUUID("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"),
                    sourceType: .clipboard,
                    sourceApp: "Notes",
                    capturedAt: Date(timeIntervalSince1970: 1_775_000_000),
                    dayKey: "preview-en",
                    text: "Drafted a stable preview for the daily story prompt",
                    auditText: nil,
                    privacyAction: .keep,
                    contentHash: "preview-en-1"
                ),
                EventRecord(
                    id: Self.previewUUID("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"),
                    sourceType: .notification,
                    sourceApp: "Calendar",
                    capturedAt: Date(timeIntervalSince1970: 1_775_000_120),
                    dayKey: "preview-en",
                    text: "Preview check stayed on the canonical prompt path",
                    auditText: nil,
                    privacyAction: .keep,
                    contentHash: "preview-en-2"
                )
            ]
        )
    }

    private static func previewUUID(_ value: String) -> UUID {
        guard let uuid = UUID(uuidString: value) else {
            preconditionFailure("Invalid preview UUID: \(value)")
        }
        return uuid
    }

    func parseStory(dayKey: String, raw: String) -> DailyStory? {
        let cleaned = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = cleaned.data(using: .utf8) else { return nil }
        guard let payload = try? JSONDecoder().decode(GeneratedStoryPayload.self, from: data) else { return nil }

        let sections = Self.sectionTemplates.map { template in
            let matched = payload.sections.first(where: { $0.id == template.id })
            return DailyStorySection(
                id: template.id,
                title: template.title,
                paragraphs: matched?.paragraphs.enumerated().compactMap { index, paragraph in
                    let sourceIDs = paragraph.sourceEventIDs.compactMap(UUID.init(uuidString:))
                    guard !paragraph.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !sourceIDs.isEmpty else {
                        return nil
                    }
                    return DailyStoryParagraph(
                        id: "\(template.id)-\(index)",
                        text: paragraph.text.trimmingCharacters(in: .whitespacesAndNewlines),
                        sourceEventIDs: sourceIDs
                    )
                } ?? []
            )
        }

        return DailyStory(dayKey: dayKey, generatedAt: Date(), sections: sections)
    }

    private func bulletList(for items: [String], emptyState: String) -> String {
        let lines = items
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { "- \($0)" }

        return lines.isEmpty ? emptyState : lines.joined(separator: "\n")
    }

    private func makeParagraphs(for sectionID: String, events: [EventRecord]) -> [DailyStoryParagraph] {
        guard !events.isEmpty else { return [] }
        let groupedEvents: [[EventRecord]] = [events]

        return groupedEvents.enumerated().map { index, group in
            DailyStoryParagraph(
                id: "\(sectionID)-\(index)",
                text: paragraphText(for: sectionID, events: group),
                sourceEventIDs: group.map(\.id)
            )
        }
    }

    private func paragraphText(for sectionID: String, events: [EventRecord]) -> String {
        let snippets = events.map { event in
            "\(event.sourceApp) \(event.displayTextSentence)"
        }
        let joinedSnippets = snippets.joined(separator: " ")

        switch sectionID {
        case "daily-journal":
            return "Today centered on \(joinedSnippets)"
        default:
            return "Smaller fragments from the day included \(joinedSnippets)"
        }
    }

    private func journalParagraphText(
        index: Int,
        mainEvents: [EventRecord],
        group: [EventRecord],
        language: NarrativeLanguage
    ) -> String {
        if index == 0 {
            let snippets = group.prefix(3).map { "\($0.sourceApp) \($0.storySnippet)" }.joined(separator: "; ")
            switch language {
            case .english:
                return "The day mostly revolved around \(snippets), and that set the tone for the rest of it."
            case .chinese:
                return "这一天大致围绕着\(snippets)展开，也由此定下了后面的节奏。"
            }
        }

        let theme = group.first?.fallbackTheme ?? .context
        let separator = language == .chinese ? "；" : "; "
        let snippets = group.prefix(3).map { "\($0.sourceApp) \($0.storySnippet)" }.joined(separator: separator)
        let suffix: String = {
            guard group.count > 3 else { return "" }
            switch language {
            case .english:
                return " There were also \(group.count - 3) other related signals in the same thread."
            case .chinese:
                return " 同一条线里还有\(group.count - 3)个相关片段。"
            }
        }()

        switch theme {
        case .communication:
            switch language {
            case .english:
                return "Later on, a thread of coordination and conversation kept surfacing around \(snippets).\(suffix)"
            case .chinese:
                return "到后面，和\(snippets)有关的沟通与协同也反复出现。\(suffix)"
            }
        case .reference:
            switch language {
            case .english:
                return "I also kept pulling in supporting references and materials, including \(snippets).\(suffix)"
            case .chinese:
                return "我也一直在补充参考资料和线索，包括\(snippets)。\(suffix)"
            }
        case .verification:
            switch language {
            case .english:
                return "Part of the day turned into verification and instrumentation work, including \(snippets).\(suffix)"
            case .chinese:
                return "这一天里还有一部分时间落在验证和排查上，比如\(snippets)。\(suffix)"
            }
        case .logistics:
            switch language {
            case .english:
                return "There was a smaller practical thread running underneath it all, involving \(snippets).\(suffix)"
            case .chinese:
                return "除此之外，还夹着一条更偏事务性的线索，涉及\(snippets)。\(suffix)"
            }
        case .context:
            switch language {
            case .english:
                return "Other context quietly shaping the day included \(snippets).\(suffix)"
            case .chinese:
                return "还有一些背景片段也在悄悄影响这一天，比如\(snippets)。\(suffix)"
            }
        }
    }

    private func dominantNarrativeLanguage(for events: [EventRecord]) -> NarrativeLanguage {
        let chineseEventCount = events.filter(\.containsChineseText).count
        let latinEventCount = events.filter(\.containsLatinText).count
        return chineseEventCount > 0 && chineseEventCount >= latinEventCount ? .chinese : .english
    }

    private func groupedLooseFragments(from events: [EventRecord]) -> [[EventRecord]] {
        guard !events.isEmpty else { return [] }

        let orderedThemes: [FallbackTheme] = [.reference, .verification, .logistics, .communication, .context]
        let groupedByTheme = Dictionary(grouping: events) { $0.fallbackTheme }

        var groups = orderedThemes.compactMap { theme in
            groupedByTheme[theme]?.sorted { $0.capturedAt < $1.capturedAt }
        }.filter { !$0.isEmpty }

        while groups.count > 4, let last = groups.popLast() {
            groups[groups.count - 1].append(contentsOf: last)
        }

        return groups
    }

    private func looseFragmentParagraphText(for events: [EventRecord]) -> String {
        guard let leadEvent = events.first else { return "" }
        let theme = leadEvent.fallbackTheme
        let snippets = events.prefix(3).map { event in
            "\(event.sourceApp) \(event.storySnippet)"
        }.joined(separator: "; ")
        let suffix = events.count > 3 ? " and \(events.count - 3) other signals." : "."

        switch theme {
        case .reference:
            return "Reference links and lookups threaded through the day, including \(snippets)\(suffix)"
        case .verification:
            return "Verification and instrumentation signals showed up around \(snippets)\(suffix)"
        case .logistics:
            return "Logistics and life-admin fragments surfaced through \(snippets)\(suffix)"
        case .communication:
            return "Secondary conversations and coordination included \(snippets)\(suffix)"
        case .context:
            return "Other supporting context from the day included \(snippets)\(suffix)"
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

enum NarrativeLanguage {
    case english
    case chinese
}

private struct GeneratedStoryPayload: Decodable {
    let sections: [GeneratedStorySection]
}

private struct GeneratedStorySection: Decodable {
    let id: String
    let paragraphs: [GeneratedStoryParagraph]
}

private struct GeneratedStoryParagraph: Decodable {
    let text: String
    let sourceEventIDs: [String]
}

private enum FallbackTheme {
    case reference
    case verification
    case logistics
    case communication
    case context
}

private extension EventRecord {
    var displayText: String {
        let value = text ?? auditText ?? ""
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var sanitizedSourceNoteText: String {
        let flattened = displayText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        return flattened.isEmpty ? "empty item" : flattened
    }

    var displayTextSentence: String {
        let trimmed = displayText
        guard !trimmed.isEmpty else { return "recorded an empty item." }
        let preview = String(trimmed.prefix(180))
        return preview.hasSuffix(".") ? preview : "\(preview)."
    }

    var storySnippet: String {
        let trimmed = displayText
        guard !trimmed.isEmpty else { return "an empty item" }

        let firstLine = trimmed
            .components(separatedBy: .newlines)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? trimmed

        if firstLine.hasPrefix("http://") || firstLine.hasPrefix("https://") {
            return firstLine
        }

        return String(firstLine.prefix(90))
    }

    var fallbackTheme: FallbackTheme {
        let lowercasedText = displayText.lowercased()
        let lowercasedApp = sourceApp.lowercased()

        if lowercasedText.contains("knowyou-verify") || lowercasedText.contains("clipboard sentinel") || lowercasedText.contains("xcodebuild") || lowercasedText.contains("test succeeded") {
            return .verification
        }

        if lowercasedText.contains("http://") || lowercasedText.contains("https://") || lowercasedApp.contains("chrome") || lowercasedApp.contains("safari") || lowercasedApp.contains("finder") || lowercasedText.hasPrefix("/") {
            return .reference
        }

        if lowercasedApp.contains("wechat") || lowercasedApp.contains("feishu") || lowercasedApp.contains("messages") || lowercasedApp.contains("mail") || lowercasedApp.contains("calendar") || sourceType == .notification {
            return .communication
        }

        if lowercasedText.contains("ups") || lowercasedText.contains("仓库") || lowercasedText.contains("快递") || lowercasedText.contains("货物") || lowercasedText.contains("bela vista") || lowercasedText.contains("paulista") {
            return .logistics
        }

        return .context
    }

    var containsChineseText: Bool {
        displayText.contains { $0.isChineseIdeograph }
    }

    var containsLatinText: Bool {
        displayText.unicodeScalars.contains { CharacterSet.letters.contains($0) && $0.properties.isAlphabetic && $0.value < 128 }
    }
}

private extension Character {
    var isChineseIdeograph: Bool {
        unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(scalar.value)
        }
    }
}
