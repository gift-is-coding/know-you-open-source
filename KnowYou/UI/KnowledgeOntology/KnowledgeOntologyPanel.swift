import SwiftUI

struct KnowledgeOntologyPanel: View {
    let sourceVault: URL?
    let projectRoot: URL?
    let developmentSourceURL: URL
    let bundledHelperAppURL: URL?

    var body: some View {
        MyWikiPanel(
            sourceVault: sourceVault,
            projectRoot: projectRoot,
            developmentSourceURL: developmentSourceURL,
            bundledHelperAppURL: bundledHelperAppURL,
        )
    }
}

struct KnowledgeOntologyRecentExportPresentation {
    let visibleFileNames: [String]
    let hiddenCount: Int

    var summaryText: String? {
        guard hiddenCount > 0 else { return nil }
        return "还有 \(hiddenCount) 个文件已同步，可在 My Wiki 的原始资料中查看。"
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
            Label("My Wiki 高级工作台", systemImage: "network")
                .font(.headline)
                .foregroundStyle(.white)

            Text("KnowYou 会优先展示轻量的 My Wiki 页面；高级工作台用于开发、调试和后续整理流程验证。")
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
