import Foundation

struct MyWikiAgentContextProvider {
    func brief(from snapshot: MyWikiDashboardSnapshot, maxItemsPerCategory: Int = 5) -> String {
        let limit = max(0, maxItemsPerCategory)
        var sections: [String] = ["# My Wiki Agent Brief"]

        appendSection("项目", entries: snapshot.projects, limit: limit, to: &sections)
        appendSection("主题", entries: snapshot.themes, limit: limit, to: &sections)
        appendSection("偏好", entries: snapshot.preferences, limit: limit, to: &sections)
        appendSection("待办", entries: snapshot.openLoops, limit: limit, to: &sections)
        appendSection("总结", entries: snapshot.summaries, limit: limit, to: &sections)

        return sections.joined(separator: "\n\n")
    }

    private func appendSection(_ title: String, entries: [MyWikiEntry], limit: Int, to sections: inout [String]) {
        let items = Array(entries.prefix(limit))
        guard items.isEmpty == false else { return }

        let body = items.map { entry in
            """
            - \(sanitize(entry.title))：\(sanitize(entry.summary))
              来源：\(sourceText(for: entry))
            """
        }
        .joined(separator: "\n")

        sections.append("## \(title)\n\(body)")
    }

    private func sourceText(for entry: MyWikiEntry) -> String {
        let sources = entry.sourceNames.filter { $0.isEmpty == false }
        return sources.isEmpty ? "My Wiki" : sources.joined(separator: "、")
    }

    private func sanitize(_ text: String) -> String {
        text
            .replacingOccurrences(of: "entity", with: "内部术语", options: [.caseInsensitive])
            .replacingOccurrences(of: "concept", with: "内部术语", options: [.caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
