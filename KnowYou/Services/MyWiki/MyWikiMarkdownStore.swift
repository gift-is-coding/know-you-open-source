import Foundation

struct MyWikiMarkdownStore {
    let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func loadDashboard(projectRoot: URL) throws -> MyWikiDashboardSnapshot {
        MyWikiDashboardSnapshot(
            summaries: try loadEntries(category: .summary, folder: "wiki/summaries", projectRoot: projectRoot),
            people: try loadEntries(category: .person, folder: "wiki/people", projectRoot: projectRoot),
            projects: try loadEntries(category: .project, folder: "wiki/projects", projectRoot: projectRoot),
            themes: try loadEntries(category: .theme, folder: "wiki/themes", projectRoot: projectRoot),
            preferences: try loadEntries(category: .preference, folder: "wiki/preferences", projectRoot: projectRoot),
            openLoops: try loadEntries(category: .openLoop, folder: "wiki/open-loops", projectRoot: projectRoot)
        )
    }

    private func loadEntries(category: MyWikiCategory, folder: String, projectRoot: URL) throws -> [MyWikiEntry] {
        let directory = projectRoot.appending(path: folder, directoryHint: .isDirectory)
        guard fileManager.fileExists(atPath: directory.path) else { return [] }

        let files = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension.lowercased() == "md" }

        return try files.map { file in
            try loadEntry(file: file, category: category)
        }
        .sorted {
            $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }

    private func loadEntry(file: URL, category: MyWikiCategory) throws -> MyWikiEntry {
        let markdown = try String(contentsOf: file, encoding: .utf8)
        let parsed = Self.parseMarkdown(markdown)
        let title = parsed.frontmatter["title"] ?? Self.titleFromFileName(file.deletingPathExtension().lastPathComponent)

        return MyWikiEntry(
            id: file.deletingPathExtension().lastPathComponent,
            title: title,
            category: category,
            summary: Self.summary(from: parsed.body),
            sourceNames: Self.sources(from: parsed.frontmatter["sources"])
        )
    }

    private static func parseMarkdown(_ markdown: String) -> (frontmatter: [String: String], body: String) {
        guard markdown.hasPrefix("---") else {
            return ([:], markdown)
        }

        let lines = markdown.components(separatedBy: .newlines)
        var frontmatter: [String: String] = [:]
        var endIndex: Int?

        for index in lines.indices.dropFirst() {
            if lines[index].trimmingCharacters(in: .whitespacesAndNewlines) == "---" {
                endIndex = index
                break
            }

            let line = lines[index]
            guard let separator = line.firstIndex(of: ":") else { continue }
            let key = line[..<separator].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)
            frontmatter[key] = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        }

        guard let endIndex else {
            return (frontmatter, markdown)
        }

        let body = lines.dropFirst(endIndex + 1).joined(separator: "\n")
        return (frontmatter, body)
    }

    private static func summary(from body: String) -> String {
        let content = body
            .components(separatedBy: .newlines)
            .filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.hasPrefix("# ") == false
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard content.count > 240 else { return content }
        let endIndex = content.index(content.startIndex, offsetBy: 240)
        return String(content[..<endIndex])
    }

    private static func sources(from rawValue: String?) -> [String] {
        guard let rawValue else { return [] }

        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
            return trimmed
                .dropFirst()
                .dropLast()
                .split(separator: ",")
                .map { item in
                    item.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'")))
                }
                .filter { $0.isEmpty == false }
        }

        return [trimmed].filter { $0.isEmpty == false }
    }

    private static func titleFromFileName(_ fileName: String) -> String {
        fileName
            .split(separator: "-")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}
