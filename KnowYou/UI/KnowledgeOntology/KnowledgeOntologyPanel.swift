import SwiftUI

struct KnowledgeOntologyPanel: View {
    let sourceVault: URL?
    let projectRoot: URL?
    let developmentSourceURL: URL
    let bundledHelperAppURL: URL?
    @Binding var selectedEntry: MyWikiEntry?

    var body: some View {
        MyWikiPanel(
            sourceVault: sourceVault,
            projectRoot: projectRoot,
            developmentSourceURL: developmentSourceURL,
            bundledHelperAppURL: bundledHelperAppURL,
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
                .foregroundStyle(.white)

            Text("Details for summaries, people, projects, topics, preferences, and follow-ups will appear here.")
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
