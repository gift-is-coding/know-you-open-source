import Foundation

struct DailyMarkdownComposer {
    private static let sectionTemplates: [(id: String, title: String)] = [
        ("daily-journal", ""),
    ]

    func compose(dayKey: String, events: [EventRecord], story: DailyStory) -> String {
        let storySections = story.sections
            .map { section in
                let paragraphTexts: [String] = section.paragraphs
                    .map { $0.text }
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                let paragraphs = paragraphTexts.joined(separator: "\n\n")
                guard !paragraphs.isEmpty else { return "_No story for this day_" }
                guard !section.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    return paragraphs
                }
                return "### " + section.title + "\n\n" + paragraphs
            }
            .joined(separator: "\n\n")
        let sourceLines = bulletList(
            for: events.map { event in
                "[\(Self.timeFormatter.string(from: event.capturedAt))] \(event.sourceApp) (\(event.sourceType.rawValue)): \(event.displayText)"
            }
        )
        return """
        # \(dayKey)

        ## Story

        \(storySections)

        ## Source Notes

        \(sourceLines)
        """
    }

    func fallbackStory(dayKey: String, events: [EventRecord]) -> DailyStory {
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
                    text: journalParagraphText(index: index, mainEvents: mainThreadEvents, group: group),
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
        let eventLines = events.enumerated().map { index, event in
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
        You are turning one day of raw computer context into a clean diary-style daily summary.

        Return strict JSON only. Do not use markdown fences.

        Required JSON shape:
        {
          "sections": [
            { "id": "daily-journal", "paragraphs": [{ "text": "...", "sourceEventIDs": ["uuid"] }] }
          ]
        }

        Rules:
        - Keep the single section id exactly as given.
        - Write this as a diary-style summary of what the user did today.
        - Use 2 to 4 short paragraphs in natural prose.
        - Do not use headings inside the paragraph text.
        - Do not use bullet lists.
        - Only reference sourceEventIDs that appear below.
        - Put all narrative paragraphs inside the single daily-journal section.
        - Preserve the user's language when possible.
        - Prefer summarizing the main work, decisions, communication, and notable side context instead of listing every fragment.

        Day: \(dayKey)
        Source events:
        \(eventLines)
        """
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

    private func bulletList(for items: [String]) -> String {
        let lines = items
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { "- \($0)" }

        return lines.isEmpty ? "_No entries_" : lines.joined(separator: "\n")
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

    private func journalParagraphText(index: Int, mainEvents: [EventRecord], group: [EventRecord]) -> String {
        if index == 0 {
            let snippets = group.prefix(3).map { "\($0.sourceApp) \($0.storySnippet)" }.joined(separator: "; ")
            return "Today I mostly focused on \(snippets)."
        }

        let theme = group.first?.fallbackTheme ?? .context
        let snippets = group.prefix(3).map { "\($0.sourceApp) \($0.storySnippet)" }.joined(separator: "; ")
        let suffix = group.count > 3 ? " There were also \(group.count - 3) other related signals in the same thread." : ""

        switch theme {
        case .communication:
            return "There was also some coordination and conversation around \(snippets).\(suffix)"
        case .reference:
            return "Supporting references and materials that fed into the day included \(snippets).\(suffix)"
        case .verification:
            return "Part of the work involved verification and instrumentation, including \(snippets).\(suffix)"
        case .logistics:
            return "A smaller practical thread in the day involved \(snippets).\(suffix)"
        case .context:
            return "Other context that shaped the day included \(snippets).\(suffix)"
        }
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
}
