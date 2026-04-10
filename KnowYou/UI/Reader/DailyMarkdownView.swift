import SwiftUI

struct DailyMarkdownView: View {
    let story: DailyStory?
    let selectedParagraphID: String?
    let dayKey: String?
    let isRefreshing: Bool
    let isActive: Bool
    let onSelectParagraph: (String) -> Void
    let onFocusStory: () -> Void
    let onRefresh: () -> Void

    @State private var hoveredParagraphID: String?

    var body: some View {
        let presentation = DailyMarkdownPresentation(story: story)

        Group {
            if presentation.showsEmptyState == false {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // Date header row
                        HStack(alignment: .firstTextBaseline) {
                            Text(formattedDayKey)
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button {
                                onRefresh()
                            } label: {
                                if isRefreshing {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Image(systemName: "arrow.clockwise")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(isRefreshing)
                            .help("Regenerate this day's journal")
                        }
                        .padding(.horizontal, 28)
                        .padding(.top, 24)
                        .padding(.bottom, 16)

                        Divider()
                            .padding(.horizontal, 28)

                        VStack(alignment: .leading, spacing: 0) {
                            Text(presentation.storyHeading)
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 14)
                                .padding(.top, 4)
                                .padding(.bottom, 16)

                            ForEach(presentation.paragraphs) { paragraph in
                                paragraphRow(paragraph)
                            }
                        }
                        .padding(.horizontal, 28)
                        .padding(.top, 16)
                        .padding(.bottom, 24)
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .background(Color(nsColor: .textBackgroundColor))
            } else {
                ContentUnavailableView("No Story Yet", systemImage: "text.book.closed")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func paragraphRow(_ paragraph: DailyStoryParagraph) -> some View {
        let isSelected = isActive && paragraph.id == selectedParagraphID
        let isHovered = hoveredParagraphID == paragraph.id

        Button {
            onFocusStory()
            onSelectParagraph(paragraph.id)
        } label: {
            HStack(alignment: .top, spacing: 0) {
                // Left accent bar (only when selected)
                Rectangle()
                    .fill(isSelected ? Color.accentColor : Color.clear)
                    .frame(width: 2)
                    .padding(.vertical, 4)

                MarkdownParagraphContent(markdown: paragraph.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
            }
            .background(
                isSelected
                    ? Color.accentColor.opacity(0.07)
                    : (isHovered ? Color.primary.opacity(0.04) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredParagraphID = hovering ? paragraph.id : nil
        }
    }

    private var formattedDayKey: String {
        guard let dayKey else { return "" }
        let parser = DateFormatter()
        parser.dateFormat = "yyyy-MM-dd"
        parser.locale = Locale(identifier: "en_US_POSIX")
        guard let date = parser.date(from: dayKey) else { return dayKey }

        let monthDay = DateFormatter()
        monthDay.dateFormat = "M月d日"
        let weekday = DateFormatter()
        weekday.dateFormat = "EEEE"
        weekday.locale = Locale(identifier: "en_US")
        return "\(monthDay.string(from: date)) · \(weekday.string(from: date))"
    }
}

struct DailyMarkdownPresentation: Equatable {
    let paragraphs: [DailyStoryParagraph]
    let storyHeading: String

    init(story: DailyStory?) {
        paragraphs = story?.sections.flatMap(\.paragraphs) ?? []
        storyHeading = Self.resolvedStoryHeading(for: story, paragraphs: paragraphs)
    }

    var showsEmptyState: Bool {
        paragraphs.isEmpty
    }

    private static func resolvedStoryHeading(
        for story: DailyStory?,
        paragraphs: [DailyStoryParagraph]
    ) -> String {
        let combinedText = paragraphs.map(\.text).joined(separator: "\n")
        if combinedText.contains(where: \.isChineseIdeograph) {
            return "今日小记"
        }

        if story?.dayKey.isEmpty == false {
            return "Story"
        }

        return "Story"
    }
}

enum DailyMarkdownRenderer {
    struct TaskItem: Equatable {
        let isCompleted: Bool
        let content: InlineContent
    }

    struct OrderedItem: Equatable {
        let index: Int
        let content: InlineContent
    }

    struct InlineContent: Equatable {
        let attributed: AttributedString?
        let plainText: String

        init(markdown: String) {
            plainText = markdown
            attributed = try? AttributedString(
                markdown: markdown,
                options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            )
        }
    }

    enum Block: Equatable {
        case heading(level: Int, content: InlineContent)
        case paragraph(InlineContent)
        case bulletList([InlineContent])
        case orderedList([OrderedItem])
        case taskList([TaskItem])
        case quote([InlineContent])
        case codeBlock(String)
    }

    static func blocks(from markdown: String) -> [Block] {
        let lines = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")

        var blocks: [Block] = []
        var index = 0

        while index < lines.count {
            let rawLine = lines[index]
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                index += 1
                continue
            }

            if trimmed.hasPrefix("```") {
                var codeLines: [String] = []
                index += 1
                while index < lines.count && lines[index].trimmingCharacters(in: .whitespaces) != "```" {
                    codeLines.append(lines[index])
                    index += 1
                }
                if index < lines.count {
                    index += 1
                }
                blocks.append(.codeBlock(codeLines.joined(separator: "\n")))
                continue
            }

            if let heading = parseHeading(from: trimmed) {
                blocks.append(heading)
                index += 1
                continue
            }

            if let task = parseTaskItem(from: trimmed) {
                var items = [task]
                index += 1
                while index < lines.count, let nextTask = parseTaskItem(from: lines[index].trimmingCharacters(in: .whitespaces)) {
                    items.append(nextTask)
                    index += 1
                }
                blocks.append(.taskList(items))
                continue
            }

            if let bullet = parseBulletItem(from: trimmed) {
                var items = [bullet]
                index += 1
                while index < lines.count, let nextBullet = parseBulletItem(from: lines[index].trimmingCharacters(in: .whitespaces)) {
                    items.append(nextBullet)
                    index += 1
                }
                blocks.append(.bulletList(items))
                continue
            }

            if let ordered = parseOrderedItem(from: trimmed) {
                var items = [ordered]
                index += 1
                while index < lines.count, let nextOrdered = parseOrderedItem(from: lines[index].trimmingCharacters(in: .whitespaces)) {
                    items.append(nextOrdered)
                    index += 1
                }
                blocks.append(.orderedList(items))
                continue
            }

            if trimmed.hasPrefix(">") {
                var quotes = [InlineContent(markdown: String(trimmed.dropFirst().trimmingCharacters(in: .whitespaces)))]
                index += 1
                while index < lines.count {
                    let nextTrimmed = lines[index].trimmingCharacters(in: .whitespaces)
                    guard nextTrimmed.hasPrefix(">") else { break }
                    quotes.append(InlineContent(markdown: String(nextTrimmed.dropFirst().trimmingCharacters(in: .whitespaces))))
                    index += 1
                }
                blocks.append(.quote(quotes))
                continue
            }

            var paragraphLines = [trimmed]
            index += 1
            while index < lines.count {
                let nextTrimmed = lines[index].trimmingCharacters(in: .whitespaces)
                if nextTrimmed.isEmpty || startsNewBlock(nextTrimmed) {
                    break
                }
                paragraphLines.append(nextTrimmed)
                index += 1
            }
            blocks.append(.paragraph(InlineContent(markdown: paragraphLines.joined(separator: "\n"))))
        }

        return blocks
    }

    private static func startsNewBlock(_ line: String) -> Bool {
        parseHeading(from: line) != nil
            || parseTaskItem(from: line) != nil
            || parseBulletItem(from: line) != nil
            || parseOrderedItem(from: line) != nil
            || line.hasPrefix(">")
            || line.hasPrefix("```")
    }

    private static func parseHeading(from line: String) -> Block? {
        guard line.hasPrefix("#") else { return nil }
        let hashes = line.prefix(while: { $0 == "#" }).count
        guard hashes > 0, hashes <= 6 else { return nil }
        let text = line.dropFirst(hashes).trimmingCharacters(in: .whitespaces)
        guard text.isEmpty == false else { return nil }
        return .heading(level: hashes, content: InlineContent(markdown: text))
    }

    private static func parseBulletItem(from line: String) -> InlineContent? {
        guard line.hasPrefix("- ") || line.hasPrefix("* ") else { return nil }
        let content = String(line.dropFirst(2))
        guard content.isEmpty == false else { return nil }
        return InlineContent(markdown: content)
    }

    private static func parseTaskItem(from line: String) -> TaskItem? {
        guard line.hasPrefix("- [") || line.hasPrefix("* [") else { return nil }
        guard line.count >= 6 else { return nil }
        let marker = line[line.index(line.startIndex, offsetBy: 3)]
        guard marker == " " || marker == "x" || marker == "X" else { return nil }
        guard line[line.index(line.startIndex, offsetBy: 4)] == "]" else { return nil }
        let contentStart = line.index(line.startIndex, offsetBy: 6)
        let content = String(line[contentStart...])
        return TaskItem(isCompleted: marker == "x" || marker == "X", content: InlineContent(markdown: content))
    }

    private static func parseOrderedItem(from line: String) -> OrderedItem? {
        let digits = line.prefix(while: { $0.isNumber })
        guard digits.isEmpty == false else { return nil }
        let remainder = line.dropFirst(digits.count)
        guard remainder.hasPrefix(". ") else { return nil }
        let content = String(remainder.dropFirst(2))
        guard let index = Int(digits), content.isEmpty == false else { return nil }
        return OrderedItem(index: index, content: InlineContent(markdown: content))
    }
}

private struct MarkdownParagraphContent: View {
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(DailyMarkdownRenderer.blocks(from: markdown).enumerated()), id: \.offset) { _, block in
                MarkdownBlockView(block: block)
            }
        }
        .multilineTextAlignment(.leading)
        .textSelection(.enabled)
        .allowsHitTesting(false)
    }
}

private struct MarkdownBlockView: View {
    let block: DailyMarkdownRenderer.Block

    var body: some View {
        switch block {
        case .heading(let level, let content):
            inlineText(content)
                .font(headingFont(for: level))
                .fontWeight(.semibold)
                .padding(.top, level == 1 ? 10 : 4)
        case .paragraph(let content):
            inlineText(content)
                .font(.body)
                .lineSpacing(3)
        case .bulletList(let items):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 10) {
                        Text("\u{2022}")
                            .font(.body.weight(.semibold))
                            .padding(.top, 1)
                        inlineText(item)
                            .font(.body)
                            .lineSpacing(3)
                    }
                }
            }
        case .orderedList(let items):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(item.index).")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.secondary)
                        inlineText(item.content)
                            .font(.body)
                            .lineSpacing(3)
                    }
                }
            }
        case .taskList(let items):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: item.isCompleted ? "checkmark.square.fill" : "square")
                            .foregroundStyle(item.isCompleted ? Color.accentColor : Color.secondary)
                            .padding(.top, 2)
                        inlineText(item.content)
                            .font(.body)
                            .lineSpacing(3)
                    }
                }
            }
        case .quote(let items):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    inlineText(item)
                        .font(.body)
                        .italic()
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.leading, 14)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(Color.secondary.opacity(0.35))
                    .frame(width: 3)
            }
        case .codeBlock(let code):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(verbatim: code)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .background(Color.primary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    @ViewBuilder
    private func inlineText(_ content: DailyMarkdownRenderer.InlineContent) -> some View {
        if let attributed = content.attributed {
            Text(attributed)
        } else {
            Text(verbatim: content.plainText)
        }
    }

    private func headingFont(for level: Int) -> Font {
        switch level {
        case 1:
            return .title2
        case 2:
            return .title3
        case 3:
            return .headline
        default:
            return .body
        }
    }
}

struct StorySourceDetailView: View {
    let selectedParagraph: DailyStoryParagraph?
    let selectedEvents: [EventRecord]
    let allEvents: [EventRecord]
    @State private var showAllSources = false

    var body: some View {
        Group {
            if selectedParagraph != nil || !allEvents.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Sources")
                                .font(.title3.weight(.semibold))

                            if let selectedParagraph {
                                MarkdownParagraphContent(markdown: selectedParagraph.text)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Select a story paragraph to inspect the original source items.")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if selectedEvents.isEmpty {
                            Text("No linked sources for this paragraph.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(selectedEvents, id: \.id) { event in
                                    SourceEventCard(event: event)
                                }
                            }
                        }

                        DisclosureGroup(isExpanded: $showAllSources) {
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(allEvents, id: \.id) { event in
                                    SourceEventCard(event: event)
                                }
                            }
                            .padding(.top, 12)
                        } label: {
                            Text("View All Sources")
                                .font(.callout.weight(.medium))
                        }
                        .disabled(allEvents.isEmpty)
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 20)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .background(Color(nsColor: .controlBackgroundColor))
            } else {
                ContentUnavailableView("No Sources Loaded", systemImage: "tray")
            }
        }
    }
}

private struct SourceEventCard: View {
    let event: EventRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(timeText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text(event.sourceApp)
                    .font(.callout.weight(.semibold))
                Spacer(minLength: 8)
                Text(event.sourceType.rawValue.capitalized)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Text(event.text ?? event.auditText ?? "")
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var timeText: String {
        Self.formatter.string(from: event.capturedAt)
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

private extension Character {
    var isChineseIdeograph: Bool {
        unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(scalar.value)
        }
    }
}
