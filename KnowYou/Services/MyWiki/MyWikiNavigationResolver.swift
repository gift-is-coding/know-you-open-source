import Foundation

struct MyWikiNavigationResolver {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func resolveSourceURL(_ sourceName: String, projectRoot: URL) -> URL? {
        let trimmed = sourceName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }

        let directCandidate = projectRoot.appending(path: trimmed)
        if trimmed.contains("/") && fileManager.fileExists(atPath: directCandidate.path) {
            return directCandidate
        }

        let sourceFileNames = candidateFileNames(for: trimmed)
        let sourceRoots = [
            projectRoot.appending(path: "wiki/sources", directoryHint: .isDirectory),
            projectRoot.appending(path: "raw/sources", directoryHint: .isDirectory)
        ]

        for root in sourceRoots {
            for fileName in sourceFileNames {
                let candidate = root.appending(path: fileName)
                if fileManager.fileExists(atPath: candidate.path) {
                    return candidate
                }
            }
        }

        return nil
    }

    func resolveRelatedEntry(_ reference: String, snapshot: MyWikiDashboardSnapshot) -> MyWikiEntry? {
        let normalized = normalizedReference(reference)
        guard normalized.isEmpty == false else { return nil }

        return snapshot.allEntries.first { entry in
            let entryTitleSlug = MyWikiRenameService.slug(for: entry.title)
            let aliasSlugs = entry.aliases.map { MyWikiRenameService.slug(for: $0) }
            return entry.id == normalized
                || entryTitleSlug == normalized
                || aliasSlugs.contains(normalized)
        }
    }

    private func candidateFileNames(for sourceName: String) -> [String] {
        let lastComponent = URL(fileURLWithPath: sourceName).lastPathComponent
        if lastComponent.contains(".") {
            return [lastComponent]
        }
        return [lastComponent, "\(lastComponent).md"]
    }

    private func normalizedReference(_ reference: String) -> String {
        var value = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("[[") && value.hasSuffix("]]") {
            value = String(value.dropFirst(2).dropLast(2))
            if let pipe = value.firstIndex(of: "|") {
                value = String(value[..<pipe])
            }
        }

        value = URL(fileURLWithPath: value).deletingPathExtension().lastPathComponent
        return MyWikiRenameService.slug(for: value)
    }
}
