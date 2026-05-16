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
        let schema = try ensureSchemaConfig(at: projectRoot)
        let directories = ([
            "raw/sources",
            "raw/assets",
            "wiki",
            ".obsidian"
        ] + schema.categories.flatMap(\.directoryCandidates)).uniqued()

        for directory in directories {
            try fileManager.createDirectory(
                at: projectRoot.appending(path: directory, directoryHint: .isDirectory),
                withIntermediateDirectories: true
            )
        }

        try write(projectRoot.appending(path: "schema.md"), contents: MyWikiSchemaMarkdownRenderer().render(schema))
        try writeIfMissing(projectRoot.appending(path: "purpose.md"), contents: Self.purposeMarkdown)
        try writeIfMissing(projectRoot.appending(path: "wiki/index.md"), contents: Self.indexMarkdown(for: schema))
        try writeIfMissing(projectRoot.appending(path: "wiki/log.md"), contents: Self.logMarkdown)
        try writeIfMissing(projectRoot.appending(path: "wiki/overview.md"), contents: Self.overviewMarkdown)
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

    private func ensureSchemaConfig(at projectRoot: URL) throws -> MyWikiSchemaConfig {
        let schemaURL = projectRoot.appending(path: "mywiki.schema.json")
        if fileManager.fileExists(atPath: schemaURL.path) {
            let data = try Data(contentsOf: schemaURL)
            return try JSONDecoder().decode(MyWikiSchemaConfig.self, from: data)
        }

        let schema = try MyWikiSchemaConfig.defaultPersonalContext()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(schema)
        try fileManager.createDirectory(
            at: schemaURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: schemaURL, options: .atomic)
        return schema
    }

    private func writeIfMissing(_ url: URL, contents: String) throws {
        guard fileManager.fileExists(atPath: url.path) == false else { return }
        try write(url, contents: contents)
    }

    private func write(_ url: URL, contents: String) throws {
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func exportedDiaryMarkdown(dayKey: String, markdown: String) -> String {
        """
        ---
        type: knowyou-diary
        source: KnowYou
        day: \(dayKey)
        ---

        \(markdown)
        """
    }

    private static let purposeMarkdown = """
    # Project Purpose

    ## 目标

    把 KnowYou 的每日记录整理成可阅读、可搜索、可追溯的 My Wiki。

    ## 关键问题

    1. 最近哪些人、项目、事件、主题和偏好反复出现在我的日记里？
    2. 哪些事情需要继续跟进？
    3. 其他 agent 在执行任务前应该知道哪些长期背景？

    ## 范围

    **In scope:**
    - KnowYou 每日日记
    - 从日记整理人物、项目、事件、主题、偏好、待办、总结和来源
    - 可读页面、搜索索引、agent 可调用摘要

    **Out of scope:**
    - 未经过 KnowYou 隐私边界处理的 SQLite 原始事件直出
    - 多用户团队协作知识库
    """

    private static func indexMarkdown(for schema: MyWikiSchemaConfig) -> String {
        let sections = schema.categories
            .map { "## \($0.displayName)" }
            .joined(separator: "\n\n")
        return "# My Wiki Index\n\n\(sections)\n"
    }

    private static let logMarkdown = """
    # My Wiki Log

    - My Wiki project created.
    """

    private static let overviewMarkdown = """
    ---
    type: overview
    title: My Wiki Overview
    tags: []
    related: []
    ---

    # Overview

    这里汇总 KnowYou 日记整理出的人物、项目、事件、主题、偏好、待办和总结。
    """

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
