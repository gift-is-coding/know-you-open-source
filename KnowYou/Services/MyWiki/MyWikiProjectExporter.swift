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
            "wiki/people",
            "wiki/projects",
            "wiki/themes",
            "wiki/preferences",
            "wiki/open-loops",
            "wiki/summaries",
            "wiki/sources",
            ".obsidian"
        ]

        for directory in directories {
            try fileManager.createDirectory(
                at: projectRoot.appending(path: directory, directoryHint: .isDirectory),
                withIntermediateDirectories: true
            )
        }

        try writeIfMissing(projectRoot.appending(path: "schema.md"), contents: Self.schemaMarkdown)
        try writeIfMissing(projectRoot.appending(path: "purpose.md"), contents: Self.purposeMarkdown)
        try writeIfMissing(projectRoot.appending(path: "wiki/index.md"), contents: Self.indexMarkdown)
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

    private func writeIfMissing(_ url: URL, contents: String) throws {
        guard fileManager.fileExists(atPath: url.path) == false else { return }
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

    private static let schemaMarkdown = """
    # My Wiki Schema

    ## 页面类型

    | 类型 | 目录 | 用途 |
    |------|------|------|
    | 人物 | wiki/people/ | 日记里反复出现的人、合作对象、朋友、家人 |
    | 项目 | wiki/projects/ | 正在推进或反复被提到的工作、产品、研究、生活计划 |
    | 主题 | wiki/themes/ | 长期关注的话题、方法、困惑、价值判断 |
    | 偏好 | wiki/preferences/ | 用户稳定的选择倾向、工作方式、沟通偏好 |
    | 待办 | wiki/open-loops/ | 尚未解决、需要跟进、需要别人协助的事项 |
    | 总结 | wiki/summaries/ | 按周、月、主题聚合后的可读结论 |
    | 来源 | wiki/sources/ | 从 KnowYou 日记或外部资料整理出的来源索引 |

    ## 抽取规则

    - 优先从 `raw/sources/knowyou-diary-*.md` 中抽取真实经历、任务、关系、偏好和反复出现的问题。
    - 对普通用户可见的页面应使用自然语言标题，例如“重要的人”“最近在做的项目”“我反复提到的主题”。
    - 内部可以保留稳定 ID，但页面正文必须能让用户直接读懂。
    - 每个重要结论都要保留来源日期，方便回到原始日记核对。
    - 不确定的信息进入待确认条目，不要硬写成事实。
    - 敏感信息只记录必要摘要，不复制密钥、密码、token 或完整账号。

    ## Frontmatter

    ```yaml
    ---
    type: person | project | theme | preference | open-loop | summary | source | overview
    title: 可读标题
    aliases: []
    tags: []
    related: []
    source_days: []
    confidence: high | medium | low
    created: YYYY-MM-DD
    updated: YYYY-MM-DD
    ---
    ```

    ## 交叉引用

    - 页面之间使用 `[[page-slug]]` 引用。
    - 重要人物、项目、主题、偏好和待办都应进入 `wiki/index.md`。
    - 总结页必须引用参与整理的来源。
    """

    private static let purposeMarkdown = """
    # Project Purpose

    ## 目标

    把 KnowYou 的每日记录整理成可阅读、可搜索、可追溯的 My Wiki。

    ## 关键问题

    1. 最近哪些人、项目、主题和偏好反复出现在我的日记里？
    2. 哪些事情需要继续跟进？
    3. 其他 agent 在执行任务前应该知道哪些长期背景？

    ## 范围

    **In scope:**
    - KnowYou 每日日记
    - 从日记整理人物、项目、主题、偏好、待办、总结和来源
    - 可读页面、搜索索引、agent 可调用摘要

    **Out of scope:**
    - 未经过 KnowYou 隐私边界处理的 SQLite 原始事件直出
    - 多用户团队协作知识库
    """

    private static let indexMarkdown = """
    # My Wiki Index

    ## People

    ## Projects

    ## Themes

    ## Preferences

    ## Open Loops

    ## Summaries

    ## Sources
    """

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

    这里汇总 KnowYou 日记整理出的人物、项目、主题、偏好、待办和总结。
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
