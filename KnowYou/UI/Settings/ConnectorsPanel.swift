import SwiftUI

struct ConnectorPanelRow: Equatable, Identifiable {
    var id: String
    var title: String
    var direction: String
    var status: String
    var detail: String
}

struct ConnectorsPanelPresentation: Equatable {
    var exportRows: [ConnectorPanelRow]
    var importRows: [ConnectorPanelRow]
    var syncMemoryStatusMessage: String?
    var knowledgeImportStatusMessage: String?

    init(
        syncMemoryConfig: SyncMemoryConfig,
        knowledgeImportConfig: KnowledgeImportConfig,
        syncMemoryStatusMessage: String?,
        knowledgeImportStatusMessage: String?
    ) {
        exportRows = [
            ConnectorPanelRow(
                id: "obsidian-export",
                title: "Obsidian Export",
                direction: "Export",
                status: syncMemoryConfig.obsidian.isEnabled ? "Ready" : "Disabled",
                detail: Self.detail(for: syncMemoryConfig.obsidian.resolvedPath)
            ),
            ConnectorPanelRow(
                id: "openclaw-export",
                title: "OpenClaw Export",
                direction: "Export",
                status: syncMemoryConfig.openClaw.isEnabled ? "Ready" : "Disabled",
                detail: Self.detail(for: syncMemoryConfig.openClaw.resolvedPath)
            ),
        ]
        importRows = knowledgeImportConfig.connectorInstances.map { instance in
            ConnectorPanelRow(
                id: instance.id,
                title: instance.displayName,
                direction: "Import",
                status: instance.isEnabled ? "Ready" : "Disabled",
                detail: Self.detail(for: instance.sourcePath ?? instance.accountID ?? instance.workspaceID)
            )
        }
        self.syncMemoryStatusMessage = syncMemoryStatusMessage
        self.knowledgeImportStatusMessage = knowledgeImportStatusMessage
    }

    private static func detail(for value: String?) -> String {
        guard let value, value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return "Not connected"
        }
        return value
    }
}

struct ConnectorsPanel: View {
    let presentation: ConnectorsPanelPresentation
    let onExportNow: () -> Void
    let onImportNow: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Connectors")
                    .font(.title3.weight(.semibold))
                Text("Manage daily memory exports and local-first knowledge imports.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            connectorSection(
                title: "Daily Memory Export",
                rows: presentation.exportRows,
                statusMessage: presentation.syncMemoryStatusMessage,
                actionTitle: "Export Now",
                action: onExportNow
            )

            connectorSection(
                title: "Knowledge Imports",
                rows: presentation.importRows,
                statusMessage: presentation.knowledgeImportStatusMessage,
                actionTitle: "Import Now",
                action: onImportNow
            )

            HStack {
                Spacer()
                Button("Close", action: onClose)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 560, minHeight: 430)
    }

    private func connectorSection(
        title: String,
        rows: [ConnectorPanelRow],
        statusMessage: String?,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Button(actionTitle, action: action)
            }

            if rows.isEmpty {
                emptyRow
            } else {
                ForEach(rows) { row in
                    connectorRow(row)
                }
            }

            if let statusMessage, statusMessage.isEmpty == false {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var emptyRow: some View {
        Text("No connectors configured")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func connectorRow(_ row: ConnectorPanelRow) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(row.title)
                    .font(.body.weight(.semibold))
                Text(row.detail)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }

            Spacer(minLength: 12)

            Text(row.direction)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(row.status)
                .font(.caption.weight(.semibold))
                .foregroundStyle(row.status == "Ready" ? .green : .secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
