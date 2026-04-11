import SwiftUI
import AppKit

struct DailyMarkdownView: View {
    let story: DailyStory?
    let selectedParagraphID: String?
    let dayKey: String?
    let refreshJob: DayRefreshJob?
    let isActive: Bool
    let onSelectParagraph: (String) -> Void
    let onFocusStory: () -> Void
    let onRefresh: () -> Void

    @State private var hoveredParagraphID: String?

    var body: some View {
        let presentation = DailyMarkdownPresentation(
            story: story,
            selectedParagraphID: selectedParagraphID
        )
        let refreshPresentation = DayRefreshProgressPresentation(refreshJob: refreshJob)

        Group {
            if presentation.showsEmptyState == false {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            // Date header row
                            HStack(alignment: .firstTextBaseline) {
                                Text(formattedDayKey)
                                    .font(.title2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                VStack(alignment: .trailing, spacing: 6) {
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

                                    if refreshPresentation.showsSteps {
                                        VStack(alignment: .trailing, spacing: 4) {
                                            ForEach(refreshPresentation.steps) { step in
                                                HStack(spacing: 6) {
                                                    Image(systemName: step.symbolName)
                                                        .font(.caption2)
                                                        .foregroundStyle(step.color)
                                                    Text(step.title)
                                                        .font(.caption)
                                                        .foregroundStyle(step.color)
                                                }
                                                .frame(maxWidth: 220, alignment: .trailing)
                                            }

                                            if let currentDetail = refreshPresentation.currentDetail {
                                                Text(currentDetail)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                                    .multilineTextAlignment(.trailing)
                                                    .frame(maxWidth: 220, alignment: .trailing)
                                            }
                                        }
                                    } else if let summaryText = refreshPresentation.summaryText {
                                        Text(summaryText)
                                            .font(.caption)
                                            .foregroundStyle(refreshPresentation.summaryColor)
                                            .multilineTextAlignment(.trailing)
                                            .frame(maxWidth: 220, alignment: .trailing)
                                    }
                                }
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
                                        .id(paragraph.id)
                                }
                            }
                            .padding(.horizontal, 28)
                            .padding(.top, 16)
                            .padding(.bottom, 24)
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .background(Color(nsColor: .textBackgroundColor))
                    .task(id: presentation.scrollRequest) {
                        scrollToParagraphIfNeeded(
                            presentation.scrollTargetParagraphID,
                            using: proxy
                        )
                    }
                }
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

    private func scrollToParagraphIfNeeded(
        _ paragraphID: String?,
        using proxy: ScrollViewProxy
    ) {
        guard let paragraphID else { return }

        withAnimation(.easeInOut(duration: 0.2)) {
            proxy.scrollTo(paragraphID, anchor: .center)
        }
    }

    private var isRefreshing: Bool {
        refreshJob?.inFlight == true
    }
}

struct DayRefreshProgressPresentation {
    enum StepState: Equatable {
        case completed
        case current
        case pending
    }

    struct Step: Identifiable, Equatable {
        let id: DayRefreshStage
        let title: String
        let state: StepState

        var symbolName: String {
            switch state {
            case .completed: "checkmark.circle.fill"
            case .current: "arrow.triangle.2.circlepath.circle.fill"
            case .pending: "circle"
            }
        }

        var color: Color {
            switch state {
            case .completed: .green
            case .current: .accentColor
            case .pending: .secondary.opacity(0.5)
            }
        }
    }

    private static let visibleStages: [DayRefreshStage] = [
        .syncingNotifications,
        .loadingEvents,
        .preparingStory,
        .generatingStory,
        .writingFiles,
    ]

    let steps: [Step]
    let currentDetail: String?
    let summaryText: String?
    let summaryColor: Color

    init(refreshJob: DayRefreshJob?) {
        guard let refreshJob else {
            steps = []
            currentDetail = nil
            summaryText = nil
            summaryColor = .secondary
            return
        }

        if refreshJob.inFlight {
            steps = Self.visibleStages.map { stage in
                let state: StepState
                if refreshJob.completedStages.contains(stage) {
                    state = .completed
                } else if refreshJob.stage == stage {
                    state = .current
                } else {
                    state = .pending
                }
                return Step(id: stage, title: stage.progressTitle, state: state)
            }
            currentDetail = refreshJob.detail
            summaryText = nil
            summaryColor = .secondary
        } else {
            steps = []
            currentDetail = nil
            summaryText = refreshJob.summary
            summaryColor = refreshJob.error == nil ? .secondary : .red
        }
    }

    var showsSteps: Bool {
        !steps.isEmpty
    }
}

private extension DayRefreshStage {
    var progressTitle: String {
        switch self {
        case .syncingNotifications:
            return "Sync notifications"
        case .loadingEvents:
            return "Load events"
        case .preparingStory:
            return "Prepare journal"
        case .generatingStory:
            return "Generate journal"
        case .writingFiles:
            return "Write files"
        case .completed, .failed:
            return detail
        }
    }
}

struct DailyMarkdownPresentation: Equatable {
    struct ScrollRequest: Equatable {
        let targetParagraphID: String?
        let dayKey: String?
        let paragraphIDs: [String]
    }

    let paragraphs: [DailyStoryParagraph]
    let selectedParagraphID: String?
    let scrollTargetParagraphID: String?
    let scrollRequest: ScrollRequest
    let storyHeading: String

    init(story: DailyStory?, selectedParagraphID: String? = nil) {
        paragraphs = story?.sections.flatMap(\.paragraphs) ?? []
        self.selectedParagraphID = selectedParagraphID
        if let selectedParagraphID,
           paragraphs.contains(where: { $0.id == selectedParagraphID }) {
            scrollTargetParagraphID = selectedParagraphID
        } else {
            scrollTargetParagraphID = paragraphs.first?.id
        }
        scrollRequest = ScrollRequest(
            targetParagraphID: scrollTargetParagraphID,
            dayKey: story?.dayKey,
            paragraphIDs: paragraphs.map(\.id)
        )
        storyHeading = Self.resolvedStoryHeading(for: story, paragraphs: paragraphs)
    }

    var showsEmptyState: Bool {
        paragraphs.isEmpty
    }

    var initialScrollParagraphID: String? {
        scrollTargetParagraphID
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

struct SourceBrand: Equatable {
    enum Identity: Equatable {
        case chatGPT
        case notes
        case mail
        case calendar
        case drafts
        case taio
        case teams
        case ghostty
        case weChat
        case feishu
        case claude
        case perplexity
        case notion
        case gitHub
        case slack
        case x
        case google
        case genericApp
    }

    enum Glyph: Equatable {
        enum Asset: String, Equatable {
            case chatGPT = "SourceLogoChatGPT"
            case notes = "SourceLogoNotes"
            case mail = "SourceLogoMail"
            case calendar = "SourceLogoCalendar"
            case drafts = "SourceLogoDrafts"
            case taio = "SourceLogoTaio"
            case teams = "SourceLogoTeams"
            case ghostty = "SourceLogoGhostty"
            case weChat = "SourceLogoWeChat"
            case feishu = "SourceLogoFeishu"
            case claude = "SourceLogoClaude"
            case perplexity = "SourceLogoPerplexity"
            case notion = "SourceLogoNotion"
            case gitHub = "SourceLogoGitHub"
            case slack = "SourceLogoSlack"
            case x = "SourceLogoX"
            case google = "SourceLogoGoogle"
        }

        enum Symbol: String, Equatable {
            case app = "app.fill"
        }

        case asset(Asset)
        case symbol(Symbol)
    }

    let identity: Identity
    let glyph: Glyph
    let fallbackSymbol: Glyph.Symbol

    var assetName: String? {
        guard case .asset(let asset) = glyph else { return nil }
        return asset.rawValue
    }

    var fallbackSymbolName: String {
        fallbackSymbol.rawValue
    }
}

enum SourceBrandResolver {
    static func resolve(appName: String) -> SourceBrand {
        let normalizedName = normalize(appName)

        switch normalizedName {
        case "chatgpt", "openai chatgpt":
            return SourceBrand(
                identity: .chatGPT,
                glyph: .asset(.chatGPT),
                fallbackSymbol: .app
            )
        case "notes":
            return SourceBrand(identity: .notes, glyph: .asset(.notes), fallbackSymbol: .app)
        case "mail", "邮件":
            return SourceBrand(identity: .mail, glyph: .asset(.mail), fallbackSymbol: .app)
        case "calendar":
            return SourceBrand(identity: .calendar, glyph: .asset(.calendar), fallbackSymbol: .app)
        case "drafts":
            return SourceBrand(identity: .drafts, glyph: .asset(.drafts), fallbackSymbol: .app)
        case "taio":
            return SourceBrand(identity: .taio, glyph: .asset(.taio), fallbackSymbol: .app)
        case "com.microsoft.teams2", "microsoft teams", "teams":
            return SourceBrand(identity: .teams, glyph: .asset(.teams), fallbackSymbol: .app)
        case "ghostty":
            return SourceBrand(identity: .ghostty, glyph: .asset(.ghostty), fallbackSymbol: .app)
        case "微信", "wechat", "weixin":
            return SourceBrand(identity: .weChat, glyph: .asset(.weChat), fallbackSymbol: .app)
        case "飞书", "feishu", "lark":
            return SourceBrand(identity: .feishu, glyph: .asset(.feishu), fallbackSymbol: .app)
        case "claude", "anthropic claude":
            return SourceBrand(identity: .claude, glyph: .asset(.claude), fallbackSymbol: .app)
        case "perplexity":
            return SourceBrand(identity: .perplexity, glyph: .asset(.perplexity), fallbackSymbol: .app)
        case "notion":
            return SourceBrand(identity: .notion, glyph: .asset(.notion), fallbackSymbol: .app)
        case "github":
            return SourceBrand(identity: .gitHub, glyph: .asset(.gitHub), fallbackSymbol: .app)
        case "slack":
            return SourceBrand(identity: .slack, glyph: .asset(.slack), fallbackSymbol: .app)
        case "x", "twitter":
            return SourceBrand(identity: .x, glyph: .asset(.x), fallbackSymbol: .app)
        case "google", "gmail", "google calendar", "google docs", "google drive":
            return SourceBrand(identity: .google, glyph: .asset(.google), fallbackSymbol: .app)
        default:
            return SourceBrand(
                identity: .genericApp,
                glyph: .symbol(.app),
                fallbackSymbol: .app
            )
        }
    }

    private static func normalize(_ appName: String) -> String {
        appName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .lowercased()
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

                            if selectedParagraph == nil {
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
                SourceBrandIcon(brand: SourceBrandResolver.resolve(appName: event.sourceApp))
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

private struct SourceBrandIcon: View {
    let brand: SourceBrand

    var body: some View {
        Group {
            switch brand.glyph {
            case .asset(let asset):
                if let image = NSImage(named: asset.rawValue) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    Image(systemName: brand.fallbackSymbol.rawValue)
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(.secondary)
                }
            case .symbol(let symbol):
                Image(systemName: symbol.rawValue)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 14, height: 14)
    }
}

private extension Character {
    var isChineseIdeograph: Bool {
        unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(scalar.value)
        }
    }
}
