import SwiftUI
import AppKit

struct MyWikiPanel: View {
    let sourceVault: URL?
    let projectRoot: URL?
    let developmentSourceURL: URL
    let bundledHelperAppURL: URL?
    let importedDocuments: [ImportedKnowledgeDocument]
    let nextDigestUpdateDate: Date?
    @Binding var selectedEntry: MyWikiEntry?

    @State private var query = ""
    @State private var snapshot = MyWikiDashboardSnapshot.empty
    @State private var duplicateSuggestions: [MyWikiDuplicateSuggestion] = []
    @State private var statusMessage = "Ready"
    @State private var ingestProgress: MyWikiIngestProgress?
    @State private var isSyncing = false
    @State private var expandedCategoryIDs: Set<String> = []
    @State private var showingAllCategoryIDs: Set<String> = []
    @State private var selectedTagByCategoryID: [String: String] = [:]
    @State private var expandedTagFacetCategoryIDs: Set<String> = []
    @State private var editingEntry: MyWikiEntry?
    @State private var conflictMessage: String?
    @State private var isShowingStatus = false
    @State private var isShowingSourceLibrary = false
    @State private var isShowingAgentConnection = false
    @State private var selectedAgentClient: MyWikiAgentClient = .codex
    @State private var agentSetupRefreshID = UUID()
    @State private var reviewingSuggestion: MyWikiDuplicateSuggestion?
    @State private var duplicateDiscoveryTask: Task<Void, Never>?

    var body: some View {
        HSplitView {
            indexPane
                .frame(minWidth: 320, idealWidth: 390, maxWidth: 520)

            detailPane
                .frame(minWidth: 520, maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(MyWikiTheme.contentBackground)
        .foregroundStyle(.primary)
        .onAppear {
            for action in MyWikiPanelLifecyclePolicy.onAppearActions {
                switch action {
                case .loadDashboard:
                    loadDashboard()
                case .syncDiaries:
                    syncDiaries()
                }
            }
        }
        .task(id: progressRefreshTaskID) {
            guard MyWikiProgressRefreshPolicy.shouldRefresh(
                isSyncing: isSyncing,
                progressState: ingestProgress?.state
            ) else {
                return
            }

            while Task.isCancelled == false {
                try? await Task.sleep(nanoseconds: MyWikiProgressRefreshPolicy.intervalNanoseconds)
                loadIngestProgress()
                if ingestProgress?.state != .running && isSyncing == false {
                    break
                }
            }
        }
        .sheet(item: $editingEntry) { entry in
            MyWikiEditSheet(
                entry: entry,
                conflictMessage: conflictMessage,
                onCancel: {
                    conflictMessage = nil
                    editingEntry = nil
                },
                onFindDuplicates: {
                    conflictMessage = nil
                    editingEntry = nil
                    findDuplicates()
                },
                onSave: saveEdit
            )
        }
        .alert("Wiki Status", isPresented: $isShowingStatus) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(statusMessage)
        }
        .sheet(isPresented: $isShowingSourceLibrary) {
            if let projectRoot {
                MyWikiSourceLibraryView(
                    projectRoot: projectRoot,
                    sourceVault: sourceVault,
                    importedDocuments: importedDocuments,
                    isUpdatingSources: isSyncing,
                    onDidChange: {
                        loadIngestProgress()
                        loadDashboard()
                    },
                    onUpdateSources: syncDiaries
                )
            } else {
                Text("My Wiki folder is not available.")
                    .padding(24)
            }
        }
        .sheet(isPresented: $isShowingAgentConnection) {
            MyWikiAgentConnectionSheet(
                presentation: agentConnectionPresentation,
                selectedClient: $selectedAgentClient,
                setupRefreshID: $agentSetupRefreshID
            )
        }
    }

    private var indexPane: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            digestScheduleView
            searchField
            ingestProgressView
            duplicateSuggestionBanner

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(indexSections) { sectionPresentation in
                        section(sectionPresentation)
                    }
                }
                .padding(.bottom, 24)
            }
        }
        .padding(24)
        .background(MyWikiTheme.sidebarBackground)
    }

    private var detailPane: some View {
        Group {
            if let suggestion = reviewingSuggestion {
                MyWikiDuplicateReviewView(
                    suggestion: suggestion,
                    onCancel: {
                        reviewingSuggestion = nil
                    },
                    onMerge: { canonicalID in
                        mergeSuggestion(suggestion, canonicalID: canonicalID)
                    }
                )
            } else {
                MyWikiDetailView(
                    entry: selectedEntry,
                    duplicateSuggestionCount: duplicateSuggestions.count,
                    duplicateSuggestionAffectedCount: selectedEntry.map(duplicateSuggestionCount) ?? 0,
                    isSyncing: isSyncing,
                    onEdit: { entry in
                        conflictMessage = nil
                        editingEntry = entry
                    },
                    onOrganizeJournals: syncDiaries,
                    onFindDuplicates: findDuplicates,
                    onManageSources: { isShowingSourceLibrary = true },
                    onUseInAgents: { isShowingAgentConnection = true },
                    onRevealWikiFolder: openProjectFolder,
                    onShowStatus: { isShowingStatus = true },
                    onOpenSource: openSource,
                    onOpenRelated: openRelated
                )
            }
        }
        .background(MyWikiTheme.contentBackground)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Label("My Wiki", systemImage: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 30, weight: .semibold))

                Spacer()

                Button {
                    isShowingAgentConnection = true
                } label: {
                    Label("Use My Wiki in Agents", systemImage: "externaldrive.connected.to.line.below")
                }
                .buttonStyle(.bordered)
            }

            Text(MyWikiUserFacingCopy.overviewSubtitle)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var searchField: some View {
        TextField("Search or ask My Wiki...", text: $query)
            .textFieldStyle(.plain)
            .font(.system(size: 15))
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(MyWikiTheme.controlBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(MyWikiTheme.border, lineWidth: 1)
                    )
            )
    }

    private var digestScheduleView: some View {
        let presentation = MyWikiDigestSchedulePresentation(
            ingestProgress: ingestProgress,
            nextRunDate: nextDigestUpdateDate
        )
        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(presentation.title)
                    .font(.system(size: 13, weight: .semibold))
                Text(presentation.triggerText)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 10)

            VStack(alignment: .trailing, spacing: 6) {
                scheduleMetric(title: presentation.lastRunTitle, value: presentation.lastRunValue)
                scheduleMetric(title: presentation.nextRunTitle, value: presentation.nextRunValue)
            }

            Button {
                syncDiaries()
            } label: {
                Text(isSyncing ? "Updating..." : presentation.updateNowTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(minWidth: 92, minHeight: 32)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSyncing)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(MyWikiTheme.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(MyWikiTheme.border, lineWidth: 1)
                )
        )
    }

    private func scheduleMetric(title: String, value: String) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 13, weight: .semibold))
        }
    }

    @ViewBuilder
    private var ingestProgressView: some View {
        HStack(alignment: .center, spacing: 8) {
            Group {
                if let ingestProgress {
                    ingestProgressStatusCard(ingestProgress)
                } else {
                    sourceCatalogStatusCard
                }
            }
            .layoutPriority(1)

            if MyWikiSourceLibraryEntryPolicy.showsManageSourcesButton {
                Button {
                    isShowingSourceLibrary = true
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: MyWikiSourceLibraryEntryPolicy.manageButtonSystemImage)
                            .font(.system(size: MyWikiSourceLibraryEntryPolicy.manageButtonIconSize, weight: .medium))
                        Text(MyWikiSourceLibraryEntryPolicy.manageButtonTitle)
                            .font(.system(size: 13, weight: .semibold))
                    }
                        .frame(
                            minWidth: MyWikiSourceLibraryEntryPolicy.manageButtonMinWidth,
                            minHeight: MyWikiSourceLibraryEntryPolicy.manageButtonMinHeight
                        )
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .fixedSize(horizontal: true, vertical: false)
            }
        }
    }

    private func ingestProgressStatusCard(_ ingestProgress: MyWikiIngestProgress) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(ingestProgress.title)
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(ingestProgress.detail)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(MyWikiTheme.controlBackground)
                    Capsule()
                        .fill(progressColor(for: ingestProgress.state))
                        .frame(width: max(0, proxy.size.width * ingestProgress.fraction))
                }
            }
            .frame(height: 4)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(MyWikiTheme.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(MyWikiTheme.border, lineWidth: 1)
                )
        )
    }

    private var sourceCatalogStatusCard: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Sources")
                .font(.system(size: 12, weight: .semibold))
            Text("Choose which documents My Wiki can process.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(MyWikiTheme.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(MyWikiTheme.border, lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private var duplicateSuggestionBanner: some View {
        if duplicateSuggestions.isEmpty == false {
            Button {
                if let first = duplicateSuggestions.first {
                    reviewingSuggestion = first
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(duplicateSuggestions.count) duplicate suggestions")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color(red: 0.94, green: 0.86, blue: 0.48))
                        Text(MyWikiUserFacingCopy.duplicateSuggestionSubtitle)
                            .font(.system(size: 12))
                            .foregroundStyle(Color(red: 0.72, green: 0.66, blue: 0.45))
                    }
                    Spacer()
                        Text("Review")
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 10)
                            .frame(height: 28)
                            .background(RoundedRectangle(cornerRadius: 7).fill(MyWikiTheme.controlBackground))
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(red: 0.98, green: 0.8, blue: 0.16).opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color(red: 0.98, green: 0.8, blue: 0.16).opacity(0.28), lineWidth: 1)
                        )
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func section(_ sectionPresentation: MyWikiIndexCategorySection) -> some View {
        let category = sectionPresentation.category
        let presentation = sectionPresentation.presentation
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Button {
                    toggle(category)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: expandedCategoryIDs.contains(category.id) ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                        Text(presentation.title.uppercased())
                            .font(.system(size: 11, weight: .bold))
                            .tracking(0.8)
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Spacer()

                Text("\(presentation.entries.count)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(height: 34)

            if expandedCategoryIDs.contains(category.id), sectionPresentation.tagFacets.isEmpty == false {
                tagFacetChips(category: category, facets: sectionPresentation.tagFacets)
        .padding(.bottom, 4)
    }

            ForEach(presentation.visibleEntries) { entry in
                MyWikiIndexRow(entry: entry, isSelected: isSelected(entry)) {
                    selectedEntry = entry
                }
            }

            if presentation.canShowMore || presentation.canShowLess {
                Button {
                    toggleShowAll(category)
                } label: {
                    Text(presentation.showMoreTitle)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
                        .padding(.horizontal, 10)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var indexSections: [MyWikiIndexCategorySection] {
        MyWikiIndexSectionsBuilder().categorySections(
            snapshot: snapshot,
            query: query,
            expandedCategoryIDs: expandedCategoryIDs,
            showingAllCategoryIDs: showingAllCategoryIDs,
            selectedTagByCategoryID: selectedTagByCategoryID,
            previewLimit: MyWikiIndexPreviewPolicy.defaultVisibleLimit
        )
    }

    private func tagFacetChips(category: MyWikiCategory, facets: [MyWikiTagFacet]) -> some View {
        let selectedTag = selectedTagByCategoryID[category.id]
        let isExpanded = expandedTagFacetCategoryIDs.contains(category.id)
        let visibleFacets = MyWikiTagFacetDisplayPolicy.visibleFacets(facets, isExpanded: isExpanded)
        return FlowLayout(spacing: 6) {
            tagFacetButton(title: "All", isSelected: selectedTag == nil) {
                selectedTagByCategoryID[category.id] = nil
                showingAllCategoryIDs.remove(category.id)
            }
            ForEach(visibleFacets) { facet in
                let isSelected = selectedTag == facet.id
                tagFacetButton(title: "\(facet.title) \(facet.count)", isSelected: isSelected) {
                    selectedTagByCategoryID[category.id] = isSelected ? nil : facet.id
                    showingAllCategoryIDs.remove(category.id)
                }
            }
            if MyWikiTagFacetDisplayPolicy.canExpand(facets, isExpanded: isExpanded)
                || MyWikiTagFacetDisplayPolicy.canCollapse(facets, isExpanded: isExpanded) {
                tagFacetButton(
                    title: MyWikiTagFacetDisplayPolicy.toggleTitle(for: facets, isExpanded: isExpanded),
                    isSelected: false
                ) {
                    toggleTagFacets(category)
                }
            }
        }
    }

    private func tagFacetButton(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isSelected ? Color.white : .secondary)
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.accentColor : MyWikiTheme.controlBackground)
                )
        }
        .buttonStyle(.plain)
    }

    private func isSelected(_ entry: MyWikiEntry) -> Bool {
        selectedEntry?.id == entry.id && selectedEntry?.category == entry.category
    }

    private var pipelineTarget: MyWikiPipelineTarget {
        MyWikiPipelineBridge.resolveTarget(
            bundledHelperAppURL: bundledHelperAppURL,
            developmentSourceURL: developmentSourceURL
        )
    }

    private var agentConnectionPresentation: MyWikiAgentConnectionPresentation {
        MyWikiAgentConnectionPresentation(
            projectRoot: projectRoot,
            mcpServerScriptURL: MyWikiAgentConnectionPresentation.defaultMCPServerScriptURL(),
            knowYouBinaryURL: Bundle.main.executableURL ?? URL(fileURLWithPath: "KnowYou")
        )
    }

    private var progressRefreshTaskID: String {
        "\(isSyncing)-\(ingestProgress?.state.rawValue ?? "none")"
    }

    private func toggle(_ category: MyWikiCategory) {
        if expandedCategoryIDs.contains(category.id) {
            expandedCategoryIDs.remove(category.id)
            showingAllCategoryIDs.remove(category.id)
        } else {
            expandedCategoryIDs.insert(category.id)
        }
    }

    private func toggleShowAll(_ category: MyWikiCategory) {
        if showingAllCategoryIDs.contains(category.id) {
            showingAllCategoryIDs.remove(category.id)
        } else {
            showingAllCategoryIDs.insert(category.id)
        }
    }

    private func toggleTagFacets(_ category: MyWikiCategory) {
        if expandedTagFacetCategoryIDs.contains(category.id) {
            expandedTagFacetCategoryIDs.remove(category.id)
        } else {
            expandedTagFacetCategoryIDs.insert(category.id)
        }
    }

    private func syncDiaries() {
        guard let projectRoot else { return }
        guard !isSyncing else { return }
        isSyncing = true
        statusMessage = "Updating My Wiki sources..."
        loadIngestProgress()

        let target = pipelineTarget
        let sourceVault = sourceVault
        let importedDocuments = importedDocuments
        Task {
            let outcome = await MyWikiDigestRunner().run(
                projectRoot: projectRoot,
                sourceVault: sourceVault,
                importedDocuments: importedDocuments,
                target: target
            )

            await MainActor.run {
                statusMessage = outcome.message
                isSyncing = false
                loadDashboard()
            }
        }
    }

    private func loadDashboard() {
        guard let projectRoot else { return }
        do {
            snapshot = try MyWikiMarkdownStore().loadDashboard(projectRoot: projectRoot)
            loadIngestProgress()
            if expandedCategoryIDs.isEmpty {
                expandedCategoryIDs = Set(snapshot.categories.map(\.id))
            }
            if selectedEntry == nil {
                selectedEntry = snapshot.primaryEntries.first ?? snapshot.sources.first
            }
            if MyWikiDuplicateDiscoveryPolicy.scansOnDashboardLoad {
                refreshDuplicateSuggestionsInBackground(projectRoot: projectRoot)
            }
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func refreshDuplicateSuggestionsInBackground(projectRoot: URL) {
        duplicateDiscoveryTask?.cancel()
        duplicateDiscoveryTask = Task { @MainActor in
            let suggestions = await Task.detached(priority: .utility) {
                do {
                    return try MyWikiDuplicateService().findDuplicateSuggestions(projectRoot: projectRoot)
                } catch {
                    return []
                }
            }.value
            guard Task.isCancelled == false else { return }
            duplicateSuggestions = suggestions
        }
    }

    private func loadIngestProgress() {
        guard let projectRoot else { return }
        ingestProgress = try? MyWikiIngestProgressStore().load(projectRoot: projectRoot)
    }

    private func saveEdit(entry: MyWikiEntry, title: String, aliases: [String], summary: String) {
        guard let projectRoot else { return }
        do {
            let result = try MyWikiRenameService().rename(
                entry,
                to: title,
                aliases: aliases,
                summary: summary,
                projectRoot: projectRoot
            )
            switch result {
            case .renamed:
                conflictMessage = nil
                editingEntry = nil
                loadDashboard()
                selectedEntry = snapshot.entries(for: entry.category).first { $0.id == entry.id }
            case .conflict(let existingTitle):
                conflictMessage = "A \(entry.category.singularTitle) named \(existingTitle) already exists. Keep the current name, choose another name, or use More > Find duplicates to merge."
            }
        } catch {
            conflictMessage = error.localizedDescription
        }
    }

    private func findDuplicates() {
        guard let projectRoot else { return }
        do {
            duplicateSuggestions = try MyWikiDuplicateService().findDuplicateSuggestions(projectRoot: projectRoot)
            statusMessage = duplicateSuggestions.isEmpty
                ? "No duplicate suggestions found."
                : "\(duplicateSuggestions.count) duplicate suggestions found."
            reviewingSuggestion = duplicateSuggestions.first
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func duplicateSuggestionCount(for entry: MyWikiEntry) -> Int {
        duplicateSuggestions.filter { suggestion in
            suggestion.entries.contains { $0.id == entry.id }
        }.count
    }

    private func mergeSuggestion(_ suggestion: MyWikiDuplicateSuggestion, canonicalID: String) {
        guard let projectRoot else { return }
        do {
            try MyWikiDuplicateService().merge(
                suggestion: suggestion,
                canonicalID: canonicalID,
                projectRoot: projectRoot
            )
            statusMessage = "Merged duplicate My Wiki items."
            reviewingSuggestion = nil
            duplicateSuggestions = try MyWikiDuplicateService().findDuplicateSuggestions(projectRoot: projectRoot)
            loadDashboard()
            selectedEntry = snapshot.allEntries.first { $0.id == canonicalID }
        } catch {
            statusMessage = error.localizedDescription
            isShowingStatus = true
        }
    }

    private func openSource(_ sourceName: String) {
        guard let projectRoot else { return }
        if let url = MyWikiNavigationResolver().resolveSourceURL(sourceName, projectRoot: projectRoot) {
            NSWorkspace.shared.open(url)
            statusMessage = "Opened source \(sourceName)."
        } else {
            statusMessage = "Source not found: \(sourceName)"
            isShowingStatus = true
        }
    }

    private func openRelated(_ reference: String) {
        if let entry = MyWikiNavigationResolver().resolveRelatedEntry(reference, snapshot: snapshot) {
            selectedEntry = entry
            reviewingSuggestion = nil
        } else {
            statusMessage = "Related page not found: \(reference)"
            isShowingStatus = true
        }
    }

    private func openProjectFolder() {
        guard let projectRoot else { return }
        NSWorkspace.shared.open(projectRoot)
        statusMessage = "Opened the My Wiki folder."
    }

    private func progressColor(for state: MyWikiIngestProgress.State) -> Color {
        switch state {
        case .running:
            return Color.blue
        case .succeeded:
            return Color.green
        case .failed:
            return Color(red: 0.98, green: 0.72, blue: 0.24)
        case .unknown:
            return .secondary
        }
    }
}

private struct MyWikiIndexRow: View {
    let entry: MyWikiEntry
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                Text(entry.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: MyWikiIndexRowHitTargetPolicy.minHeight, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? MyWikiTheme.selectionBackground : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isSelected ? Color.blue.opacity(0.78) : Color.clear, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

private struct MyWikiDuplicateReviewView: View {
    let suggestion: MyWikiDuplicateSuggestion
    let onCancel: () -> Void
    let onMerge: (String) -> Void

    @State private var canonicalID: String

    init(
        suggestion: MyWikiDuplicateSuggestion,
        onCancel: @escaping () -> Void,
        onMerge: @escaping (String) -> Void
    ) {
        self.suggestion = suggestion
        self.onCancel = onCancel
        self.onMerge = onMerge
        _canonicalID = State(initialValue: suggestion.entries.first?.id ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Review Duplicate Suggestion")
                .font(.system(size: 34, weight: .semibold))
            Text(suggestion.reason)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(suggestion.entries) { entry in
                    Button {
                        canonicalID = entry.id
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(entry.title)
                                    .font(.system(size: 17, weight: .semibold))
                                Text(entry.summary.isEmpty ? "No summary yet." : entry.summary)
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                if entry.aliases.isEmpty == false {
                                    Text("Aliases: \(entry.aliases.joined(separator: ", "))")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Image(systemName: canonicalID == entry.id ? "largecircle.fill.circle" : "circle")
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(canonicalID == entry.id ? MyWikiTheme.selectionBackground : MyWikiTheme.cardBackground)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(MyWikiTheme.border, lineWidth: 1))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack {
                Button("Not duplicates", action: onCancel)
                Spacer()
                Button("Merge with selected canonical item") {
                    onMerge(canonicalID)
                }
                .buttonStyle(.borderedProminent)
                .disabled(canonicalID.isEmpty)
            }
        }
        .padding(32)
        .frame(maxWidth: 920, maxHeight: .infinity, alignment: .topLeading)
        .background(MyWikiTheme.contentBackground)
    }
}

private struct MyWikiEditSheet: View {
    let entry: MyWikiEntry
    let conflictMessage: String?
    let onCancel: () -> Void
    let onFindDuplicates: () -> Void
    let onSave: (MyWikiEntry, String, [String], String) -> Void

    @State private var title: String
    @State private var aliasesText: String
    @State private var summary: String

    init(
        entry: MyWikiEntry,
        conflictMessage: String?,
        onCancel: @escaping () -> Void,
        onFindDuplicates: @escaping () -> Void,
        onSave: @escaping (MyWikiEntry, String, [String], String) -> Void
    ) {
        self.entry = entry
        self.conflictMessage = conflictMessage
        self.onCancel = onCancel
        self.onFindDuplicates = onFindDuplicates
        self.onSave = onSave
        _title = State(initialValue: entry.title)
        _aliasesText = State(initialValue: entry.aliases.joined(separator: ", "))
        _summary = State(initialValue: entry.summary)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Edit \(entry.category.singularTitle)")
                .font(.title2.weight(.semibold))
            TextField("Name", text: $title)
            TextField("Aliases, comma separated", text: $aliasesText)
            TextEditor(text: $summary)
                .frame(minHeight: 160)

            if let conflictMessage {
                VStack(alignment: .leading, spacing: 10) {
                    Text(conflictMessage)
                        .font(.callout)
                        .foregroundStyle(.yellow)
                    HStack {
                        Button("Keep current name", action: onCancel)
                        Button("Choose another name") {
                            title = ""
                        }
                        Button("Review possible merge", action: onFindDuplicates)
                            .buttonStyle(.borderedProminent)
                    }
                }
                .padding(12)
                .background(Color.yellow.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Save") {
                    onSave(entry, title, aliases, summary)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 520)
    }

    private var aliases: [String] {
        aliasesText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
    }
}

enum MyWikiTheme {
    static let sidebarBackground = Color(nsColor: .windowBackgroundColor)
    static let contentBackground = Color(nsColor: .textBackgroundColor)
    static let controlBackground = Color.primary.opacity(0.06)
    static let cardBackground = Color.primary.opacity(0.035)
    static let selectionBackground = Color.accentColor.opacity(0.12)
    static let border = Color.primary.opacity(0.10)
}
