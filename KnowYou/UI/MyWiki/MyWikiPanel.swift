import SwiftUI

struct MyWikiPanel: View {
    let sourceVault: URL?
    let projectRoot: URL?
    let developmentSourceURL: URL
    let bundledHelperAppURL: URL?

    @State private var query = ""
    @State private var statusMessage = "Ready"
    @State private var snapshot = MyWikiDashboardSnapshot.empty
    @State private var exportedFileNames: [String] = []
    @State private var selectedEntry: MyWikiEntry?
    @State private var isSyncing = false

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    searchField
                    statusBar

                    if filteredEntries.isEmpty && exportedFileNames.isEmpty {
                        emptyState
                    }

                    MyWikiSummarySection(
                        entries: filtered(snapshot.summaries),
                        selectedEntry: $selectedEntry
                    )

                    MyWikiCategorySection(
                        title: MyWikiCategory.person.displayTitle,
                        entries: filtered(snapshot.people),
                        selectedEntry: $selectedEntry
                    )
                    MyWikiCategorySection(
                        title: MyWikiCategory.project.displayTitle,
                        entries: filtered(snapshot.projects),
                        selectedEntry: $selectedEntry
                    )
                    MyWikiCategorySection(
                        title: MyWikiCategory.theme.displayTitle,
                        entries: filtered(snapshot.themes),
                        selectedEntry: $selectedEntry
                    )
                    MyWikiCategorySection(
                        title: MyWikiCategory.preference.displayTitle,
                        entries: filtered(snapshot.preferences),
                        selectedEntry: $selectedEntry
                    )
                    MyWikiCategorySection(
                        title: MyWikiCategory.openLoop.displayTitle,
                        entries: filtered(snapshot.openLoops),
                        selectedEntry: $selectedEntry
                    )

                    recentSyncSection
                }
                .padding(.horizontal, 32)
                .padding(.top, 32)
                .padding(.bottom, 40)
                .frame(maxWidth: 860, alignment: .topLeading)
                .frame(minHeight: proxy.size.height, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.black)
        .foregroundStyle(.white)
        .onAppear {
            loadDashboard()
            syncDiaries()
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Label("My Wiki", systemImage: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 28, weight: .semibold))

                Text("整理你的日记，看到最近的人、项目、主题、偏好、待办和总结。")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.62))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Button {
                syncDiaries()
            } label: {
                Label("整理日记", systemImage: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSyncing || sourceVault == nil || projectRoot == nil)
        }
    }

    private var searchField: some View {
        TextField("问问你的 My Wiki...", text: $query)
            .textFieldStyle(.plain)
            .font(.system(size: 15))
            .padding(.horizontal, 14)
            .frame(height: 42)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
            )
    }

    private var statusBar: some View {
        HStack(spacing: 14) {
            infoPill("Project", projectRoot?.path ?? "KnowYou environment is not ready.")
            infoPill("Status", statusMessage)

            Button {
                openAdvancedWorkspace()
            } label: {
                Label("高级工作台", systemImage: "hammer")
            }
            .buttonStyle(.bordered)
            .disabled(projectRoot == nil || launchTarget == .missing)
        }
        .font(.system(size: 12))
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("还没有生成 My Wiki 内容")
                .font(.headline)
                .foregroundStyle(.white)
            Text("先整理日记，KnowYou 会把原始资料写入 My Wiki 项目；后续 pipeline 会把它们整理成人物、项目、主题、偏好、待办和总结。")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.62))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.06)))
    }

    private var recentPresentation: KnowledgeOntologyRecentExportPresentation {
        KnowledgeOntologyRecentExportPresentation(exportedFileNames: exportedFileNames)
    }

    @ViewBuilder
    private var recentSyncSection: some View {
        if exportedFileNames.isEmpty == false {
            VStack(alignment: .leading, spacing: 8) {
                Text("最近整理")
                    .font(.headline)
                    .foregroundStyle(.white)

                ForEach(recentPresentation.visibleFileNames, id: \.self) { fileName in
                    Label(fileName, systemImage: "doc.plaintext")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.62))
                }

                if let summaryText = recentPresentation.summaryText {
                    Text(summaryText)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(.top, 2)
                }
            }
        }
    }

    private var launchTarget: KnowledgeOntologyLaunchTarget {
        switch pipelineTarget {
        case .bundledHelperApp(let url):
            return .bundledHelperApp(url)
        case .developmentSource(let url):
            return .developmentSource(url)
        case .missing:
            return .missing
        }
    }

    private var pipelineTarget: MyWikiPipelineTarget {
        MyWikiPipelineBridge.resolveTarget(
            bundledHelperAppURL: bundledHelperAppURL,
            developmentSourceURL: developmentSourceURL
        )
    }

    private var filteredEntries: [MyWikiEntry] {
        [
            snapshot.summaries,
            snapshot.people,
            snapshot.projects,
            snapshot.themes,
            snapshot.preferences,
            snapshot.openLoops
        ].flatMap { filtered($0) }
    }

    private func filtered(_ entries: [MyWikiEntry]) -> [MyWikiEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return entries }

        return entries.filter { entry in
            entry.title.localizedCaseInsensitiveContains(trimmed)
                || entry.summary.localizedCaseInsensitiveContains(trimmed)
        }
    }

    private func infoPill(_ title: String, _ value: String) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .fontWeight(.semibold)
                .foregroundStyle(.white.opacity(0.8))
            Text(value)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.white.opacity(0.56))
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.06)))
    }

    private func syncDiaries() {
        guard let sourceVault, let projectRoot else { return }
        isSyncing = true
        defer { isSyncing = false }

        do {
            let result = try KnowledgeOntologyProjectExporter().syncDiaries(
                sourceVault: sourceVault,
                projectRoot: projectRoot
            )
            exportedFileNames = result.exportedFileNames
            do {
                try MyWikiPipelineBridge().runIngest(target: pipelineTarget, projectRoot: projectRoot)
                statusMessage = "已整理 \(result.exportedFileNames.count) 篇日记，并连接 My Wiki pipeline。"
            } catch {
                statusMessage = "已整理 \(result.exportedFileNames.count) 篇日记；My Wiki pipeline 暂不可用。"
            }
            loadDashboard()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func loadDashboard() {
        guard let projectRoot else { return }
        do {
            snapshot = try MyWikiMarkdownStore().loadDashboard(projectRoot: projectRoot)
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func openAdvancedWorkspace() {
        guard let projectRoot else { return }

        do {
            try MyWikiPipelineBridge().openAdvancedWorkspace(target: pipelineTarget, projectRoot: projectRoot)
            statusMessage = "正在打开 My Wiki 高级工作台..."
        } catch {
            statusMessage = error.localizedDescription
        }
    }
}

private struct MyWikiSummarySection: View {
    let entries: [MyWikiEntry]
    @Binding var selectedEntry: MyWikiEntry?

    var body: some View {
        if entries.isEmpty == false {
            MyWikiCategorySection(
                title: MyWikiCategory.summary.displayTitle,
                entries: entries,
                selectedEntry: $selectedEntry
            )
        }
    }
}

private struct MyWikiCategorySection: View {
    let title: String
    let entries: [MyWikiEntry]
    @Binding var selectedEntry: MyWikiEntry?

    var body: some View {
        if entries.isEmpty == false {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.system(size: 18, weight: .semibold))

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 220), spacing: 12)],
                    alignment: .leading,
                    spacing: 12
                ) {
                    ForEach(entries) { entry in
                        Button {
                            selectedEntry = entry
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(entry.title)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)

                                Text(entry.summary.isEmpty ? "暂无摘要。" : entry.summary)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.white.opacity(0.62))
                                    .lineLimit(3)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.06)))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.white.opacity(selectedEntry == entry ? 0.36 : 0.08), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}
