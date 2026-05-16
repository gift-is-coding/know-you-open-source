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
        try removeStarterGeneratedPages(projectRoot: projectRoot)

        var written = 0
        written += try writeSummary(projectRoot: projectRoot, sources: sources)
        written += try writePeople(projectRoot: projectRoot, sources: sources)
        written += try writeProjects(projectRoot: projectRoot, sources: sources)
        written += try writeEvents(projectRoot: projectRoot, sources: sources)
        written += try writeThemes(projectRoot: projectRoot, sources: sources)
        written += try writePreferences(projectRoot: projectRoot, sources: sources)
        written += try writeOpenLoops(projectRoot: projectRoot, sources: sources)
        try writeIndex(projectRoot: projectRoot)
        try normalizeLegacyFrontmatterTypes(projectRoot: projectRoot)
        try appendLog(projectRoot: projectRoot, fileCount: written, sourceCount: sources.count)

        return written
    }

    private func loadSources(projectRoot: URL) throws -> [DiarySource] {
        let sourceDirectories = [
            projectRoot.appending(path: "raw/sources", directoryHint: .isDirectory),
            projectRoot.appending(path: "wiki/sources", directoryHint: .isDirectory)
        ]

        var sourcesByFileName: [String: DiarySource] = [:]
        for directory in sourceDirectories where fileManager.fileExists(atPath: directory.path) {
            let files = try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )

            for file in files
                where file.pathExtension == "md" && file.lastPathComponent.hasPrefix("knowyou-diary-") {
                guard sourcesByFileName[file.lastPathComponent] == nil else { continue }
                let text = try String(contentsOf: file, encoding: .utf8)
                sourcesByFileName[file.lastPathComponent] = DiarySource(
                    fileName: file.lastPathComponent,
                    day: day(from: file.lastPathComponent),
                    text: stripFrontmatter(text)
                )
            }
        }

        return sourcesByFileName.values.sorted { $0.fileName > $1.fileName }
    }

    private func ensureDirectories(projectRoot: URL) throws {
        for directory in [
            "wiki/summaries",
            "wiki/people",
            "wiki/projects",
            "wiki/events",
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

    private func removeStarterGeneratedPages(projectRoot: URL) throws {
        for directory in [
            "wiki/summaries",
            "wiki/people",
            "wiki/projects",
            "wiki/events",
            "wiki/themes",
            "wiki/preferences",
            "wiki/open-loops"
        ] {
            let url = projectRoot.appending(path: directory, directoryHint: .isDirectory)
            guard fileManager.fileExists(atPath: url.path) else { continue }
            let files = try fileManager.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            for file in files where file.pathExtension.lowercased() == "md" {
                let markdown = try String(contentsOf: file, encoding: .utf8)
                let frontmatter = MyWikiMarkdownStore.parseMarkdownDocument(markdown).frontmatter
                let generatedBy = frontmatter["generated_by"]?.lowercased() ?? ""
                if generatedBy.contains("starter extractor") {
                    try fileManager.removeItem(at: file)
                }
            }
        }
    }

    private func normalizeLegacyFrontmatterTypes(projectRoot: URL) throws {
        let folders: [(String, String)] = [
            ("wiki/people", "person"),
            ("wiki/projects", "project"),
            ("wiki/events", "event"),
            ("wiki/themes", "theme"),
            ("wiki/preferences", "preference"),
            ("wiki/open-loops", "open-loop"),
            ("wiki/summaries", "summary")
        ]

        for (folder, expectedType) in folders {
            let directory = projectRoot.appending(path: folder, directoryHint: .isDirectory)
            guard fileManager.fileExists(atPath: directory.path) else { continue }
            let files = try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            for file in files where file.pathExtension.lowercased() == "md" {
                var lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: .newlines)
                guard lines.first == "---" else { continue }
                var changed = false
                for index in lines.indices.dropFirst() {
                    if lines[index] == "---" { break }
                    if lines[index].hasPrefix("type:") && lines[index] != "type: \(expectedType)" {
                        lines[index] = "type: \(expectedType)"
                        changed = true
                        break
                    }
                }
                if changed {
                    try lines.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
                }
            }
        }
    }

    private func writeSummary(projectRoot: URL, sources: [DiarySource]) throws -> Int {
        let latest = sources.prefix(7)
        let highlights = latest.flatMap { source in
            source.extractHighlights(limit: 2).map { "- \(source.day): \($0)" }
        }
        let body = """
        # Recent Journal Summary

        KnowYou organized \(sources.count) journal files. The latest source date is \(sources.first?.day ?? "unknown").

        ## Recent Signals

        \(highlights.isEmpty ? "- No stable signals were found yet." : highlights.joined(separator: "\n"))
        """

        try writePage(
            projectRoot: projectRoot,
            relativePath: "wiki/summaries/recent-diary-summary.md",
            type: "summary",
            title: "Recent Journal Summary",
            sources: latest.map(\.fileName),
            body: body
        )
        return 1
    }

    private func writePeople(projectRoot: URL, sources: [DiarySource]) throws -> Int {
        let candidates = peopleCandidates(from: sources)

        var written = 0
        for candidate in candidates {
            let matches = sources.matching(candidate.keywords)
            guard matches.isEmpty == false else { continue }

            let body = """
            # \(candidate.title)

            ## Summary

            \(candidate.title) appears as a real person mentioned in the journal evidence below. Keep this page separate from tools, projects, topics, patterns, and events unless later evidence says otherwise.

            ## Recent Mentions

            \(matches.bullets(matching: candidate.keywords, limit: 5))
            """

            try writePage(
                projectRoot: projectRoot,
                relativePath: "wiki/people/\(candidate.slug).md",
                type: "person",
                title: candidate.title,
                sources: matches.map(\.fileName),
                body: body
            )
            written += 1
        }

        return written
    }

    private func writeProjects(projectRoot: URL, sources: [DiarySource]) throws -> Int {
        let candidates = [
            Candidate(title: "KnowYou", slug: "knowyou", keywords: ["knowyou", "日记", "产品"], summary: "KnowYou is the local-first diary and personal knowledge product being actively developed."),
            Candidate(title: "My Wiki", slug: "my-wiki", keywords: ["my wiki", "wiki", "本体", "搜索", "总结"], summary: "My Wiki is the readable knowledge layer that organizes journal context into people, projects, events, topics, patterns, and follow-ups."),
            Candidate(title: "Project10 BMS Coordination", slug: "project10-bms-coordination", keywords: ["project10", "bms"], summary: "Project10 BMS coordination is a workstream around BMS discussion, scheduling, evidence review, and project-management methods."),
            Candidate(title: "Qingtian 5.0 Acceleration", slug: "qingtian-5-acceleration", keywords: ["擎天5.0", "擎天", "加速项目"], summary: "Qingtian 5.0 Acceleration is a recurring workstream around launch meetings, weekly materials, platform direction, and delivery coordination."),
            Candidate(title: "AI Native Enterprise Framework", slug: "ai-native-enterprise-framework", keywords: ["ai native enterprise", "ai 原生企业", "7s", "framework"], summary: "AI Native Enterprise Framework is the research and writing workstream about defining AI-native organizations and Lenovo transformation paths."),
            Candidate(title: "AIDC Research", slug: "aidc-research", keywords: ["aidc", "数据中心", "omdia", "iea", "morgan stanley"], summary: "AIDC Research is the evidence-building workstream for data-center capacity, power, market space, and source口径."),
            Candidate(title: "Software R&D Agents", slug: "software-rd-agents", keywords: ["软件研发智能体", "研发智能体"], summary: "Software R&D Agents is the workstream around AI-assisted software development needs, materials, meetings, and stakeholder alignment."),
            Candidate(title: "Compliance Process Plan", slug: "compliance-process-plan", keywords: ["合规流程", "安全实验室", "法务", "cicd"], summary: "Compliance Process Plan is a workstream for clarifying compliance-process ownership, staffing, and tooling integration.")
        ]

        var written = 0
        for candidate in candidates {
            let matches = sources.matching(candidate.keywords)
            guard matches.isEmpty == false else { continue }

            let body = """
            # \(candidate.title)

            \(candidate.summary)

            ## Recent Status

            \(matches.bullets(matching: candidate.keywords, limit: 5))
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

    private func writeEvents(projectRoot: URL, sources: [DiarySource]) throws -> Int {
        let candidates = [
            Candidate(title: "BMS Meeting", slug: "bms-meeting", keywords: ["bms meeting", "bms meeting", "bms与项目管理", "bms meeting", "project10 meeting"], summary: "A concrete meeting event around BMS synchronization, Project10 coordination, room/time logistics, and project-management discussion."),
            Candidate(title: "Qingtian 5.0 Launch Meeting", slug: "qingtian-5-launch-meeting", keywords: ["擎天5.0加速项目启动会", "擎天5.0加速项目周例会", "启动会", "周例会"], summary: "A recurring Qingtian 5.0 meeting event involving launch or weekly coordination."),
            Candidate(title: "Lenovo-IDC Strategic Cooperation Meeting", slug: "lenovo-idc-strategic-cooperation-meeting", keywords: ["联想与idc战略合作", "idc战略合作", "三个主题跟进会议"], summary: "A meeting/event thread around Lenovo and IDC strategic cooperation follow-up."),
            Candidate(title: "AI Ontology Exchange", slug: "ai-ontology-exchange", keywords: ["本体构建交流", "中数睿知", "本体的自动化构建"], summary: "An ontology exchange event about automated ontology construction and enterprise AI practice."),
            Candidate(title: "ByteDance Interview Notice", slug: "bytedance-interview-notice", keywords: ["字节", "bytedance", "面试"], summary: "A career-related event involving ByteDance interview or relocation discussion."),
            Candidate(title: "Investor Or Incubator Application Push", slug: "investor-incubator-application-push", keywords: ["yc", "a16z", "pearx", "ai2 incubator", "neo residency"], summary: "A startup/application event where the project direction is prepared for incubators or investors.")
        ]

        var written = 0
        for candidate in candidates {
            let matches = sources.matching(candidate.keywords)
            guard matches.isEmpty == false else { continue }

            let body = """
            # \(candidate.title)

            \(candidate.summary)

            ## Timeline

            \(matches.bullets(matching: candidate.keywords, limit: 6))
            """

            try writePage(
                projectRoot: projectRoot,
                relativePath: "wiki/events/\(candidate.slug).md",
                type: "event",
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
            Candidate(title: "Product Simplicity", slug: "product-simplification", keywords: ["轻量", "太重", "用户", "交互", "困惑"], summary: "A recurring topic about simplifying product interaction and making My Wiki understandable to normal users."),
            Candidate(title: "AI Agent Collaboration", slug: "ai-agent-collaboration", keywords: ["agent", "codex", "claude", "cowork", "智能体"], summary: "A recurring topic about agents using personal context and collaborating with development workflows."),
            Candidate(title: "Search and Summaries", slug: "search-and-summary", keywords: ["搜索", "总结", "检索", "准确"], summary: "A recurring topic about better search results, readable summaries, and useful context retrieval."),
            Candidate(title: "Local Privacy Boundaries", slug: "local-privacy", keywords: ["隐私", "本地", "权限", "full disk access"], summary: "A recurring topic about local-first behavior, permissions, onboarding trust, and privacy boundaries."),
            Candidate(title: "Pipeline Performance", slug: "pipeline-performance", keywords: ["卡", "耗电", "风扇", "pipeline", "分段", "切片"], summary: "A recurring topic about pipeline speed, energy use, chunking, and making extraction safe for foreground use."),
            Candidate(title: "Ontology Quality", slug: "ontology-quality", keywords: ["本体", "人物是人物", "事件是事件", "schema", "抽取"], summary: "A recurring topic about making extracted ontology types semantically correct rather than merely generated.")
        ]

        var written = 0
        for candidate in candidates {
            let matches = sources.matching(candidate.keywords)
            guard matches.isEmpty == false else { continue }

            let body = """
            # \(candidate.title)

            \(candidate.summary)

            ## Recent Signals

            \(matches.bullets(matching: candidate.keywords, limit: 5))
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
        let candidates = [
            Candidate(title: "Prefer Lightweight UX", slug: "prefer-lightweight-ux", keywords: ["太重", "轻量", "用户", "困惑", "卡"], summary: "The user prefers lightweight, clear UX over technical dashboards or confusing interaction."),
            Candidate(title: "Preserve Login State", slug: "preserve-login-state", keywords: ["不要每次都清", "不要清", "登录状态", "onboarding", "清登陆状态"], summary: "Build and verification should preserve login and onboarding state unless a clean-state test is explicitly requested."),
            Candidate(title: "Reuse Existing Code", slug: "reuse-existing-code", keywords: ["复用", "不要自己从零写", "已有的开源代码"], summary: "The user prefers reusing proven existing code and open-source pipeline pieces instead of rewriting from scratch."),
            Candidate(title: "English Market UI", slug: "english-market-ui", keywords: ["英文", "海外市场", "english"], summary: "User-facing UI copy should be English because the product is intended for an overseas market."),
            Candidate(title: "Test Before Push", slug: "test-before-push", keywords: ["不要自动push", "不要 push", "先测试", "本地测试"], summary: "The user wants local testing before any remote push.")
        ]

        var written = 0
        for candidate in candidates {
            let matches = sources.matching(candidate.keywords)
            guard matches.isEmpty == false else { continue }
            let lines = matches.flatMap { source in
                source.lines(matching: candidate.keywords).map { "- \(source.day): \($0)" }
            }

            let body = """
            # \(candidate.title)

            \(candidate.summary)

            ## Evidence

            \(lines.isEmpty ? matches.bullets(matching: candidate.keywords, limit: 5) : lines.prefix(8).joined(separator: "\n"))
            """

            try writePage(
                projectRoot: projectRoot,
                relativePath: "wiki/preferences/\(candidate.slug).md",
                type: "preference",
                title: candidate.title,
                sources: matches.map(\.fileName),
                body: body
            )
            written += 1
        }
        return written
    }

    private func writeOpenLoops(projectRoot: URL, sources: [DiarySource]) throws -> Int {
        let lines = sources.flatMap { source in
            source.lines(matching: ["- [ ]", "待办", "继续", "需要", "跟进", "确认", "测试", "完成", "follow up", "to follow up"])
                .map { "- \(source.day): \($0)" }
        }
        guard lines.isEmpty == false else { return 0 }

        let matchedSources = sources.filter { source in
            source.containsAny(["- [ ]", "待办", "继续", "需要", "跟进", "确认", "测试", "完成", "follow up", "to follow up"])
        }
        let body = """
        # Follow-ups

        ## Open Items

        \(lines.prefix(12).joined(separator: "\n"))
        """

        try writePage(
            projectRoot: projectRoot,
            relativePath: "wiki/open-loops/recent-open-loops.md",
            type: "open-loop",
            title: "Follow-ups",
            sources: matchedSources.map(\.fileName),
            body: body
        )
        return 1
    }

    private func writeIndex(projectRoot: URL) throws {
        let index = """
        # My Wiki Index

        ## Summary

        - [[recent-diary-summary|Recent Journal Summary]]

        ## Projects

        - [[knowyou|KnowYou]]
        - [[my-wiki|My Wiki]]

        ## Events

        - [[bms-meeting|BMS Meeting]]
        - [[qingtian-5-launch-meeting|Qingtian 5.0 Launch Meeting]]

        ## Topics

        - [[product-simplification|Product Simplicity]]
        - [[ai-agent-collaboration|AI Agent Collaboration]]
        - [[search-and-summary|Search and Summaries]]
        - [[local-privacy|Local Privacy Boundaries]]

        ## Preferences

        - [[prefer-lightweight-ux|Prefer Lightweight UX]]
        - [[preserve-login-state|Preserve Login State]]
        - [[reuse-existing-code|Reuse Existing Code]]

        ## Follow-ups

        - [[recent-open-loops|Follow-ups]]
        """

        try index.write(
            to: projectRoot.appending(path: "wiki/index.md"),
            atomically: true,
            encoding: .utf8
        )
    }

    private func appendLog(projectRoot: URL, fileCount: Int, sourceCount: Int) throws {
        let logURL = projectRoot.appending(path: "wiki/log.md")
        let line = "- \(Date().formatted(date: .numeric, time: .shortened)): Generated \(fileCount) starter pages from \(sourceCount) journal files.\n"
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

    private func peopleCandidates(from sources: [DiarySource]) -> [Candidate] {
        let knownPeople = [
            Candidate(title: "Huang Shan", slug: "huang-shan", keywords: ["黄山", "huang shan"], summary: "Huang Shan appears as a real person in work discussions, especially around platform ownership and hardware acceleration boundaries."),
            Candidate(title: "Billy", slug: "billy", keywords: ["billy"], summary: "Billy appears as a real person in recent relationship or collaboration context."),
            Candidate(title: "Zhen Yu", slug: "zhen-yu", keywords: ["zhen yu", "郑鸾"], summary: "Zhen Yu appears as a real person in coordination and discussion context."),
            Candidate(title: "Meg", slug: "meg", keywords: ["meg"], summary: "Meg appears as a real person in team communication about platform demand."),
            Candidate(title: "Brad", slug: "brad", keywords: ["brad"], summary: "Brad appears as a real person in project or platform discussions."),
            Candidate(title: "Gina", slug: "gina", keywords: ["gina"], summary: "Gina appears as a real person in cross-team project alignment."),
            Candidate(title: "Cynthia Li", slug: "cynthia-li", keywords: ["cynthia li", "cynthia"], summary: "Cynthia Li appears as a real person in Lenovo-IDC strategic cooperation follow-up."),
            Candidate(title: "Zhenlei Dai", slug: "zhenlei-dai", keywords: ["zhenlei", "戴总"], summary: "Zhenlei Dai appears as a real person in Lenovo-IDC strategic cooperation follow-up."),
            Candidate(title: "Xuguang Gu", slug: "xuguang-gu", keywords: ["xuguang gu", "xuguang"], summary: "Xuguang Gu appears as a real person in CTO EKP or ChinaGeo coordination."),
            Candidate(title: "Hollis Qi", slug: "hollis-qi", keywords: ["hollis"], summary: "Hollis Qi appears as a real person in CTO EKP planning coordination."),
            Candidate(title: "Adam", slug: "adam", keywords: ["adam"], summary: "Adam appears as a real person in coordination context."),
            Candidate(title: "QiangA Guo", slug: "qianga-guo", keywords: ["qianga guo", "qiangA guo"], summary: "QiangA Guo appears as a real person in FDE capability discussions."),
            Candidate(title: "Shuo Zhou", slug: "shuo-zhou", keywords: ["shuo zhou", "shuo"], summary: "Shuo Zhou appears as a real person in BMS and Project10 meeting coordination."),
            Candidate(title: "Johnson", slug: "johnson", keywords: ["johnson"], summary: "Johnson appears as a real person in BMS meeting coordination."),
            Candidate(title: "Vivian Sun", slug: "vivian-sun", keywords: ["vivian sun", "vivian"], summary: "Vivian Sun appears as a real person in meeting forwarding or coordination.")
        ]

        return knownPeople
    }
}

private struct Candidate {
    let title: String
    let slug: String
    let keywords: [String]
    let summary: String
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
            .filter { $0.localizedCaseInsensitiveContains("There were no usable source events") == false }
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

    func bullets(matching keywords: [String], limit: Int) -> String {
        let lines = flatMap { source in
            source.lines(matching: keywords).map { "- \(source.day): \($0)" }
        }
        if lines.isEmpty == false {
            return lines.prefix(limit).joined(separator: "\n")
        }
        return bullets(limit: limit)
    }

    func bullets(limit: Int) -> String {
        let lines = flatMap { source in
            source.extractHighlights(limit: 2).map { "- \(source.day): \($0)" }
        }
        return lines.isEmpty ? "- No stable signals were found yet." : lines.prefix(limit).joined(separator: "\n")
    }
}
