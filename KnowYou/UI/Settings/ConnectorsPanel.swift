import AppKit
import SwiftUI

struct ConnectorPanelRow: Equatable, Identifiable {
    var id: String
    var title: String
    var direction: String
    var status: String
    var detail: String
}

struct AddSourceCardPresentation: Equatable, Identifiable {
    var id: String
    var title: String
    var status: String
    var detail: String
    var systemImage: String
    var brandAssetName: String?
    var primaryActionTitle: String
    var isPrimaryActionEnabled: Bool
    var localDirectory: String?
    var connectorID: KnowledgeConnectorID?
    var connectorInstanceID: String?
}

enum ExternalSourcePromptFrequency: String, CaseIterable, Identifiable, Equatable {
    case daily
    case weekly

    var id: String { rawValue }
}

struct ExternalSourcePromptPresentation: Equatable {
    var connectorID: KnowledgeConnectorID
    var frequency: ExternalSourcePromptFrequency
    var importTime: Date
    var scopeDescription: String
    var externalSourcesRootURL: URL

    var platformName: String {
        switch connectorID {
        case .feishuImport:
            return "Feishu Docs"
        case .notionImport:
            return "Notion"
        case .googleDriveImport:
            return "Google Drive"
        case .localFolderImport:
            return "Local Folder"
        case .obsidianImport:
            return "Obsidian Vault"
        case .obsidianExport:
            return "Obsidian Export"
        case .openClawExport:
            return "OpenClaw Export"
        }
    }

    var directoryName: String {
        switch connectorID {
        case .feishuImport:
            return "feishu"
        case .notionImport:
            return "notion"
        case .googleDriveImport:
            return "google-drive"
        default:
            return connectorID.rawValue
        }
    }

    var outputDirectory: String {
        externalSourcesRootURL
            .appending(path: directoryName, directoryHint: .isDirectory)
            .path
    }

    var displayTime: String {
        Self.timeFormatter.string(from: importTime)
    }

    var prompt: String {
        let scope = scopeDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let scopeLine = scope.isEmpty ? "Use the platform content scope I provide when I run this prompt." : scope
        return """
        Create a \(frequency.rawValue) automation for \(platformName).

        Schedule:
        - Frequency: \(frequency.rawValue)
        - Local time: \(displayTime)

        Source scope:
        \(scopeLine)

        Destination:
        - Write Markdown or plain text files into:
          \(outputDirectory)
        - Create the directory if it does not exist.
        - Use stable folder paths and file names so later runs overwrite changed files instead of creating duplicates.
        - Convert supported remote documents to Markdown whenever possible.

        Authorization:
        - Handle any required platform sign-in inside Codex or Cloud Code.
        - Keep remote authorization state in that automation environment.
        - Do not ask the user to paste any remote credential into KnowYou.

        After the first run, KnowYou will scan this local directory and show the files as a linked source. KnowYou does not copy the files or store remote credentials.
        """
    }

    static func defaultExternalSourcesRootURL() -> URL {
        let applicationSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support")
        return applicationSupportURL
            .appending(path: "KnowYou", directoryHint: .isDirectory)
            .appending(path: "ExternalSources", directoryHint: .isDirectory)
    }

    static func defaultImportTime(calendar: Calendar = .current) -> Date {
        let now = Date()
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = 11
        components.minute = 0
        components.second = 0
        return calendar.date(from: components) ?? now
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

struct ConnectorsPanelPresentation: Equatable {
    var exportRows: [ConnectorPanelRow]
    var importRows: [ConnectorPanelRow]
    var importInstances: [KnowledgeConnectorInstanceConfig]
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
        importInstances = knowledgeImportConfig.connectorInstances
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

enum ConnectorsManagementSurface: Equatable {
    case connectorsSheet
    case otherSourceRoot
}

struct ConnectorsManagementPresentation: Equatable {
    var panelPresentation: ConnectorsPanelPresentation
    var surface: ConnectorsManagementSurface
    var externalSourcesRootURL: URL = ExternalSourcePromptPresentation.defaultExternalSourcesRootURL()

    var title: String {
        switch surface {
        case .connectorsSheet:
            return "Connectors"
        case .otherSourceRoot:
            return "Add Source"
        }
    }

    var subtitle: String {
        switch surface {
        case .connectorsSheet:
            return "Manage daily memory exports."
        case .otherSourceRoot:
            return "Manage all sources that feed your local Markdown library."
        }
    }

    var emptyImportMessage: String {
        switch surface {
        case .connectorsSheet:
            return "No connectors configured"
        case .otherSourceRoot:
            return "No sources connected yet. Add a connector and it will appear as a first-level item in the sidebar."
        }
    }

    var showsDailyMemoryExport: Bool {
        surface == .connectorsSheet
    }

    var showsAPIConnectorOption: Bool {
        false
    }

    var showsHeaderAddConnector: Bool {
        false
    }

    var showsConnectedSection: Bool {
        false
    }

    var usesModalPromptGeneration: Bool {
        true
    }

    var showsInlineExternalPrompt: Bool {
        false
    }

    var addSourceCards: [AddSourceCardPresentation] {
        [
            AddSourceCardPresentation(
                id: "my-diary",
                title: "My Diary",
                status: "Built-in",
                detail: "Daily notes generated by KnowYou stay in the same source tree.",
                systemImage: "book.closed",
                brandAssetName: nil,
                primaryActionTitle: "Open",
                isPrimaryActionEnabled: false,
                localDirectory: nil,
                connectorID: nil,
                connectorInstanceID: nil
            ),
            localSourceCard(
                id: "local-folder",
                title: "Local Folder",
                connectorID: .localFolderImport,
                defaultStatus: "Not connected",
                defaultDetail: "Link a folder on this Mac. Files stay in place and are not copied.",
                systemImage: "folder.badge.plus",
                addAction: "Add Folder"
            ),
            localSourceCard(
                id: "obsidian",
                title: "Obsidian Vault",
                connectorID: .obsidianImport,
                defaultStatus: "Detected",
                defaultDetail: "Use your existing Obsidian vault as a local Markdown source.",
                systemImage: "square.stack.3d.up",
                brandAssetName: "SourceLogoObsidian",
                addAction: "Use Vault"
            ),
            externalSourceCard(id: "feishu", title: "Feishu Docs", connectorID: .feishuImport, systemImage: "doc.richtext", brandAssetName: "SourceLogoFeishu"),
            externalSourceCard(id: "notion", title: "Notion", connectorID: .notionImport, systemImage: "doc.on.doc", brandAssetName: "SourceLogoNotion"),
            externalSourceCard(id: "google-drive", title: "Google Drive", connectorID: .googleDriveImport, systemImage: "externaldrive", brandAssetName: "SourceLogoGoogleDrive"),
        ]
    }

    private func localSourceCard(
        id: String,
        title: String,
        connectorID: KnowledgeConnectorID,
        defaultStatus: String,
        defaultDetail: String,
        systemImage: String,
        brandAssetName: String? = nil,
        addAction: String
    ) -> AddSourceCardPresentation {
        let instance = panelPresentation.importInstances.first { $0.connectorID == connectorID }
        if let instance {
            let sourcePath = Self.detail(for: instance.sourcePath ?? instance.accountID ?? instance.workspaceID)
            let detail = Self.referenceDetail(for: sourcePath)
            return AddSourceCardPresentation(
                id: id,
                title: title,
                status: instance.isEnabled ? "Linked" : "Disabled",
                detail: detail,
                systemImage: systemImage,
                brandAssetName: brandAssetName,
                primaryActionTitle: "Refresh",
                isPrimaryActionEnabled: instance.isEnabled,
                localDirectory: sourcePath == "Not connected" ? nil : sourcePath,
                connectorID: connectorID,
                connectorInstanceID: instance.id
            )
        }
        return AddSourceCardPresentation(
            id: id,
            title: title,
            status: defaultStatus,
            detail: defaultDetail,
            systemImage: systemImage,
            brandAssetName: brandAssetName,
            primaryActionTitle: addAction,
            isPrimaryActionEnabled: true,
            localDirectory: nil,
            connectorID: connectorID,
            connectorInstanceID: nil
        )
    }

    private func externalSourceCard(
        id: String,
        title: String,
        connectorID: KnowledgeConnectorID,
        systemImage: String,
        brandAssetName: String
    ) -> AddSourceCardPresentation {
        let instance = panelPresentation.importInstances.first { $0.connectorID == connectorID }
        let directory = externalSourcesRootURL
            .appending(path: ExternalSourcePromptPresentation(
                connectorID: connectorID,
                frequency: .daily,
                importTime: Date(timeIntervalSince1970: 0),
                scopeDescription: "",
                externalSourcesRootURL: externalSourcesRootURL
            ).directoryName, directoryHint: .isDirectory)
            .path
        if let instance {
            let detail = Self.detail(for: instance.sourcePath ?? instance.accountID ?? instance.workspaceID)
            let status = instance.isEnabled
                ? Self.localDirectoryStatus(for: instance.sourcePath)
                : "Disabled"
            return AddSourceCardPresentation(
                id: id,
                title: title,
                status: status,
                detail: detail,
                systemImage: systemImage,
                brandAssetName: brandAssetName,
                primaryActionTitle: status == "Needs first scan" ? "Generate Prompt" : "Refresh",
                isPrimaryActionEnabled: instance.isEnabled && status != "Error",
                localDirectory: detail == "Not connected" ? directory : detail,
                connectorID: connectorID,
                connectorInstanceID: instance.id
            )
        }
        return AddSourceCardPresentation(
            id: id,
            title: title,
            status: "Not connected",
            detail: "Generate a Codex or Cloud Code prompt that writes Markdown into a local folder KnowYou can scan.",
            systemImage: systemImage,
            brandAssetName: brandAssetName,
            primaryActionTitle: "Generate Prompt",
            isPrimaryActionEnabled: true,
            localDirectory: directory,
            connectorID: connectorID,
            connectorInstanceID: nil
        )
    }

    private static func detail(for value: String?) -> String {
        guard let value, value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return "Not connected"
        }
        return value
    }

    private static func referenceDetail(for sourcePath: String) -> String {
        guard sourcePath != "Not connected" else {
            return sourcePath
        }
        return "\(sourcePath) - Reference only; files are not copied."
    }

    private static func localDirectoryStatus(for path: String?) -> String {
        guard let path, path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return "Needs first scan"
        }
        let url = URL(fileURLWithPath: path, isDirectory: true)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
            return "Needs first scan"
        }
        guard isDirectory.boolValue else {
            return "Error"
        }
        do {
            guard let enumerator = FileManager.default.enumerator(
                at: url,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                return "Error"
            }
            for case let fileURL as URL in enumerator {
                let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
                guard values.isRegularFile == true else { continue }
                switch fileURL.pathExtension.lowercased() {
                case "md", "markdown", "txt":
                    return "Linked"
                default:
                    continue
                }
            }
            return "Needs first scan"
        } catch {
            return "Error"
        }
    }
}

struct ConnectorsManagementView: View {
    let managementPresentation: ConnectorsManagementPresentation
    @Binding var isAutoImportEnabled: Bool
    @Binding var dailyImportTime: Date
    let onChooseObsidianExport: () -> Void
    let onChooseOpenClawExport: () -> Void
    let onOpenObsidianExport: () -> Void
    let onOpenOpenClawExport: () -> Void
    let onAddLocalFolderImport: () -> Void
    let onAddObsidianImport: () -> Void
    let onAddExternalPromptSource: (KnowledgeConnectorID, String, String) -> Void
    let onSetImportConnectorEnabled: (String, Bool) -> Void
    let onDeleteImportConnector: (String) -> Void
    let onExportNow: () -> Void
    let onImportNow: () -> Void

    @State private var promptConnectorID: KnowledgeConnectorID = .feishuImport
    @State private var promptFrequency: ExternalSourcePromptFrequency = .daily
    @State private var promptImportTime = ExternalSourcePromptPresentation.defaultImportTime()
    @State private var promptScopeDescription = ""
    @State private var isShowingExternalPrompt = false

    init(
        managementPresentation: ConnectorsManagementPresentation,
        isAutoImportEnabled: Binding<Bool>,
        dailyImportTime: Binding<Date>,
        onChooseObsidianExport: @escaping () -> Void,
        onChooseOpenClawExport: @escaping () -> Void,
        onOpenObsidianExport: @escaping () -> Void,
        onOpenOpenClawExport: @escaping () -> Void,
        onAddLocalFolderImport: @escaping () -> Void,
        onAddObsidianImport: @escaping () -> Void,
        onAddExternalPromptSource: @escaping (KnowledgeConnectorID, String, String) -> Void = { _, _, _ in },
        onSetImportConnectorEnabled: @escaping (String, Bool) -> Void,
        onDeleteImportConnector: @escaping (String) -> Void,
        onExportNow: @escaping () -> Void,
        onImportNow: @escaping () -> Void
    ) {
        self.managementPresentation = managementPresentation
        _isAutoImportEnabled = isAutoImportEnabled
        _dailyImportTime = dailyImportTime
        self.onChooseObsidianExport = onChooseObsidianExport
        self.onChooseOpenClawExport = onChooseOpenClawExport
        self.onOpenObsidianExport = onOpenObsidianExport
        self.onOpenOpenClawExport = onOpenOpenClawExport
        self.onAddLocalFolderImport = onAddLocalFolderImport
        self.onAddObsidianImport = onAddObsidianImport
        self.onAddExternalPromptSource = onAddExternalPromptSource
        self.onSetImportConnectorEnabled = onSetImportConnectorEnabled
        self.onDeleteImportConnector = onDeleteImportConnector
        self.onExportNow = onExportNow
        self.onImportNow = onImportNow
    }

    private var presentation: ConnectorsPanelPresentation {
        managementPresentation.panelPresentation
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            managementHeader

            if managementPresentation.surface == .otherSourceRoot {
                addSourceRootSection
            }

            if managementPresentation.showsDailyMemoryExport {
                connectorSection(
                    title: "Daily Memory Export",
                    rows: presentation.exportRows,
                    statusMessage: presentation.syncMemoryStatusMessage,
                    actionTitle: "Export Now",
                    action: onExportNow,
                    rowActions: exportRowActions
                )
            }
        }
        .sheet(isPresented: $isShowingExternalPrompt) {
            externalPromptSheet
        }
    }

    private var managementHeader: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(managementPresentation.title)
                    .font(.title.weight(.semibold))
                Text(managementPresentation.subtitle)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 16)

            if managementPresentation.surface == .otherSourceRoot, managementPresentation.showsHeaderAddConnector {
                Menu {
                    Button(action: onAddLocalFolderImport) {
                        Label("Local Folder", systemImage: "folder.badge.plus")
                    }
                    Button(action: onAddObsidianImport) {
                        Label("Obsidian Vault", systemImage: "square.stack.3d.up")
                    }
                    Divider()
                    Button {
                        beginExternalPromptSetup(.feishuImport)
                    } label: {
                        Label("Feishu Docs", systemImage: "doc.richtext")
                    }
                    Button {
                        beginExternalPromptSetup(.notionImport)
                    } label: {
                        Label("Notion", systemImage: "doc.on.doc")
                    }
                    Button {
                        beginExternalPromptSetup(.googleDriveImport)
                    } label: {
                        Label("Google Drive", systemImage: "externaldrive")
                    }
                } label: {
                    Label("Add Connector", systemImage: "plus")
                }
            }
        }
    }

    private var addSourceRootSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Sources")
                .font(.title2.weight(.semibold))

            ForEach(managementPresentation.addSourceCards) { card in
                addSourceCard(card)
            }

            if presentation.importRows.isEmpty {
                Text("Connectors added here will appear as source items in the sidebar.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if let statusMessage = presentation.knowledgeImportStatusMessage, statusMessage.isEmpty == false {
                Text(statusMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func addSourceCard(_ card: AddSourceCardPresentation) -> some View {
        HStack(alignment: .center, spacing: 20) {
            sourceCardIcon(card)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(card.title)
                        .font(.title2.weight(.semibold))
                    statusPill(card.status)
                }
                Text(card.detail)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .layoutPriority(1)

            Spacer(minLength: 12)

            Button(card.primaryActionTitle) {
                performAddSourceCardAction(card)
            }
            .disabled(!card.isPrimaryActionEnabled)
            .controlSize(.large)
            .fixedSize()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @ViewBuilder
    private func sourceCardIcon(_ card: AddSourceCardPresentation) -> some View {
        if let brandAssetName = card.brandAssetName, let image = NSImage(named: brandAssetName) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: 40, height: 40)
        } else {
            Image(systemName: card.systemImage)
                .font(.system(size: 34, weight: .regular))
                .frame(width: 44, height: 44)
                .foregroundStyle(Color.accentColor)
        }
    }

    private func statusPill(_ status: String) -> some View {
        Text(status)
            .font(.callout.weight(.semibold))
            .foregroundStyle(statusForegroundColor(status))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(statusBackgroundColor(status))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func statusForegroundColor(_ status: String) -> Color {
        switch status {
        case "Built-in", "Detected", "Linked":
            return .green
        case "Needs first scan", "Add":
            return .orange
        case "Error":
            return .red
        default:
            return .secondary
        }
    }

    private func statusBackgroundColor(_ status: String) -> Color {
        switch status {
        case "Built-in", "Detected", "Linked":
            return Color.green.opacity(0.12)
        case "Needs first scan", "Add":
            return Color.orange.opacity(0.14)
        case "Error":
            return Color.red.opacity(0.12)
        default:
            return Color(nsColor: .quaternaryLabelColor).opacity(0.18)
        }
    }

    private func performAddSourceCardAction(_ card: AddSourceCardPresentation) {
        if card.primaryActionTitle == "Refresh" {
            onImportNow()
            return
        }

        switch card.id {
        case "local-folder":
            onAddLocalFolderImport()
        case "obsidian":
            onAddObsidianImport()
        case "feishu":
            beginExternalPromptSetup(.feishuImport)
        case "notion":
            beginExternalPromptSetup(.notionImport)
        case "google-drive":
            beginExternalPromptSetup(.googleDriveImport)
        default:
            break
        }
    }

    private var externalPromptSheet: some View {
        externalPromptSection
            .padding(24)
            .frame(minWidth: 760, idealWidth: 860, minHeight: 620, idealHeight: 700)
    }

    private var externalPromptSection: some View {
        let promptPresentation = ExternalSourcePromptPresentation(
            connectorID: promptConnectorID,
            frequency: promptFrequency,
            importTime: promptImportTime,
            scopeDescription: promptScopeDescription,
            externalSourcesRootURL: managementPresentation.externalSourcesRootURL
        )

        return VStack(alignment: .leading, spacing: 10) {
            Text("Generate Prompt")
                .font(.title2.weight(.semibold))

            Picker("Platform", selection: $promptConnectorID) {
                Text("Feishu Docs").tag(KnowledgeConnectorID.feishuImport)
                Text("Notion").tag(KnowledgeConnectorID.notionImport)
                Text("Google Drive").tag(KnowledgeConnectorID.googleDriveImport)
            }
            .pickerStyle(.segmented)

            Picker("Frequency", selection: $promptFrequency) {
                Text("Daily").tag(ExternalSourcePromptFrequency.daily)
                Text("Weekly").tag(ExternalSourcePromptFrequency.weekly)
            }
            .pickerStyle(.segmented)

            DatePicker("Update Time", selection: $promptImportTime, displayedComponents: .hourAndMinute)

            TextField("Remote scope, folder, workspace, page, or doc link", text: $promptScopeDescription)

            Text(promptPresentation.outputDirectory)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            TextEditor(text: .constant(promptPresentation.prompt))
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 300)
                .textSelection(.enabled)

            HStack {
                Button {
                    copyPromptAndCreateSource(promptPresentation)
                } label: {
                    Label("Copy Prompt", systemImage: "doc.on.doc")
                }

                Button("Cancel") {
                    isShowingExternalPrompt = false
                }

                Spacer()
            }
        }
        .padding(18)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func beginExternalPromptSetup(_ connectorID: KnowledgeConnectorID) {
        promptConnectorID = connectorID
        isShowingExternalPrompt = true
    }

    private func copyPromptAndCreateSource(_ presentation: ExternalSourcePromptPresentation) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(presentation.prompt, forType: .string)
        onAddExternalPromptSource(
            presentation.connectorID,
            presentation.platformName,
            presentation.outputDirectory
        )
        isShowingExternalPrompt = false
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
    let onSetImportConnectorEnabled: (String, Bool) -> Void
    let onDeleteImportConnector: (String) -> Void
    let onExportNow: () -> Void
    let onImportNow: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ConnectorsManagementView(
                managementPresentation: ConnectorsManagementPresentation(
                    panelPresentation: presentation,
                    surface: .connectorsSheet
                ),
                isAutoImportEnabled: $isAutoImportEnabled,
                dailyImportTime: $dailyImportTime,
                onChooseObsidianExport: onChooseObsidianExport,
                onChooseOpenClawExport: onChooseOpenClawExport,
                onOpenObsidianExport: onOpenObsidianExport,
                onOpenOpenClawExport: onOpenOpenClawExport,
                onAddLocalFolderImport: onAddLocalFolderImport,
                onAddObsidianImport: onAddObsidianImport,
                onSetImportConnectorEnabled: onSetImportConnectorEnabled,
                onDeleteImportConnector: onDeleteImportConnector,
                onExportNow: onExportNow,
                onImportNow: onImportNow
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
}
