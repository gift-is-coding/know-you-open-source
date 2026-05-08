import SwiftUI

struct KnowledgeOntologyPanel: View {
    let sourceVault: URL?
    let projectRoot: URL?
    let developmentSourceURL: URL
    let bundledHelperAppURL: URL?

    @State private var statusMessage = "Ready"
    @State private var exportedFileNames: [String] = []
    @State private var isSyncing = false

    var body: some View {
        GeometryReader { proxy in
            VStack(alignment: .leading, spacing: 22) {
                header

                VStack(alignment: .leading, spacing: 14) {
                    infoRow("Project", projectRoot?.path ?? "KnowYou environment is not ready.")
                    infoRow("llm_wiki", launchTarget.statusDescription)
                    infoRow("Status", statusMessage)
                }
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.62))

                HStack(spacing: 12) {
                    Button {
                        syncDiaries()
                    } label: {
                        Label("同步日记到知识本体", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSyncing || sourceVault == nil || projectRoot == nil)

                    Button {
                        openKnowledgeOntology()
                    } label: {
                        Label("打开知识本体", systemImage: "point.3.connected.trianglepath.dotted")
                    }
                    .buttonStyle(.bordered)
                    .disabled(projectRoot == nil || launchTarget == .missing)
                }

                recentSyncSection
            }
            .padding(.horizontal, 32)
            .padding(.top, 32)
            .padding(.bottom, 40)
            .frame(maxWidth: 760, alignment: .topLeading)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.black)
        .foregroundStyle(.white)
        .onAppear {
            syncDiaries()
        }
    }

    private var recentPresentation: KnowledgeOntologyRecentExportPresentation {
        KnowledgeOntologyRecentExportPresentation(exportedFileNames: exportedFileNames)
    }

    @ViewBuilder
    private var recentSyncSection: some View {
        if exportedFileNames.isEmpty == false {
            VStack(alignment: .leading, spacing: 8) {
                Text("最近同步")
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
        KnowledgeOntologyLauncher.resolveLaunchTarget(
            bundledHelperAppURL: bundledHelperAppURL,
            developmentSourceURL: developmentSourceURL
        )
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("知识本体", systemImage: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 28, weight: .semibold))
            Text("复用 llm_wiki 的 sources、wiki、search、graph、lint、review 和 deep research，把 KnowYou 日记作为原始资料输入。")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.62))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .fontWeight(.semibold)
                .foregroundStyle(.white.opacity(0.86))
                .frame(width: 84, alignment: .leading)
            Text(value)
                .textSelection(.enabled)
                .lineLimit(2)
        }
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
            statusMessage = "Synced \(result.exportedFileNames.count) diary source file(s)."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func openKnowledgeOntology() {
        guard let projectRoot else { return }

        do {
            try KnowledgeOntologyLauncher().launch(target: launchTarget, projectRoot: projectRoot)
            statusMessage = "Opening knowledge ontology workspace..."
        } catch {
            statusMessage = error.localizedDescription
        }
    }
}

struct KnowledgeOntologyRecentExportPresentation {
    let visibleFileNames: [String]
    let hiddenCount: Int

    var summaryText: String? {
        guard hiddenCount > 0 else { return nil }
        return "还有 \(hiddenCount) 个文件已同步，可在 llm_wiki 的原始资料中查看。"
    }

    init(exportedFileNames: [String], maxVisibleCount: Int = 8) {
        let limit = max(0, maxVisibleCount)
        visibleFileNames = Array(exportedFileNames.prefix(limit))
        hiddenCount = max(0, exportedFileNames.count - visibleFileNames.count)
    }
}

struct KnowledgeOntologyDetailPlaceholder: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("llm_wiki 原功能", systemImage: "network")
                .font(.headline)
                .foregroundStyle(.white)

            Text("知识本体的图谱、搜索、review、lint、deep research 和 settings 会在复用的 llm_wiki 工作台中运行。KnowYou 负责同步日记资料和启动这个工作台。")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.black.opacity(0.96))
    }
}
