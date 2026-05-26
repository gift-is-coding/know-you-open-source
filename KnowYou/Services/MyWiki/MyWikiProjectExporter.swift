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
        ] + schema.categories.map(\.directory)).uniqued()

        for directory in directories {
            try fileManager.createDirectory(
                at: projectRoot.appending(path: directory, directoryHint: .isDirectory),
                withIntermediateDirectories: true
            )
        }

        try write(projectRoot.appending(path: "schema.md"), contents: MyWikiSchemaMarkdownRenderer().render(schema))
        try writeIfMissingOrLegacy(
            projectRoot.appending(path: "purpose.md"),
            contents: Self.purposeMarkdown,
            legacyMarkers: Self.legacyPurposeMarkers
        )
        try writeIfMissing(projectRoot.appending(path: "wiki/index.md"), contents: Self.indexMarkdown(for: schema))
        try writeIfMissing(projectRoot.appending(path: "wiki/log.md"), contents: Self.logMarkdown)
        try writeIfMissingOrLegacy(
            projectRoot.appending(path: "wiki/overview.md"),
            contents: Self.overviewMarkdown,
            legacyMarkers: Self.legacyOverviewMarkers
        )
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

    private func writeIfMissingOrLegacy(_ url: URL, contents: String, legacyMarkers: [String]) throws {
        guard fileManager.fileExists(atPath: url.path) else {
            try write(url, contents: contents)
            return
        }

        let existing = try String(contentsOf: url, encoding: .utf8)
        guard legacyMarkers.contains(where: existing.contains) else { return }
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
        tags: [knowyou, diary]
        ---

        \(markdown)
        """
    }

    private static let purposeMarkdown = """
    # Project Purpose

    ## 目标

    把 KnowYou 的每日记录整理成可阅读、可搜索、可追溯的 My Wiki。

    ## 关键问题

    1. 最近哪些 Sources 已经被整理，哪些还没有进入 My Wiki？
    2. 哪些 Entities（人、组织、工具、产品、项目或其他具体对象）值得长期保留？
    3. 哪些 Concepts（主题、偏好、决策、问题、工作模式和开放事项）能帮助后续 agent 理解背景？
    4. Entity 页面可以用宽标签帮助筛选：person、project、organization、other；需要时再追加更具体的标签。

    ## 范围

    **In scope:**
    - KnowYou 每日日记
    - 用 llm_wiki 原生 Sources、Entities、Concepts 结构整理可读、可追溯的内容
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

    这里汇总 KnowYou 日记整理出的 Sources、Entities 和 Concepts。Sources 保留来源线索，Entities 记录具体对象，Concepts 收纳主题、偏好、决策、问题、工作模式和开放事项。
    """

    private static let legacyPurposeMarkers = [
        "个人知识本体",
        "哪些人、项目、工具和主题",
        "人物、项目、事件、主题、偏好、待办"
    ]

    private static let legacyOverviewMarkers = [
        "人物、项目、事件、主题、偏好、待办",
        "这里汇总 KnowYou 日记整理出的人物"
    ]

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
