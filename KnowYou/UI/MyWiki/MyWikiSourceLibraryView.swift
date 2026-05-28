import SwiftUI
import AppKit
import UniformTypeIdentifiers

enum MyWikiSourceLibraryActionCopy {
    static let closeTitle = "Close"
    static let updateTitle = "Update My Wiki"
    static let updatingTitle = "Updating My Wiki..."
    static let manualUploadsTitle = "Manual Uploads"
    static let defaultStatusMessage = "Choose which sources are included in My Wiki."
    static let autosaveExplanation = "Selections are saved automatically. Update My Wiki processes included pending or changed sources."
    static let manualUploadsExplanation = "Drop or import Markdown/text files here. They are added to Manual Uploads and stay pending until you run Update My Wiki."

    static func importedStatusMessage(importedCount: Int) -> String {
        "Imported \(importedCount) source file(s) into Manual Uploads. Click Update My Wiki to process them."
    }
}

enum MyWikiSourceLibraryLayoutPolicy {
    static let minimumWidth: CGFloat = 980
    static let minimumHeight: CGFloat = 680
    static let preferredWidth: CGFloat = 1180
    static let preferredHeight: CGFloat = 780
    static let visibleFrameWidthRatio: CGFloat = 0.88
    static let visibleFrameHeightRatio: CGFloat = 0.88
    static let sourceTreeWidthRatio: CGFloat = 0.68
    static let minimumSourceTreeWidth: CGFloat = 480
    static let managementColumnWidth: CGFloat = 340
    static let usesScrollableManagementPane = true

    static func resolvedPresentationSize(forVisibleFrame visibleFrame: CGSize) -> CGSize {
        let widthLimit = visibleFrame.width * visibleFrameWidthRatio
        let heightLimit = visibleFrame.height * visibleFrameHeightRatio
        return CGSize(
            width: min(preferredWidth, widthLimit),
            height: min(preferredHeight, heightLimit)
        )
    }
}

struct MyWikiSourceLibraryView: View {
    let projectRoot: URL
    var sourceVault: URL?
    var importedDocuments: [ImportedKnowledgeDocument] = []
    var isUpdatingSources = false
    var onDidChange: () -> Void = {}
    var onUpdateSources: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var snapshot = MyWikiSourceCatalogStore.emptySnapshot()
    @State private var query = ""
    @State private var statusFilter: MyWikiSourceProcessingStatus?
    @State private var statusMessage = MyWikiSourceLibraryActionCopy.defaultStatusMessage
    @State private var isDropTargeted = false

    private var presentation: MyWikiSourceLibraryPresentation {
        MyWikiSourceLibraryPresentation(
            snapshot: snapshot,
            query: query,
            statusFilter: statusFilter
        )
    }

    private var visibleNodeRows: [SourceLibraryNodeRow] {
        flattenedRows(from: presentation.tree.children, depth: 0)
    }

    var body: some View {
        let presentationSize = MyWikiSourceLibraryLayoutPolicy.resolvedPresentationSize(
            forVisibleFrame: NSScreen.main?.visibleFrame.size ?? CGSize(
                width: MyWikiSourceLibraryLayoutPolicy.preferredWidth,
                height: MyWikiSourceLibraryLayoutPolicy.preferredHeight
            )
        )

        HStack(alignment: .top, spacing: 24) {
            sourceTreePane
            managementPane
        }
        .padding(24)
        .frame(
            width: presentationSize.width,
            height: presentationSize.height
        )
        .background(MyWikiTheme.contentBackground)
        .foregroundStyle(.primary)
        .onAppear(perform: reload)
        .onChange(of: isUpdatingSources) { wasUpdating, isUpdating in
            if wasUpdating, isUpdating == false {
                statusMessage = "Source catalog refreshed."
                reload()
            }
        }
    }

    private var sourceTreePane: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Source Library")
                    .font(.system(size: 26, weight: .semibold))
                Text(statusMessage)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            sourceSearchField
            sourceList
        }
        .frame(
            minWidth: MyWikiSourceLibraryLayoutPolicy.minimumSourceTreeWidth,
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .topLeading
        )
    }

    private var managementPane: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Spacer()
                Button(MyWikiSourceLibraryActionCopy.closeTitle) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    updatePanel
                    summaryPanel
                    filterAndBatchPanel
                    manualUploadsPanel
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.bottom, 2)
            }
            Spacer(minLength: 0)
        }
        .frame(width: MyWikiSourceLibraryLayoutPolicy.managementColumnWidth)
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }

    private var updatePanel: some View {
        sideSection {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    statusMessage = "My Wiki update started."
                    onUpdateSources()
                } label: {
                    Label(
                        isUpdatingSources
                            ? MyWikiSourceLibraryActionCopy.updatingTitle
                            : MyWikiSourceLibraryActionCopy.updateTitle,
                        systemImage: "arrow.triangle.2.circlepath"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isUpdatingSources)

                Text(MyWikiSourceLibraryActionCopy.autosaveExplanation)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var summaryPanel: some View {
        sideSection(title: "Status") {
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8),
            ], spacing: 8) {
                summaryBadge("\(presentation.totalCount)", "total")
                summaryBadge("\(presentation.includedCount)", "included")
                summaryBadge("\(presentation.pendingCount)", "pending")
                summaryBadge("\(presentation.changedCount)", "changed")
                summaryBadge("\(presentation.failedCount)", "failed")
            }
            Text("\(presentation.visibleRecords.count) visible")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private var filterAndBatchPanel: some View {
        sideSection(title: "Selection") {
            Menu {
                Button("All Statuses") {
                    statusFilter = nil
                }
                Divider()
                ForEach(MyWikiSourceProcessingStatus.allCasesForSourceLibrary, id: \.self) { status in
                    Button(status.rawValue) {
                        statusFilter = status
                    }
                }
            } label: {
                Label(statusFilter?.rawValue ?? "All Statuses", systemImage: "line.3.horizontal.decrease.circle")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                applyBulkAction(.includeVisible)
            } label: {
                Label("Include Visible", systemImage: "checkmark.circle")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .disabled(presentation.visibleRecords.isEmpty)

            Button {
                applyBulkAction(.excludeVisible)
            } label: {
                Label("Exclude Visible", systemImage: "minus.circle")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .disabled(presentation.visibleRecords.isEmpty)

            Button {
                applyBulkAction(.invertVisible)
            } label: {
                Label("Invert Visible", systemImage: "arrow.triangle.2.circlepath")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .disabled(presentation.visibleRecords.isEmpty)
        }
    }

    private var manualUploadsPanel: some View {
        sideSection(title: MyWikiSourceLibraryActionCopy.manualUploadsTitle) {
            Text(MyWikiSourceLibraryActionCopy.manualUploadsExplanation)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            dropTarget

            HStack(spacing: 8) {
                Button {
                    chooseFolder()
                } label: {
                    Label("Choose Folder", systemImage: "folder")
                }

                Button {
                    chooseFiles()
                } label: {
                    Label("Import Files", systemImage: "doc.badge.plus")
                }
            }
        }
    }

    private var dropTarget: some View {
        VStack(spacing: 6) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 21, weight: .semibold))
            Text("Drop Markdown or text here")
                .font(.system(size: 13, weight: .semibold))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isDropTargeted ? Color.blue.opacity(0.18) : MyWikiTheme.controlBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(
                            isDropTargeted ? Color.blue.opacity(0.7) : MyWikiTheme.border,
                            style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                        )
                )
        )
        .dropDestination(for: URL.self) { urls, _ in
            importFiles(urls)
            return true
        } isTargeted: { isTargeted in
            isDropTargeted = isTargeted
        }
    }

    private var sourceSearchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search title or path", text: $query)
                .textFieldStyle(.plain)
            if query.isEmpty == false {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(MyWikiTheme.controlBackground)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(MyWikiTheme.border, lineWidth: 1))
        )
    }

    private var sourceList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 6) {
                if presentation.visibleRecords.isEmpty {
                    emptyState
                } else {
                    ForEach(visibleNodeRows) { row in
                        nodeRow(row.node, depth: row.depth)
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("No sources match the current view.")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
    }

    @ViewBuilder
    private func nodeRow(_ node: MyWikiSourceCatalogNode, depth: Int) -> some View {
        switch node.kind {
        case .root:
            EmptyView()
        case .directory:
            directoryRow(node, depth: depth)
        case .source(let record):
            sourceRow(record, depth: depth)
        }
    }

    private func directoryRow(_ node: MyWikiSourceCatalogNode, depth: Int) -> some View {
        HStack(spacing: 10) {
            selectionButton(state: node.selectionState) {
                let shouldInclude = node.selectionState != .included
                setIncluded(shouldInclude, sourceIDs: descendantSourceIDs(from: node))
            }

            Image(systemName: "folder")
                .foregroundStyle(.secondary)

            Text(node.title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)

            Spacer()

            Text("\(descendantSourceIDs(from: node).count)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.leading, CGFloat(depth) * 18)
        .padding(.vertical, 8)
        .padding(.trailing, 10)
        .background(rowBackground)
    }

    private func sourceRow(_ record: MyWikiSourceCatalogRecord, depth: Int) -> some View {
        HStack(spacing: 10) {
            selectionButton(state: record.included ? .included : .excluded) {
                setIncluded(record.included == false, sourceIDs: [record.sourceID])
            }

            Image(systemName: icon(for: record.status))
                .foregroundStyle(color(for: record.status))

            VStack(alignment: .leading, spacing: 3) {
                Text(record.displayTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(MyWikiSourceLibraryDisplayPolicy.displayRelativePath(for: record))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(record.status.rawValue)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(color(for: record.status))

            if let summaryPath = record.wikiSummaryPath {
                Button {
                    NSWorkspace.shared.open(projectRoot.appending(path: summaryPath))
                } label: {
                    Image(systemName: "arrow.up.right.square")
                }
                .buttonStyle(.plain)
                .help("Open summary")
            }
        }
        .padding(.leading, CGFloat(depth) * 18)
        .padding(.vertical, 8)
        .padding(.trailing, 10)
        .background(rowBackground)
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(MyWikiTheme.cardBackground)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(MyWikiTheme.border, lineWidth: 1))
    }

    private func sideSection<Content: View>(
        title: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(MyWikiTheme.cardBackground)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(MyWikiTheme.border, lineWidth: 1))
        )
    }

    private func selectionButton(
        state: MyWikiSourceSelectionState,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: selectionIcon(for: state))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(selectionColor(for: state))
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.plain)
        .help(selectionHelp(for: state))
    }

    private func summaryBadge(_ value: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(value)
                .font(.system(size: 12, weight: .semibold))
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(MyWikiTheme.controlBackground)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(MyWikiTheme.border, lineWidth: 1))
        )
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose Folder"
        if panel.runModal() == .OK, let folder = panel.url {
            do {
                let result = try MyWikiSourceLibrary().importFolder(folder, projectRoot: projectRoot)
                didImport(result)
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = Self.allowedSourceContentTypes
        panel.prompt = "Import"
        if panel.runModal() == .OK {
            importFiles(panel.urls)
        }
    }

    private func importFiles(_ urls: [URL]) {
        do {
            let result = try MyWikiSourceLibrary().importFiles(urls, projectRoot: projectRoot)
            didImport(result)
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func didImport(_ result: MyWikiSourceImportResult) {
        if result.importedFileNames.isEmpty {
            statusMessage = "No supported Markdown or text files were imported."
        } else {
            statusMessage = MyWikiSourceLibraryActionCopy.importedStatusMessage(
                importedCount: result.importedFileNames.count
            )
        }
        reload()
        onDidChange()
    }

    private func reload() {
        do {
            snapshot = try MyWikiSourceCatalogBuilder().refreshCatalog(
                projectRoot: projectRoot,
                sourceVault: sourceVault,
                importedDocuments: importedDocuments
            )
            if statusMessage.isEmpty || statusMessage == MyWikiSourceLibraryActionCopy.defaultStatusMessage {
                statusMessage = MyWikiSourceLibraryActionCopy.defaultStatusMessage
            }
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func applyBulkAction(_ action: MyWikiSourceCatalogBulkAction) {
        var updated = snapshot
        updated.apply(action: action, visibleSourceIDs: presentation.visibleRecords.map(\.sourceID))
        save(updated)
    }

    private func setIncluded(_ included: Bool, sourceIDs: [String]) {
        let sourceIDs = Set(sourceIDs)
        var updated = snapshot
        for index in updated.records.indices where sourceIDs.contains(updated.records[index].sourceID) {
            updated.records[index].included = included
        }
        save(updated)
    }

    private func save(_ updated: MyWikiSourceCatalogSnapshot) {
        do {
            try MyWikiSourceCatalogStore(projectRoot: projectRoot).save(updated)
            snapshot = updated
            statusMessage = "Source catalog updated."
            onDidChange()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func descendantSourceIDs(from node: MyWikiSourceCatalogNode) -> [String] {
        switch node.kind {
        case .source(let record):
            return [record.sourceID]
        case .root, .directory:
            return node.children.flatMap(descendantSourceIDs)
        }
    }

    private func flattenedRows(from nodes: [MyWikiSourceCatalogNode], depth: Int) -> [SourceLibraryNodeRow] {
        nodes.flatMap { node in
            [SourceLibraryNodeRow(node: node, depth: depth)] + flattenedRows(from: node.children, depth: depth + 1)
        }
    }

    private func selectionIcon(for state: MyWikiSourceSelectionState) -> String {
        switch state {
        case .included:
            return "checkmark.circle.fill"
        case .excluded:
            return "circle"
        case .mixed:
            return "minus.circle.fill"
        }
    }

    private func selectionColor(for state: MyWikiSourceSelectionState) -> Color {
        switch state {
        case .included:
            return .green
        case .excluded:
            return .secondary
        case .mixed:
            return .orange
        }
    }

    private func selectionHelp(for state: MyWikiSourceSelectionState) -> String {
        switch state {
        case .included:
            return "Included in My Wiki"
        case .excluded:
            return "Not included in My Wiki"
        case .mixed:
            return "Some descendants are included"
        }
    }

    private func icon(for status: MyWikiSourceProcessingStatus) -> String {
        switch status {
        case .indexed, .excludedIndexed:
            return "checkmark.circle.fill"
        case .changed:
            return "arrow.triangle.2.circlepath.circle"
        case .failed:
            return "exclamationmark.triangle.fill"
        case .pending:
            return "clock"
        case .notIncluded:
            return "minus.circle"
        }
    }

    private func color(for status: MyWikiSourceProcessingStatus) -> Color {
        switch status {
        case .indexed:
            return .green
        case .changed:
            return .blue
        case .failed:
            return .orange
        case .pending:
            return .secondary
        case .notIncluded:
            return .secondary
        case .excludedIndexed:
            return .purple
        }
    }

    private static var allowedSourceContentTypes: [UTType] {
        [
            .plainText,
            .text,
            UTType(filenameExtension: "md"),
            UTType(filenameExtension: "markdown")
        ].compactMap { $0 }
    }
}

private extension MyWikiSourceProcessingStatus {
    static var allCasesForSourceLibrary: [MyWikiSourceProcessingStatus] {
        [.pending, .indexed, .changed, .failed, .notIncluded, .excludedIndexed]
    }
}

private struct SourceLibraryNodeRow: Identifiable {
    var node: MyWikiSourceCatalogNode
    var depth: Int

    var id: String {
        "\(depth):\(node.id)"
    }
}
