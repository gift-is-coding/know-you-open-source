import Foundation

struct SyncMemoryCopyResult: Equatable {
    var copiedFileNames: [String]
    var destinationDirectoryPath: String
}

enum SyncMemoryCoordinatorError: LocalizedError {
    case noDiaryMarkdownFound

    var errorDescription: String? {
        switch self {
        case .noDiaryMarkdownFound:
            return "No diary markdown file found to sync."
        }
    }
}

struct SyncMemoryCoordinator {
    private static let dailyMemoryExportMarker = "knowyou_export: daily_memory"
    private static let dailyMemoryExportMarkerLine = dailyMemoryExportMarker + "\n"
    private static let dailyMemoryExportFrontmatter = """
    ---
    knowyou_export: daily_memory
    ---
    """ + "\n"
    private static let dailyMemoryExportMarkerPattern = #"(?i)^knowyou_export\s*:\s*daily_memory\s*$"#
    private static let trustedFrontmatterKeys: Set<String> = [
        "alias",
        "aliases",
        "author",
        "categories",
        "category",
        "created",
        "createdat",
        "date",
        "description",
        "draft",
        "id",
        "layout",
        "modified",
        "modifiedat",
        "cssclass",
        "cssclasses",
        "source",
        "status",
        "summary",
        "tag",
        "tags",
        "title",
        "type",
        "uid",
        "updated",
        "updatedat",
        "uuid",
    ]

    private struct FrontmatterBlock {
        let contentRange: Range<String.Index>
        let insertionIndex: String.Index
    }

    let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func syncDiaries(
        sourceVault: URL,
        destinations: [SyncMemoryChannel: URL]
    ) throws -> [SyncMemoryChannel: SyncMemoryCopyResult] {
        let diaryFiles = try markdownFiles(in: sourceVault)
        var results: [SyncMemoryChannel: SyncMemoryCopyResult] = [:]

        for (channel, directory) in destinations {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            for diaryFile in diaryFiles {
                let destinationFile = directory.appendingPathComponent(diaryFile.lastPathComponent)
                let markdown = try String(contentsOf: diaryFile, encoding: .utf8)
                try exportMarkdown(markdown).write(to: destinationFile, atomically: true, encoding: .utf8)
            }
            results[channel] = SyncMemoryCopyResult(
                copiedFileNames: diaryFiles.map(\.lastPathComponent),
                destinationDirectoryPath: directory.path
            )
        }

        return results
    }

    private func markdownFiles(in sourceVault: URL) throws -> [URL] {
        let files = try fileManager.contentsOfDirectory(
            at: sourceVault,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        let markdownFiles = files
            .filter { $0.pathExtension == "md" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }

        guard !markdownFiles.isEmpty else {
            throw SyncMemoryCoordinatorError.noDiaryMarkdownFound
        }

        return markdownFiles
    }

    private func exportMarkdown(_ markdown: String) -> String {
        if let frontmatterBlock = frontmatterBlock(in: markdown) {
            guard !hasDailyMemoryExportMarker(in: markdown, frontmatterBlock: frontmatterBlock) else {
                return markdown
            }

            return String(markdown[..<frontmatterBlock.insertionIndex])
                + Self.dailyMemoryExportMarkerLine
                + String(markdown[frontmatterBlock.insertionIndex...])
        }

        return Self.dailyMemoryExportFrontmatter + markdown
    }

    private func frontmatterBlock(in markdown: String) -> FrontmatterBlock? {
        guard markdown.hasPrefix("---"), let openingLineEnd = markdown.firstIndex(of: "\n") else {
            return nil
        }

        let openingLine = markdown[..<openingLineEnd].trimmingCharacters(in: .whitespacesAndNewlines)
        guard openingLine == "---" else {
            return nil
        }

        let contentStart = markdown.index(after: openingLineEnd)
        var lineStart = contentStart
        var keyValueLineCount = 0
        var hasTrustedMetadataKey = false
        var hasStructuredYAMLValue = false
        var hasDailyMemoryExportMarker = false
        var previousLineAllowsListItem = false
        var isInsideBlockScalar = false

        while lineStart < markdown.endIndex {
            let lineEnd = markdown[lineStart...].firstIndex(of: "\n") ?? markdown.endIndex
            let rawLine = String(markdown[lineStart..<lineEnd])
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)

            if line == "---" {
                // A leading thematic break can look like frontmatter; require a metadata confidence signal.
                guard hasDailyMemoryExportMarker
                    || hasTrustedMetadataKey
                    || hasStructuredYAMLValue
                    || keyValueLineCount > 1
                else {
                    return nil
                }
                return FrontmatterBlock(contentRange: contentStart..<lineStart, insertionIndex: contentStart)
            }

            if line.isEmpty || line.hasPrefix("#") {
                guard lineEnd < markdown.endIndex else {
                    break
                }
                lineStart = markdown.index(after: lineEnd)
                continue
            }

            if rawLine.range(of: Self.dailyMemoryExportMarkerPattern, options: .regularExpression) != nil {
                hasDailyMemoryExportMarker = true
                previousLineAllowsListItem = false
                isInsideBlockScalar = false
            } else if isInsideBlockScalar && startsWithIndent(rawLine) {
                hasStructuredYAMLValue = true
            } else if previousLineAllowsListItem && isYAMLListItemLine(rawLine) {
                hasStructuredYAMLValue = true
                previousLineAllowsListItem = true
                isInsideBlockScalar = false
            } else if let keyValue = yamlKeyValue(in: rawLine) {
                keyValueLineCount += 1
                hasTrustedMetadataKey = hasTrustedMetadataKey || isTrustedFrontmatterKey(keyValue.key)
                hasStructuredYAMLValue = hasStructuredYAMLValue || isYAMLBlockScalarIndicator(keyValue.value)
                previousLineAllowsListItem = keyValue.value.isEmpty
                isInsideBlockScalar = isYAMLBlockScalarIndicator(keyValue.value)
            } else {
                return nil
            }

            guard lineEnd < markdown.endIndex else {
                break
            }
            lineStart = markdown.index(after: lineEnd)
        }

        return nil
    }

    private func yamlKeyValue(in line: String) -> (key: String, value: String)? {
        let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let colonIndex = trimmedLine.firstIndex(of: ":") else {
            return nil
        }

        let key = String(trimmedLine[..<colonIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, key.allSatisfy(isYAMLKeyCharacter) else {
            return nil
        }

        let valueStart = trimmedLine.index(after: colonIndex)
        let value = String(trimmedLine[valueStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return (key, value)
    }

    private func isYAMLKeyCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_" || character == "-"
    }

    private func isTrustedFrontmatterKey(_ key: String) -> Bool {
        let normalizedKey = key
            .lowercased()
            .filter { $0 != "_" && $0 != "-" }
        return Self.trustedFrontmatterKeys.contains(normalizedKey)
    }

    private func isYAMLListItemLine(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("- ")
    }

    private func isYAMLBlockScalarIndicator(_ value: String) -> Bool {
        ["|", "|-", "|+", ">", ">-", ">+"].contains(value)
    }

    private func startsWithIndent(_ line: String) -> Bool {
        line.first == " " || line.first == "\t"
    }

    private func hasDailyMemoryExportMarker(in markdown: String, frontmatterBlock: FrontmatterBlock) -> Bool {
        markdown[frontmatterBlock.contentRange]
            .split(whereSeparator: \.isNewline)
            .contains { line in
                String(line).range(
                    of: Self.dailyMemoryExportMarkerPattern,
                    options: .regularExpression
                ) != nil
            }
    }
}
