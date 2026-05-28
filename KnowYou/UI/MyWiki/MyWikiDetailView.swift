import SwiftUI

struct MyWikiDetailView: View {
    let entry: MyWikiEntry?
    var duplicateSuggestionCount: Int = 0
    var isSyncing = false
    var onEdit: (MyWikiEntry) -> Void = { _ in }
    var onOrganizeJournals: () -> Void = {}
    var onFindDuplicates: () -> Void = {}
    var onManageSources: () -> Void = {}
    var onUseInAgents: () -> Void = {}
    var onRevealWikiFolder: () -> Void = {}
    var onShowStatus: () -> Void = {}
    var onOpenSource: (String) -> Void = { _ in }
    var onOpenRelated: (String) -> Void = { _ in }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                toolbar

                if let entry {
                    entryHeader(entry)
                    contentGrid(entry)
                } else {
                    emptyState
                }
            }
            .padding(32)
            .frame(maxWidth: 1040, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(MyWikiTheme.contentBackground)
    }

    private var toolbar: some View {
        HStack {
            Text(entry.map { "\($0.category.displayTitle) / \($0.title)" } ?? "My Wiki")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            Spacer()

            Menu("More") {
                Button(isSyncing ? "Updating My Wiki..." : "Update My Wiki", action: onOrganizeJournals)
                    .disabled(isSyncing)
                Button(MyWikiSourceLibraryEntryPolicy.manageButtonTitle, action: onManageSources)
                Button("Use My Wiki in Agents", action: onUseInAgents)
                Divider()
                Button("Find duplicates", action: onFindDuplicates)
                Button("Reveal Wiki Folder", action: onRevealWikiFolder)
                Button("Wiki Status", action: onShowStatus)
            }
            .menuStyle(.button)

            if let entry {
                Button("Edit") {
                    onEdit(entry)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func entryHeader(_ entry: MyWikiEntry) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("\(entry.category.singularTitle) · \(entry.mentions.count) mentions · \(entry.sourceNames.count) sources\(entry.confidence.isEmpty ? "" : " · \(entry.confidence) confidence")")
                .font(.system(size: 12, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(Color(red: 0.56, green: 0.76, blue: 1))
                .textCase(.uppercase)

            Text(entry.title)
                .font(.system(size: 42, weight: .semibold))

            Text(entry.summary.isEmpty ? "No summary yet." : entry.summary)
                .font(.system(size: 18))
                .foregroundStyle(.primary)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)

            if entry.aliases.isEmpty == false {
                FlowLayout(spacing: 8) {
                    ForEach(entry.aliases, id: \.self) { alias in
                        Text("Also known as: \(alias)")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .frame(height: 28)
                            .background(Capsule().fill(MyWikiTheme.controlBackground))
                    }
                }
            }
        }
        .padding(.bottom, 20)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(MyWikiTheme.border)
                .frame(height: 1)
        }
    }

    private func contentGrid(_ entry: MyWikiEntry) -> some View {
        let presentation = MyWikiDetailPresentation(entry: entry)

        return VStack(alignment: .leading, spacing: 16) {
            if MyWikiDetailLayoutPolicy.showsStandaloneSummaryCard {
                detailCard("Summary") {
                    Text(entry.summary.isEmpty ? "No summary yet." : entry.summary)
                        .detailBodyStyle()
                }
            }

            if entry.mentions.isEmpty == false {
                detailCard("Recent Mentions") {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(entry.mentions, id: \.day) { mention in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(mention.day)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Color(red: 0.56, green: 0.76, blue: 1))
                                Text(mention.text)
                                    .detailBodyStyle()
                            }
                        }
                    }
                }
            }

            if entry.related.isEmpty == false {
                detailCard("Related") {
                    FlowLayout(spacing: 8) {
                        ForEach(entry.related, id: \.self) { related in
                            Button {
                                onOpenRelated(related)
                            } label: {
                                Text(related)
                                    .font(.system(size: 12))
                                    .padding(.horizontal, 10)
                                    .frame(height: 28)
                                    .background(Capsule().fill(MyWikiTheme.controlBackground))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            if MyWikiDetailMaintenancePolicy.showsDuplicateSuggestionCard(
                duplicateSuggestionCount: duplicateSuggestionCount
            ) {
                detailCard("Duplicate Suggestions") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(duplicateSuggestionCount) possible duplicate group(s) found.")
                            .detailBodyStyle()
                        Button("Review duplicates", action: onFindDuplicates)
                    }
                }
            }

            if presentation.showsMarkdownPage {
                detailCard("Page") {
                    MyWikiMarkdownBodyView(markdown: presentation.markdownText)
                    if presentation.isMarkdownTruncated {
                        Text("Page preview truncated.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            detailCard("Sources") {
                sourceList(entry)
            }
        }
    }

    @ViewBuilder
    private func sourceList(_ entry: MyWikiEntry) -> some View {
        if entry.sourceNames.isEmpty {
            Text("No sources yet.")
                .detailBodyStyle()
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(entry.sourceNames, id: \.self) { sourceName in
                    Button {
                        onOpenSource(sourceName)
                    } label: {
                        Label(sourceName, systemImage: "doc.plaintext")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                }
            }
        }
    }

    private func detailCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(MyWikiTheme.cardBackground)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(MyWikiTheme.border, lineWidth: 1))
        )
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Select a My Wiki item", systemImage: "sidebar.right")
                .font(.headline)
            Text(MyWikiUserFacingCopy.detailPlaceholder)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
        .padding(.top, 80)
    }
}

private struct MyWikiMarkdownBodyView: View {
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(DailyMarkdownRenderer.blocks(from: markdown).enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .multilineTextAlignment(.leading)
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func blockView(_ block: DailyMarkdownRenderer.Block) -> some View {
        switch block {
        case .heading(let level, let content):
            inlineText(content)
                .font(headingFont(for: level))
                .fontWeight(.semibold)
                .padding(.top, level == 1 ? 8 : 4)
        case .paragraph(let content):
            inlineText(content)
                .font(.system(size: 16))
                .lineSpacing(4)
        case .bulletList(let items):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 10) {
                        Text("\u{2022}")
                            .font(.system(size: 16, weight: .semibold))
                            .padding(.top, 1)
                        inlineText(item)
                            .font(.system(size: 16))
                            .lineSpacing(4)
                    }
                }
            }
        case .orderedList(let items):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(item.index).")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.secondary)
                        inlineText(item.content)
                            .font(.system(size: 16))
                            .lineSpacing(4)
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
                            .font(.system(size: 16))
                            .lineSpacing(4)
                    }
                }
            }
        case .quote(let items):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    inlineText(item)
                        .font(.system(size: 16))
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
                    .font(.system(size: 13, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .background(Color.primary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
            return .system(size: 26, weight: .semibold)
        case 2:
            return .system(size: 21, weight: .semibold)
        case 3:
            return .system(size: 17, weight: .semibold)
        default:
            return .system(size: 16, weight: .semibold)
        }
    }
}

enum MyWikiDetailMoreMenuPolicy {
    static let includesSourceLibrary = true
    static let includesAgentContext = true
}

private extension Text {
    func detailBodyStyle() -> some View {
        self
            .font(.system(size: 15))
            .foregroundStyle(.secondary)
            .lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct FlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(for: subviews, proposalWidth: proposal.width ?? 600)
        return CGSize(
            width: proposal.width ?? rows.map(\.width).max() ?? 0,
            height: rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(rows.count - 1, 0))
        )
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = rows(for: subviews, proposalWidth: bounds.width)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for item in row.items {
                item.subview.place(
                    at: CGPoint(x: x, y: y),
                    proposal: ProposedViewSize(item.size)
                )
                x += item.size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private func rows(for subviews: Subviews, proposalWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if current.items.isEmpty == false && current.width + spacing + size.width > proposalWidth {
                rows.append(current)
                current = Row()
            }
            current.append(subview: subview, size: size, spacing: spacing)
        }

        if current.items.isEmpty == false {
            rows.append(current)
        }
        return rows
    }

    private struct Row {
        var items: [(subview: LayoutSubview, size: CGSize)] = []
        var width: CGFloat = 0
        var height: CGFloat = 0

        mutating func append(subview: LayoutSubview, size: CGSize, spacing: CGFloat) {
            if items.isEmpty == false {
                width += spacing
            }
            items.append((subview, size))
            width += size.width
            height = max(height, size.height)
        }
    }
}
