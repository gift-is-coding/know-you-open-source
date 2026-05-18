import SwiftUI

struct MyWikiDetailView: View {
    let entry: MyWikiEntry?
    var duplicateSuggestionCount: Int = 0
    var isSyncing = false
    var onEdit: (MyWikiEntry) -> Void = { _ in }
    var onOrganizeJournals: () -> Void = {}
    var onFindDuplicates: () -> Void = {}
    var onManageSources: () -> Void = {}
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
                Button(isSyncing ? "Organizing Journals..." : "Organize Journals", action: onOrganizeJournals)
                    .disabled(isSyncing)
                Button("Source Library", action: onManageSources)
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
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 16) {
                detailCard("Summary") {
                    Text(entry.summary.isEmpty ? "No summary yet." : entry.summary)
                        .detailBodyStyle()
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
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)

            VStack(alignment: .leading, spacing: 16) {
                detailCard("Evidence Sources") {
                    sourceList(entry)
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
            }
            .frame(width: 310, alignment: .topLeading)
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
            Text("Summaries, people, projects, topics, patterns, and follow-ups will appear here.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
        .padding(.top, 80)
    }
}

enum MyWikiDetailMoreMenuPolicy {
    static let includesSourceLibrary = true
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

private struct FlowLayout: Layout {
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
