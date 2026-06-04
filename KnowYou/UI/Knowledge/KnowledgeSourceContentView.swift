import SwiftUI

struct KnowledgeSourceContentPresentation: Equatable {
    enum State: Equatable {
        case disabled
        case empty
        case documents
    }

    let title: String
    let state: State
    let emptyTitle: String
    let emptyMessage: String
    let showsDocumentList: Bool
    let showsRefreshAction: Bool
    let showsConfigureAction: Bool
    let markdown: String?
    let statusMessage: String?
    let searchQuery: String?

    init(
        connector: KnowledgeConnectorInstanceConfig,
        documents: [ImportedKnowledgeDocument],
        selectedDocumentID: String?,
        selectedMarkdown: String?,
        statusMessage: String?,
        searchQuery: String? = nil
    ) {
        title = connector.displayName
        let selectedDocumentExists = selectedDocumentID.map { selectedID in
            documents.contains { $0.id == selectedID }
        } ?? false
        markdown = selectedDocumentExists ? Self.markdownBodyWithoutFrontmatter(selectedMarkdown) : nil
        self.searchQuery = selectedDocumentExists
            ? Self.normalizedSearchQuery(searchQuery)
            : nil
        self.statusMessage = nil
        showsDocumentList = false
        showsRefreshAction = false
        showsConfigureAction = false

        if connector.isEnabled == false {
            state = .disabled
            emptyTitle = "Connector disabled"
            emptyMessage = "Enable this linked source to scan its local Markdown and text files."
        } else if markdown == nil {
            state = .empty
            emptyTitle = "No document selected"
            emptyMessage = "Choose a Markdown or text file from the source tree on the left."
        } else {
            state = .documents
            emptyTitle = ""
            emptyMessage = ""
        }
    }

    private static func normalizedSearchQuery(_ searchQuery: String?) -> String? {
        let normalized = searchQuery?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return normalized.isEmpty ? nil : normalized
    }

    private static func markdownBodyWithoutFrontmatter(_ markdown: String?) -> String? {
        guard let markdown else { return nil }
        let normalized = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        guard normalized.hasPrefix("---\n") else { return markdown }

        let searchStart = normalized.index(normalized.startIndex, offsetBy: 4)
        guard let closingRange = normalized[searchStart...].range(of: "\n---") else {
            return markdown
        }

        let afterClosingMarker = closingRange.upperBound
        let bodyStart: String.Index
        if afterClosingMarker < normalized.endIndex,
           normalized[afterClosingMarker] == "\n" {
            bodyStart = normalized.index(after: afterClosingMarker)
        } else {
            bodyStart = afterClosingMarker
        }

        return String(normalized[bodyStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct KnowledgeSourceContentView: View {
    let presentation: KnowledgeSourceContentPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            switch presentation.state {
            case .disabled, .empty:
                emptyStateCard
            case .documents:
                documentsBrowser
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(20)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(presentation.title)
                .font(.title3.weight(.semibold))
                .lineLimit(1)

            Spacer(minLength: 12)
        }
    }

    private var emptyStateCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(presentation.emptyTitle)
                .font(.headline)

            Text(presentation.emptyMessage)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var documentsBrowser: some View {
        markdownPreview
    }

    private var markdownPreview: some View {
        ScrollView {
            if let markdown = presentation.markdown {
                MarkdownPreviewContent(markdown: markdown, highlightQuery: presentation.searchQuery)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            } else {
                Text("Select a document to preview its markdown.")
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
