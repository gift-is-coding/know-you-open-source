import Foundation

struct MyWikiStarterExtractor {
    let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    @discardableResult
    func materialize(projectRoot: URL) throws -> Int {
        let sources = try loadSources(projectRoot: projectRoot)
        guard sources.isEmpty == false else { return 0 }

        try ensureDirectories(projectRoot: projectRoot)

        var written = 0
        written += try writeSummary(projectRoot: projectRoot, sources: sources)
        written += try writeProjects(projectRoot: projectRoot, sources: sources)
        written += try writeThemes(projectRoot: projectRoot, sources: sources)
        written += try writePreferences(projectRoot: projectRoot, sources: sources)
        written += try writeOpenLoops(projectRoot: projectRoot, sources: sources)
        try writeIndex(projectRoot: projectRoot)
        try appendLog(projectRoot: projectRoot, fileCount: written, sourceCount: sources.count)

        return written
    }

    private func loadSources(projectRoot: URL) throws -> [DiarySource] {
        let rawSources = projectRoot.appending(path: "raw/sources", directoryHint: .isDirectory)
        guard fileManager.fileExists(atPath: rawSources.path) else { return [] }

        let files = try fileManager.contentsOfDirectory(
            at: rawSources,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        return try files
            .filter { $0.pathExtension == "md" }
            .filter { $0.lastPathComponent.hasPrefix("knowyou-diary-") }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
            .map { file in
                let text = try String(contentsOf: file, encoding: .utf8)
                return DiarySource(
                    fileName: file.lastPathComponent,
                    day: day(from: file.lastPathComponent),
                    text: stripFrontmatter(text)
                )
            }
    }

    private func ensureDirectories(projectRoot: URL) throws {
        for directory in [
            "wiki/summaries",
            "wiki/projects",
            "wiki/themes",
            "wiki/preferences",
            "wiki/open-loops"
        ] {
            try fileManager.createDirectory(
                at: projectRoot.appending(path: directory, directoryHint: .isDirectory),
                withIntermediateDirectories: true
            )
        }
    }

    private func writeSummary(projectRoot: URL, sources: [DiarySource]) throws -> Int {
        let latest = sources.prefix(7)
        let highlights = latest.flatMap { source in
            source.extractHighlights(limit: 2).map { "- \(source.day)：\($0)" }
        }
        let body = """
        # 最近日记总结

        已整理 \(sources.count) 篇 KnowYou 日记，最近日期是 \(sources.first?.day ?? "未知日期")。

        ## 最近线索

        \(highlights.isEmpty ? "- 暂时没有提取到稳定线索。" : highlights.joined(separator: "\n"))
        """

        try writePage(
            projectRoot: projectRoot,
            relativePath: "wiki/summaries/recent-diary-summary.md",
            type: "summary",
            title: "最近日记总结",
            sources: latest.map(\.fileName),
            body: body
        )
        return 1
    }

    private func writeProjects(projectRoot: URL, sources: [DiarySource]) throws -> Int {
        let candidates = [
            Candidate(title: "KnowYou", slug: "knowyou", keywords: ["knowyou", "日记", "产品"]),
            Candidate(title: "My Wiki", slug: "my-wiki", keywords: ["my wiki", "wiki", "搜索", "总结"]),
            Candidate(title: "Codex", slug: "codex", keywords: ["codex", "agent"]),
            Candidate(title: "Claude / Cowork", slug: "claude-cowork", keywords: ["claude", "cowork"])
        ]

        var written = 0
        for candidate in candidates {
            let matches = sources.matching(candidate.keywords)
            guard matches.isEmpty == false else { continue }

            let body = """
            # \(candidate.title)

            ## 最近状态

            \(matches.bullets(limit: 5))
            """

            try writePage(
                projectRoot: projectRoot,
                relativePath: "wiki/projects/\(candidate.slug).md",
                type: "project",
                title: candidate.title,
                sources: matches.map(\.fileName),
                body: body
            )
            written += 1
        }

        return written
    }

    private func writeThemes(projectRoot: URL, sources: [DiarySource]) throws -> Int {
        let candidates = [
            Candidate(title: "产品轻量化", slug: "product-simplification", keywords: ["轻量", "太重", "用户", "交互", "困惑"]),
            Candidate(title: "AI Agent 协作", slug: "ai-agent-collaboration", keywords: ["agent", "codex", "claude", "cowork"]),
            Candidate(title: "搜索与总结", slug: "search-and-summary", keywords: ["搜索", "总结", "检索", "准确"]),
            Candidate(title: "本地隐私边界", slug: "local-privacy", keywords: ["隐私", "本地", "权限", "full disk access"])
        ]

        var written = 0
        for candidate in candidates {
            let matches = sources.matching(candidate.keywords)
            guard matches.isEmpty == false else { continue }

            let body = """
            # \(candidate.title)

            ## 最近线索

            \(matches.bullets(limit: 5))
            """

            try writePage(
                projectRoot: projectRoot,
                relativePath: "wiki/themes/\(candidate.slug).md",
                type: "theme",
                title: candidate.title,
                sources: matches.map(\.fileName),
                body: body
            )
            written += 1
        }

        return written
    }

    private func writePreferences(projectRoot: URL, sources: [DiarySource]) throws -> Int {
        let lines = sources.flatMap { source in
            source.lines(matching: ["我觉得", "我希望", "不要", "不需要", "应该", "更好", "太重", "轻量", "复用"])
                .map { "- \(source.day)：\($0)" }
        }
        guard lines.isEmpty == false else { return 0 }

        let matchedSources = sources.filter { source in
            source.containsAny(["我觉得", "我希望", "不要", "不需要", "应该", "更好", "太重", "轻量", "复用"])
        }
        let body = """
        # 最近表达的偏好

        ## 可观察偏好

        \(lines.prefix(10).joined(separator: "\n"))
        """

        try writePage(
            projectRoot: projectRoot,
            relativePath: "wiki/preferences/recent-preferences.md",
            type: "preference",
            title: "最近表达的偏好",
            sources: matchedSources.map(\.fileName),
            body: body
        )
        return 1
    }

    private func writeOpenLoops(projectRoot: URL, sources: [DiarySource]) throws -> Int {
        let lines = sources.flatMap { source in
            source.lines(matching: ["- [ ]", "待办", "继续", "需要", "跟进", "确认", "测试", "完成", "follow up", "to follow up"])
                .map { "- \(source.day)：\($0)" }
        }
        guard lines.isEmpty == false else { return 0 }

        let matchedSources = sources.filter { source in
            source.containsAny(["- [ ]", "待办", "继续", "需要", "跟进", "确认", "测试", "完成", "follow up", "to follow up"])
        }
        let body = """
        # 需要继续跟进

        ## 待办和未闭环事项

        \(lines.prefix(12).joined(separator: "\n"))
        """

        try writePage(
            projectRoot: projectRoot,
            relativePath: "wiki/open-loops/recent-open-loops.md",
            type: "open-loop",
            title: "需要继续跟进",
            sources: matchedSources.map(\.fileName),
            body: body
        )
        return 1
    }

    private func writeIndex(projectRoot: URL) throws {
        let index = """
        # My Wiki Index

        ## 总结

        - [[recent-diary-summary|最近日记总结]]

        ## 项目

        - [[knowyou|KnowYou]]
        - [[my-wiki|My Wiki]]
        - [[codex|Codex]]
        - [[claude-cowork|Claude / Cowork]]

        ## 主题

        - [[product-simplification|产品轻量化]]
        - [[ai-agent-collaboration|AI Agent 协作]]
        - [[search-and-summary|搜索与总结]]
        - [[local-privacy|本地隐私边界]]

        ## 偏好

        - [[recent-preferences|最近表达的偏好]]

        ## 待办

        - [[recent-open-loops|需要继续跟进]]
        """

        try index.write(
            to: projectRoot.appending(path: "wiki/index.md"),
            atomically: true,
            encoding: .utf8
        )
    }

    private func appendLog(projectRoot: URL, fileCount: Int, sourceCount: Int) throws {
        let logURL = projectRoot.appending(path: "wiki/log.md")
        let line = "- \(Date().formatted(date: .numeric, time: .shortened))：从 \(sourceCount) 篇日记生成 \(fileCount) 个 My Wiki 起始页面。\n"
        if fileManager.fileExists(atPath: logURL.path) {
            let handle = try FileHandle(forWritingTo: logURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(line.utf8))
            try handle.close()
        } else {
            try ("# My Wiki Log\n\n" + line).write(to: logURL, atomically: true, encoding: .utf8)
        }
    }

    private func writePage(
        projectRoot: URL,
        relativePath: String,
        type: String,
        title: String,
        sources: [String],
        body: String
    ) throws {
        let sourceList = sources.prefix(12).map { "\"\($0)\"" }.joined(separator: ", ")
        let content = """
        ---
        type: \(type)
        title: \(title)
        sources: [\(sourceList)]
        source_days: []
        confidence: medium
        generated_by: KnowYou My Wiki starter extractor
        ---

        \(body)
        """

        let url = projectRoot.appending(path: relativePath)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    private func stripFrontmatter(_ text: String) -> String {
        guard text.hasPrefix("---") else { return text }
        let lines = text.components(separatedBy: .newlines)
        guard let closing = lines.dropFirst().firstIndex(of: "---") else { return text }
        return lines.dropFirst(closing + 1).joined(separator: "\n")
    }

    private func day(from fileName: String) -> String {
        fileName
            .replacingOccurrences(of: "knowyou-diary-", with: "")
            .replacingOccurrences(of: ".md", with: "")
    }
}

private struct Candidate {
    let title: String
    let slug: String
    let keywords: [String]
}

private struct DiarySource {
    let fileName: String
    let day: String
    let text: String

    func containsAny(_ keywords: [String]) -> Bool {
        let lowered = text.lowercased()
        return keywords.contains { lowered.contains($0.lowercased()) }
    }

    func extractHighlights(limit: Int) -> [String] {
        let headings = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.hasPrefix("#") == false }
            .filter { $0.count >= 8 }
            .filter { $0.count <= 180 }
        return Array(headings.prefix(limit))
    }

    func lines(matching keywords: [String]) -> [String] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
            .filter { line in
                let lowered = line.lowercased()
                return keywords.contains { lowered.contains($0.lowercased()) }
            }
            .map { String($0.prefix(180)) }
    }
}

private extension Array where Element == DiarySource {
    func matching(_ keywords: [String]) -> [DiarySource] {
        filter { $0.containsAny(keywords) }
    }

    func bullets(limit: Int) -> String {
        let lines = flatMap { source in
            source.extractHighlights(limit: 2).map { "- \(source.day)：\($0)" }
        }
        return lines.isEmpty ? "- 暂时没有提取到稳定线索。" : lines.prefix(limit).joined(separator: "\n")
    }
}
