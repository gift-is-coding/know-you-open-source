import Foundation

struct KnowledgeOntologySyncResult: Equatable {
    let projectRoot: URL
    let exportedFileNames: [String]
}

enum KnowledgeOntologyProjectExporterError: LocalizedError {
    case noDiaryMarkdownFound

    var errorDescription: String? {
        switch self {
        case .noDiaryMarkdownFound:
            return "No KnowYou diary Markdown files were found to sync."
        }
    }
}

struct KnowledgeOntologyProjectExporter {
    let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func syncDiaries(sourceVault: URL, projectRoot: URL) throws -> KnowledgeOntologySyncResult {
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

        return KnowledgeOntologySyncResult(
            projectRoot: projectRoot,
            exportedFileNames: exportedFileNames
        )
    }

    func ensureProject(at projectRoot: URL) throws {
        let directories = [
            "raw/sources",
            "raw/assets",
            "wiki/entities",
            "wiki/concepts",
            "wiki/sources",
            "wiki/queries",
            "wiki/comparisons",
            "wiki/synthesis",
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
            throw KnowledgeOntologyProjectExporterError.noDiaryMarkdownFound
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
            throw KnowledgeOntologyProjectExporterError.noDiaryMarkdownFound
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
    # KnowYou 知识本体 Schema

    ## 页面类型

    | Type | Directory | Purpose |
    |------|-----------|---------|
    | entity | wiki/entities/ | 人、公司、项目、产品、工具、地点等具名主体 |
    | concept | wiki/concepts/ | 抽象主题、方法、偏好、长期问题、价值判断 |
    | source | wiki/sources/ | 来自 KnowYou 日记或外部资料的来源记录 |
    | query | wiki/queries/ | 需要继续追问或验证的问题 |
    | comparison | wiki/comparisons/ | 多个主体或方案之间的对比 |
    | synthesis | wiki/synthesis/ | 跨日记、跨资料的综合结论 |

    ## 抽取规则

    - 优先从 `raw/sources/knowyou-diary-*.md` 中抽取用户真实经历、任务、关系、偏好和反复出现的问题。
    - 实体应尽量使用稳定名称，例如人名、项目名、公司名、产品名。
    - 关系应保留来源日期，并能追溯到具体 source。
    - 不确定的信息进入 query，不要硬写成事实。
    - 敏感信息只记录必要摘要，不复制密钥、密码、token 或完整账号。

    ## Frontmatter

    ```yaml
    ---
    type: entity | concept | source | query | comparison | synthesis | overview
    title: 可读标题
    tags: []
    related: []
    created: YYYY-MM-DD
    updated: YYYY-MM-DD
    ---
    ```

    ## 交叉引用

    - 页面之间使用 `[[page-slug]]` 引用。
    - 每个重要实体和概念都应进入 `wiki/index.md`。
    - synthesis 页面必须引用参与推理的 source。
    """

    private static let purposeMarkdown = """
    # Project Purpose

    ## 目标

    把 KnowYou 的每日上下文沉淀为可查询、可追溯、可被 agent 调用的个人知识本体。

    ## 关键问题

    1. 哪些人、项目、工具和主题反复出现在我的日记里？
    2. 它们之间有什么关系、进展和未完成事项？
    3. 其他 agent 在执行任务前应该知道哪些长期上下文？

    ## 范围

    **In scope:**
    - KnowYou 每日日记
    - 从日记抽取实体、概念、关系、来源
    - 图谱、搜索、review 与综合结论

    **Out of scope:**
    - 未经过 KnowYou 隐私边界处理的 SQLite 原始事件直出
    - 多用户团队协作知识库
    """

    private static let indexMarkdown = """
    # Wiki Index

    ## Entities

    ## Concepts

    ## Sources

    ## Queries

    ## Comparisons

    ## Synthesis
    """

    private static let logMarkdown = """
    # Research Log

    - KnowYou knowledge ontology project created.
    """

    private static let overviewMarkdown = """
    ---
    type: overview
    title: KnowYou Context Overview
    tags: []
    related: []
    ---

    # Overview

    这里汇总 KnowYou 日记抽取出的主体、关系、主题和长期上下文。
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
