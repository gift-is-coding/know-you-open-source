import Foundation

struct MyWikiSyncResult: Equatable {
    let projectRoot: URL
    let exportedFileNames: [String]
}

enum MyWikiProjectExporterError: LocalizedError {
    case noDiaryMarkdownFound

    var errorDescription: String? {
        switch self {
        case .noDiaryMarkdownFound:
            return "No KnowYou diary Markdown files were found to sync."
        }
    }
}

struct MyWikiProjectExporter {
    let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func syncDiaries(sourceVault: URL, projectRoot: URL) throws -> MyWikiSyncResult {
        try ensureProject(at: projectRoot)

        let diaryFiles = try markdownDiaryFiles(in: sourceVault)
        let rawSources = projectRoot.appending(path: "raw/sources", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: rawSources, withIntermediateDirectories: true)

        var exportedFileNames: [String] = []
        for diaryFile in diaryFiles {
            let dayKey = diaryFile.deletingPathExtension().lastPathComponent
            let exportedFileName = "knowyou-diary-\(dayKey).md"
            let destination = rawSources.appending(path: exportedFileName)
            let markdown = try String(contentsOf: diaryFile, encoding: .utf8)
            let contents = Self.exportedDiaryMarkdown(dayKey: dayKey, markdown: markdown)
            try contents.write(to: destination, atomically: true, encoding: .utf8)
            exportedFileNames.append(exportedFileName)
        }

        return MyWikiSyncResult(
            projectRoot: projectRoot,
            exportedFileNames: exportedFileNames
        )
    }

    func ensureProject(at projectRoot: URL) throws {
        let directories = [
            "raw/sources",
            "raw/assets",
            "wiki/sources",
            "wiki/entities",
            "wiki/concepts",
            ".obsidian"
        ]

        for directory in directories {
            try fileManager.createDirectory(
                at: projectRoot.appending(path: directory, directoryHint: .isDirectory),
                withIntermediateDirectories: true
            )
        }

        try removeIfExists(projectRoot.appending(path: "mywiki.schema.json"))
        try removeIfExists(projectRoot.appending(path: "schema.md"))
        try removeIfExists(projectRoot.appending(path: "purpose.md"))
        try writeIfMissing(projectRoot.appending(path: ".obsidian/app.json"), contents: Self.obsidianAppJSON)
        try writeIfMissing(projectRoot.appending(path: ".obsidian/appearance.json"), contents: Self.obsidianAppearanceJSON)
        try writeIfMissing(projectRoot.appending(path: ".obsidian/core-plugins.json"), contents: Self.obsidianCorePluginsJSON)
    }

    private func markdownDiaryFiles(in sourceVault: URL) throws -> [URL] {
        guard fileManager.fileExists(atPath: sourceVault.path) else {
            throw MyWikiProjectExporterError.noDiaryMarkdownFound
        }

        let files = try fileManager.contentsOfDirectory(
            at: sourceVault,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        let dayKeyPattern = #"^\d{4}-\d{2}-\d{2}$"#
        let diaries = files
            .filter { $0.pathExtension == "md" }
            .filter { file in
                file.deletingPathExtension().lastPathComponent.range(
                    of: dayKeyPattern,
                    options: .regularExpression
                ) != nil
            }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }

        guard diaries.isEmpty == false else {
            throw MyWikiProjectExporterError.noDiaryMarkdownFound
        }

        return diaries
    }

    private func writeIfMissing(_ url: URL, contents: String) throws {
        guard fileManager.fileExists(atPath: url.path) == false else { return }
        try write(url, contents: contents)
    }

    private func removeIfExists(_ url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    private func write(_ url: URL, contents: String) throws {
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func exportedDiaryMarkdown(dayKey _: String, markdown: String) -> String {
        markdown.hasSuffix("\n") ? markdown : "\(markdown)\n"
    }

    static func exportedDiaryMarkdownForCatalog(dayKey: String, markdown: String) -> String {
        exportedDiaryMarkdown(dayKey: dayKey, markdown: markdown)
    }

    private static let obsidianAppJSON = """
    {
      "attachmentFolderPath": "raw/assets",
      "userIgnoreFilters": [
        ".cache",
        ".llm-wiki",
        ".superpowers"
      ],
      "useMarkdownLinks": false,
      "newLinkFormat": "shortest",
      "showUnsupportedFiles": false
    }
    """

    private static let obsidianAppearanceJSON = """
    {
      "baseFontSize": 16,
      "theme": "obsidian"
    }
    """

    private static let obsidianCorePluginsJSON = """
    {
      "file-explorer": true,
      "global-search": true,
      "graph": true,
      "backlink": true,
      "tag-pane": true,
      "page-preview": true,
      "outgoing-link": true,
      "starred": true
    }
    """
}
