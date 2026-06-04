import SwiftUI

struct KnowledgeOntologyPanel: View {
    let sourceVault: URL?
    let projectRoot: URL?
    let developmentSourceURL: URL?
    let bundledRunner: Result<MyWikiRunnerBundle?, Error>
    let importedDocuments: [ImportedKnowledgeDocument]
    let summarizer: SummaryGenerating?
    let nextDigestUpdateDate: Date?
    @Binding var selectedEntry: MyWikiEntry?

    var body: some View {
        MyWikiPanel(
            sourceVault: sourceVault,
            projectRoot: projectRoot,
            developmentSourceURL: developmentSourceURL,
            bundledRunner: bundledRunner,
            importedDocuments: importedDocuments,
            summarizer: summarizer,
            nextDigestUpdateDate: nextDigestUpdateDate,
            selectedEntry: $selectedEntry
        )
    }
}

struct KnowledgeOntologyRecentExportPresentation {
    let visibleFileNames: [String]
    let hiddenCount: Int

    var summaryText: String? {
        guard hiddenCount > 0 else { return nil }
        return "\(hiddenCount) more files were synced. You can review them in My Wiki sources."
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
            Label("Select a My Wiki item", systemImage: "sidebar.right")
                .font(.headline)

            Text(MyWikiUserFacingCopy.detailPlaceholder)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .textBackgroundColor))
    }
}
