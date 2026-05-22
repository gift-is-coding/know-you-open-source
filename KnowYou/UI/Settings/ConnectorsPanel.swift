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
    @Binding var isAutoImportEnabled: Bool
    @Binding var dailyImportTime: Date
    let onChooseObsidianExport: () -> Void
    let onChooseOpenClawExport: () -> Void
    let onOpenObsidianExport: () -> Void
    let onOpenOpenClawExport: () -> Void
    let onAddLocalFolderImport: () -> Void
    let onAddObsidianImport: () -> Void
    let onAddAPIImportConnector: (KnowledgeConnectorID, String, String?, String?, String) -> Void
    let onSetImportConnectorEnabled: (String, Bool) -> Void
    let onDeleteImportConnector: (String) -> Void
    let onExportNow: () -> Void
    let onImportNow: () -> Void
    let onClose: () -> Void

    @State private var apiConnectorID: KnowledgeConnectorID = .feishuImport
    @State private var apiDisplayName = ""
    @State private var apiSource = ""
    @State private var apiAccount = ""
    @State private var apiBearerToken = ""
    @State private var isShowingAPIConnectorForm = false

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
                action: onExportNow,
                rowActions: exportRowActions
            )

            importSection

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
        action: @escaping () -> Void,
        @ViewBuilder rowActions: @escaping (ConnectorPanelRow) -> some View = { _ in EmptyView() }
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
                    connectorRow(row) {
                        rowActions(row)
                    }
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

    private func connectorRow<Actions: View>(
        _ row: ConnectorPanelRow,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
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

            actions()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @ViewBuilder
    private func exportRowActions(_ row: ConnectorPanelRow) -> some View {
        let hasFolder = row.detail != "Not connected"
        if row.id == "obsidian-export" {
            Button(action: onChooseObsidianExport) {
                Label("Change", systemImage: "folder")
            }
            if hasFolder {
                Button(action: onOpenObsidianExport) {
                    Label("Open", systemImage: "arrow.up.forward.app")
                }
            }
        } else if row.id == "openclaw-export" {
            Button(action: onChooseOpenClawExport) {
                Label("Change", systemImage: "folder")
            }
            if hasFolder {
                Button(action: onOpenOpenClawExport) {
                    Label("Open", systemImage: "arrow.up.forward.app")
                }
            }
        }
    }

    private var importSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Knowledge Imports")
                    .font(.headline)
                Spacer()
                Button("Import Now", action: onImportNow)
            }

            HStack(spacing: 12) {
                Button(action: onAddLocalFolderImport) {
                    Label("Add Folder", systemImage: "folder.badge.plus")
                }
                Button(action: onAddObsidianImport) {
                    Label("Add Obsidian", systemImage: "square.stack.3d.up")
                }
                Button {
                    isShowingAPIConnectorForm.toggle()
                } label: {
                    Label("Add API", systemImage: "network")
                }
            }

            if isShowingAPIConnectorForm {
                apiConnectorForm
            }

            HStack {
                Toggle("Daily Import", isOn: $isAutoImportEnabled)
                DatePicker(
                    "Import Time",
                    selection: $dailyImportTime,
                    displayedComponents: .hourAndMinute
                )
                .disabled(!isAutoImportEnabled)
            }

            if presentation.importRows.isEmpty {
                emptyRow
            } else {
                ForEach(presentation.importRows) { row in
                    connectorRow(row) {
                        Toggle(
                            "",
                            isOn: Binding(
                                get: { row.status == "Ready" },
                                set: { onSetImportConnectorEnabled(row.id, $0) }
                            )
                        )
                        .labelsHidden()

                        Button(role: .destructive) {
                            onDeleteImportConnector(row.id)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }

            if let statusMessage = presentation.knowledgeImportStatusMessage, statusMessage.isEmpty == false {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var apiConnectorForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Type", selection: $apiConnectorID) {
                Text("Feishu / Lark").tag(KnowledgeConnectorID.feishuImport)
                Text("Notion").tag(KnowledgeConnectorID.notionImport)
                Text("Google Drive").tag(KnowledgeConnectorID.googleDriveImport)
            }
            .pickerStyle(.segmented)

            TextField("Display Name", text: $apiDisplayName)

            if apiConnectorID == .feishuImport {
                TextField("Document Token", text: $apiSource)
            } else {
                TextField("Account or Workspace", text: $apiAccount)
            }

            SecureField("Bearer Token", text: $apiBearerToken)

            HStack {
                Spacer()
                Button("Add") {
                    onAddAPIImportConnector(
                        apiConnectorID,
                        apiDisplayName,
                        apiConnectorID == .feishuImport ? apiSource : nil,
                        apiConnectorID == .feishuImport ? nil : apiAccount,
                        apiBearerToken
                    )
                    resetAPIForm()
                }
                .disabled(!canSubmitAPIConnector)
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var canSubmitAPIConnector: Bool {
        let hasName = apiDisplayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        let hasToken = apiBearerToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        if apiConnectorID == .feishuImport {
            return hasName && hasToken && apiSource.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        }
        return hasName && hasToken && apiAccount.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    private func resetAPIForm() {
        apiDisplayName = ""
        apiSource = ""
        apiAccount = ""
        apiBearerToken = ""
        isShowingAPIConnectorForm = false
    }
}
