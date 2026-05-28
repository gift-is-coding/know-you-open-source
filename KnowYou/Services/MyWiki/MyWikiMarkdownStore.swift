import Foundation

struct MyWikiMarkdownStore {
    let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func loadDashboard(projectRoot: URL) throws -> MyWikiDashboardSnapshot {
        var entriesByCategoryID: [String: [MyWikiEntry]] = [:]
        for category in MyWikiCategory.nativeCategories {
            entriesByCategoryID[category.id] = try loadEntries(category: category, projectRoot: projectRoot)
        }

        return MyWikiDashboardSnapshot(entriesByCategoryID: entriesByCategoryID)
    }

    private func loadEntries(
        category: MyWikiCategory,
        projectRoot: URL
    ) throws -> [MyWikiEntry] {
        let directory = projectRoot.appending(path: "wiki/\(category.id)", directoryHint: .isDirectory)
        guard fileManager.fileExists(atPath: directory.path) else { return [] }

        let files = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension.lowercased() == "md" }
        guard files.isEmpty == false else { return [] }

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
            summary: Self.summary(from: parsed.body, frontmatter: parsed.frontmatter),
            sourceNames: Self.array(from: parsed.frontmatter["sources"]),
            aliases: Self.array(from: parsed.frontmatter["aliases"]),
            related: Self.array(from: parsed.frontmatter["related"]),
            tags: Self.array(from: parsed.frontmatter["tags"]),
            confidence: parsed.frontmatter["confidence"] ?? "",
            mentions: Self.mentions(from: parsed.body),
            markdownBody: parsed.body.trimmingCharacters(in: .whitespacesAndNewlines),
            fileURL: file
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

    private static func summary(from body: String, frontmatter: [String: String]) -> String {
        if let description = cleanSummary(frontmatter["description"]), description.isEmpty == false {
            return description
        }
        if let summarySection = section(named: "Summary", from: body), summarySection.isEmpty == false {
            return summarySection
        }
        return firstBodyParagraph(from: body)
    }

    private static func section(named heading: String, from body: String) -> String? {
        let lines = body.components(separatedBy: .newlines)
        var collected: [String] = []
        var isCollecting = false
        let normalizedHeading = heading.lowercased()

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("## ") {
                let title = trimmed
                    .dropFirst(3)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                if isCollecting {
                    break
                }
                if title == normalizedHeading {
                    isCollecting = true
                }
                continue
            }

            if isCollecting {
                collected.append(line)
            }
        }

        return cleanSummary(collected.joined(separator: "\n"))
    }

    private static func firstBodyParagraph(from body: String) -> String {
        var paragraph: [String] = []
        for line in body.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("#") == false else {
                if paragraph.isEmpty == false {
                    break
                }
                continue
            }
            if trimmed.isEmpty {
                if paragraph.isEmpty == false {
                    break
                }
                continue
            }
            paragraph.append(trimmed)
        }

        return cleanSummary(paragraph.joined(separator: " ")) ?? ""
    }

    private static func cleanSummary(_ rawValue: String?) -> String? {
        guard let rawValue else { return nil }
        let collapsed = rawValue
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { $0.isEmpty == false }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard collapsed.count > 480 else { return collapsed }
        let endIndex = collapsed.index(collapsed.startIndex, offsetBy: 480)
        return String(collapsed[..<endIndex])
    }

    static func array(from rawValue: String?) -> [String] {
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

    static func frontmatterArray(_ values: [String]) -> String {
        "[\(values.uniqued().map { "\"\($0.replacingOccurrences(of: "\"", with: "\\\""))\"" }.joined(separator: ", "))]"
    }

    static func parseMarkdownDocument(_ markdown: String) -> (frontmatter: [String: String], body: String) {
        parseMarkdown(markdown)
    }

    static func mentions(from body: String) -> [MyWikiMention] {
        body.components(separatedBy: .newlines).compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("- ") else { return nil }
            let content = trimmed.dropFirst(2)
            guard content.count >= 11 else { return nil }
            let day = String(content.prefix(10))
            guard day.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else {
                return nil
            }
            var text = String(content.dropFirst(10)).trimmingCharacters(in: .whitespacesAndNewlines)
            if text.hasPrefix(":") || text.hasPrefix("-") {
                text = String(text.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return MyWikiMention(day: day, text: text)
        }
    }

    private static func titleFromFileName(_ fileName: String) -> String {
        fileName
            .split(separator: "-")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}

enum MyWikiRenameResult: Equatable {
    case renamed
    case conflict(existingTitle: String)
}

struct MyWikiRenameService {
    let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func rename(
        _ entry: MyWikiEntry,
        to newTitle: String,
        aliases: [String],
        summary: String,
        projectRoot: URL
    ) throws -> MyWikiRenameResult {
        let trimmedTitle = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let snapshot = try MyWikiMarkdownStore(fileManager: fileManager).loadDashboard(projectRoot: projectRoot)
        if let conflict = snapshot.entries(for: entry.category).first(where: { other in
            other.id != entry.id && (
                other.title.caseInsensitiveCompare(trimmedTitle) == .orderedSame
                    || Self.slug(for: other.title) == Self.slug(for: trimmedTitle)
            )
        }) {
            return .conflict(existingTitle: conflict.title)
        }

        let existingMarkdown = try String(contentsOf: entry.fileURL, encoding: .utf8)
        let parsed = MyWikiMarkdownStore.parseMarkdownDocument(existingMarkdown)
        var mergedAliases = aliases
        if entry.title.caseInsensitiveCompare(trimmedTitle) != .orderedSame {
            mergedAliases.append(entry.title)
        }
        mergedAliases = mergedAliases.uniqued().filter { $0.caseInsensitiveCompare(trimmedTitle) != .orderedSame }

        let body = Self.rewrittenBody(originalBody: parsed.body, title: trimmedTitle, summary: summary)
        let markdown = Self.markdown(
            type: entry.category.frontmatterType,
            title: trimmedTitle,
            aliases: mergedAliases,
            related: entry.related,
            sources: entry.sourceNames,
            confidence: entry.confidence,
            body: body
        )
        try markdown.write(to: entry.fileURL, atomically: true, encoding: .utf8)
        return .renamed
    }

    static func slug(for title: String) -> String {
        let allowed = CharacterSet.alphanumerics
        let parts = title.lowercased().unicodeScalars.map { scalar -> Character in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        return String(parts)
            .split(separator: "-")
            .joined(separator: "-")
    }

    private static func rewrittenBody(originalBody: String, title: String, summary: String) -> String {
        let lines = originalBody.components(separatedBy: .newlines)
        let bodyWithoutTitle = lines.drop { line in
            line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || line.hasPrefix("# ")
        }
        let trailing = bodyWithoutTitle.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        if trailing.isEmpty {
            return "# \(title)\n\n\(summary)"
        }
        return "# \(title)\n\n\(summary)\n\n\(trailing)"
    }

    static func markdown(
        type: String,
        title: String,
        aliases: [String],
        related: [String],
        sources: [String],
        confidence: String,
        body: String
    ) -> String {
        """
        ---
        type: \(type)
        title: \(title)
        aliases: \(MyWikiMarkdownStore.frontmatterArray(aliases))
        related: \(MyWikiMarkdownStore.frontmatterArray(related))
        sources: \(MyWikiMarkdownStore.frontmatterArray(sources))
        confidence: \(confidence.isEmpty ? "medium" : confidence)
        ---

        \(body.trimmingCharacters(in: .whitespacesAndNewlines))
        """
    }
}

struct MyWikiDuplicateSuggestion: Equatable {
    let entries: [MyWikiEntry]
    let reason: String
    let confidence: String
}

struct MyWikiDuplicateService {
    let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func findDuplicateSuggestions(projectRoot: URL) throws -> [MyWikiDuplicateSuggestion] {
        let snapshot = try MyWikiMarkdownStore(fileManager: fileManager).loadDashboard(projectRoot: projectRoot)
        let candidates = snapshot.primaryEntries
        var suggestions: [MyWikiDuplicateSuggestion] = []

        for (index, entry) in candidates.enumerated() {
            for other in candidates.dropFirst(index + 1) {
                guard entry.category == other.category else { continue }
                if Self.looksDuplicate(entry, other) {
                    suggestions.append(
                        MyWikiDuplicateSuggestion(
                            entries: [entry, other],
                            reason: "Names or aliases overlap.",
                            confidence: "medium"
                        )
                    )
                }
            }
        }

        return suggestions
    }

    func merge(suggestion: MyWikiDuplicateSuggestion, canonicalID: String, projectRoot: URL) throws {
        guard let canonical = suggestion.entries.first(where: { $0.id == canonicalID }) else { return }
        let mergedAway = suggestion.entries.filter { $0.id != canonicalID }
        guard mergedAway.isEmpty == false else { return }

        let backupDir = projectRoot
            .appending(path: ".llm-wiki/page-history", directoryHint: .isDirectory)
            .appending(path: "mywiki-dedup-\(Int(Date().timeIntervalSince1970))", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: backupDir, withIntermediateDirectories: true)

        var aliases = canonical.aliases + [canonical.title]
        var related = canonical.related
        var sources = canonical.sourceNames
        var bodyParts = [canonical.markdownBody]

        for entry in mergedAway {
            let backupURL = backupDir.appending(path: entry.fileURL.lastPathComponent)
            if fileManager.fileExists(atPath: entry.fileURL.path) {
                try fileManager.copyItem(at: entry.fileURL, to: backupURL)
            }
            aliases.append(contentsOf: entry.aliases + [entry.title])
            related.append(contentsOf: entry.related)
            sources.append(contentsOf: entry.sourceNames)
            bodyParts.append(entry.markdownBody)
            try? fileManager.removeItem(at: entry.fileURL)
        }

        let canonicalBackup = backupDir.appending(path: canonical.fileURL.lastPathComponent)
        if fileManager.fileExists(atPath: canonical.fileURL.path) {
            try? fileManager.copyItem(at: canonical.fileURL, to: canonicalBackup)
        }

        let body = bodyParts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
            .joined(separator: "\n\n## Merged Notes\n\n")
        let markdown = MyWikiRenameService.markdown(
            type: canonical.category.frontmatterType,
            title: canonical.title,
            aliases: aliases.uniqued().filter { $0.caseInsensitiveCompare(canonical.title) != .orderedSame },
            related: related.uniqued(),
            sources: sources.uniqued(),
            confidence: canonical.confidence,
            body: body
        )
        try markdown.write(to: canonical.fileURL, atomically: true, encoding: .utf8)
        try rewriteReferences(from: mergedAway, to: canonical, projectRoot: projectRoot)
    }

    private static func looksDuplicate(_ lhs: MyWikiEntry, _ rhs: MyWikiEntry) -> Bool {
        let leftNames = Set(([lhs.title] + lhs.aliases).map(normalizedName))
        let rightNames = Set(([rhs.title] + rhs.aliases).map(normalizedName))
        return leftNames.isDisjoint(with: rightNames) == false
            || leftNames.contains(MyWikiRenameService.slug(for: rhs.title))
            || rightNames.contains(MyWikiRenameService.slug(for: lhs.title))
    }

    private static func normalizedName(_ value: String) -> String {
        MyWikiRenameService.slug(for: value)
    }

    private func rewriteReferences(from mergedAway: [MyWikiEntry], to canonical: MyWikiEntry, projectRoot: URL) throws {
        let wikiRoot = projectRoot.appending(path: "wiki", directoryHint: .isDirectory)
        guard fileManager.fileExists(atPath: wikiRoot.path) else { return }

        let files = fileManager.enumerator(
            at: wikiRoot,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension.lowercased() == "md" } ?? []

        let replacements = mergedAway.flatMap { entry in
            [entry.id, entry.title] + entry.aliases
        }
        .filter { $0.isEmpty == false }
        .uniqued()

        for file in files {
            var markdown = try String(contentsOf: file, encoding: .utf8)
            let original = markdown
            for replacement in replacements {
                markdown = markdown.replacingOccurrences(of: "[[\(replacement)]]", with: "[[\(canonical.id)]]")
            }
            if markdown != original {
                try markdown.write(to: file, atomically: true, encoding: .utf8)
            }
        }
    }
}

extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen: Set<Element> = []
        return filter { seen.insert($0).inserted }
    }
}
