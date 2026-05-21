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

        while lineStart < markdown.endIndex {
            let lineEnd = markdown[lineStart...].firstIndex(of: "\n") ?? markdown.endIndex
            let line = markdown[lineStart..<lineEnd].trimmingCharacters(in: .whitespacesAndNewlines)

            if line == "---" {
                return FrontmatterBlock(contentRange: contentStart..<lineStart, insertionIndex: contentStart)
            }

            guard lineEnd < markdown.endIndex else {
                break
            }
            lineStart = markdown.index(after: lineEnd)
        }

        return nil
    }

    private func hasDailyMemoryExportMarker(in markdown: String, frontmatterBlock: FrontmatterBlock) -> Bool {
        markdown[frontmatterBlock.contentRange]
            .split(whereSeparator: \.isNewline)
            .contains { $0.trimmingCharacters(in: .whitespaces) == Self.dailyMemoryExportMarker }
    }
}
