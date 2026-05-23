import SwiftUI

struct KnowledgeSourceContentPresentation: Equatable {
    enum State: Equatable {
        case disabled
        case empty
        case documents
    }

    struct DocumentRow: Equatable, Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let isSelected: Bool
    }

    let title: String
    let state: State
    let emptyTitle: String
    let showsSyncNow: Bool
    let documentRows: [DocumentRow]
    let markdown: String?
    let statusMessage: String?

    init(
        connector: KnowledgeConnectorInstanceConfig,
        documents: [ImportedKnowledgeDocument],
        selectedDocumentID: String?,
        selectedMarkdown: String?,
        statusMessage: String?
    ) {
        title = connector.displayName
        documentRows = documents.map { document in
            DocumentRow(
                id: document.id,
                title: document.title,
                subtitle: Self.subtitle(for: document),
                isSelected: document.id == selectedDocumentID
            )
        }
        markdown = selectedMarkdown
        self.statusMessage = statusMessage

        if connector.isEnabled == false {
            state = .disabled
            emptyTitle = "Connector disabled"
            showsSyncNow = false
        } else if documents.isEmpty {
            state = .empty
            emptyTitle = "No documents yet"
            showsSyncNow = true
        } else {
            state = .documents
            emptyTitle = ""
            showsSyncNow = true
        }
    }

    private static func subtitle(for document: ImportedKnowledgeDocument) -> String {
        if let sourcePath = nonEmpty(document.sourcePath) {
            return sourcePath
        }
        if let remoteURL = nonEmpty(document.remoteURL) {
            return remoteURL
        }
        return document.mimeType
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return nil
        }
        return value
    }
}

struct KnowledgeSourceContentView: View {
    let presentation: KnowledgeSourceContentPresentation
    let onSyncNow: () -> Void
    let onSelectDocument: (String) -> Void
    let onConfigure: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if let statusMessage = presentation.statusMessage, statusMessage.isEmpty == false {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

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

            if presentation.showsSyncNow {
                Button("Sync Now", action: onSyncNow)
                    .accessibilityLabel("Sync knowledge source now")
            }

            Button("Configure", action: onConfigure)
                .accessibilityLabel("Configure knowledge source")
        }
    }

    private var emptyStateCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(presentation.emptyTitle)
                .font(.headline)

            Text("Synced documents are stored locally in KnowYou. Source files are not modified.")
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
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 16) {
                documentList
                    .frame(width: 260)

                Divider()

                markdownPreview
            }

            VStack(alignment: .leading, spacing: 12) {
                documentList
                    .frame(height: 180)

                Divider()

                markdownPreview
            }
        }
    }

    private var documentList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(presentation.documentRows) { row in
                    documentRow(row)
                }
            }
        }
    }

    private var markdownPreview: some View {
        ScrollView {
            Text(presentation.markdown ?? "Select a document to preview its markdown.")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(presentation.markdown == nil ? .secondary : .primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func documentRow(_ row: KnowledgeSourceContentPresentation.DocumentRow) -> some View {
        Button {
            onSelectDocument(row.id)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(row.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Text(row.subtitle)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(row.isSelected ? Color.accentColor.opacity(0.14) : Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(row.title)
    }
}
