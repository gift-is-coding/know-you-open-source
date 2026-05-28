import Foundation

struct MyWikiAgentContextProvider {
    func brief(from snapshot: MyWikiDashboardSnapshot, maxItemsPerCategory: Int = 5) -> String {
        let limit = max(0, maxItemsPerCategory)
        var sections: [String] = ["# My Wiki Agent Brief"]

        for category in snapshot.categories {
            appendSection(
                category.displayTitle,
                entries: snapshot.entries(for: category.id),
                limit: limit,
                to: &sections
            )
        }

        return sections.joined(separator: "\n\n")
    }

    private func appendSection(_ title: String, entries: [MyWikiEntry], limit: Int, to sections: inout [String]) {
        let items = Array(entries.prefix(limit))
        guard items.isEmpty == false else { return }

        let body = items.map { entry in
            """
            - \(sanitize(entry.title)): \(sanitize(entry.summary))
              Sources: \(sourceText(for: entry))
            """
        }
        .joined(separator: "\n")

        sections.append("## \(title)\n\(body)")
    }

    private func sourceText(for entry: MyWikiEntry) -> String {
        let sources = entry.sourceNames.filter { $0.isEmpty == false }
        return sources.isEmpty ? "My Wiki" : sources.joined(separator: ", ")
    }

    private func sanitize(_ text: String) -> String {
        text
            .replacingOccurrences(of: "entity", with: "item", options: [.caseInsensitive])
            .replacingOccurrences(of: "concept", with: "item", options: [.caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
