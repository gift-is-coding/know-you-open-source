import Foundation

struct MyWikiRGBColor {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    fileprivate var relativeLuminance: Double {
        0.2126 * linearized(red) + 0.7152 * linearized(green) + 0.0722 * linearized(blue)
    }

    func contrastRatio(with other: MyWikiRGBColor) -> Double {
        let lighter = max(relativeLuminance, other.relativeLuminance)
        let darker = min(relativeLuminance, other.relativeLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    private func linearized(_ component: Double) -> Double {
        component <= 0.03928 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
    }
}

struct MyWikiAgentStepBadgePalette {
    let background: MyWikiRGBColor
    let foreground: MyWikiRGBColor

    static let standard = MyWikiAgentStepBadgePalette(
        background: MyWikiRGBColor(red: 0.1, green: 0.24, blue: 0.78),
        foreground: MyWikiRGBColor(red: 1, green: 1, blue: 1)
    )

    var contrastRatio: Double {
        background.contrastRatio(with: foreground)
    }
}

enum MyWikiAgentClient: String, CaseIterable, Identifiable {
    case codex
    case claudeCode
    case claudeDesktop
    case cursor
    case geminiCLI
    case openClaw
    case generic

    var id: String { rawValue }

    static var automaticInstallCases: [MyWikiAgentClient] {
        [.codex, .claudeCode, .claudeDesktop, .cursor, .geminiCLI, .openClaw]
    }

    var supportsAutomaticInstall: Bool {
        Self.automaticInstallCases.contains(self)
    }

    var hasCompanionSkill: Bool {
        switch self {
        case .codex, .claudeCode, .cursor, .geminiCLI, .openClaw:
            return true
        case .claudeDesktop, .generic:
            return false
        }
    }

    var title: String {
        switch self {
        case .codex:
            return "Codex"
        case .claudeCode:
            return "Claude Code"
        case .claudeDesktop:
            return "Claude Desktop"
        case .cursor:
            return "Cursor"
        case .geminiCLI:
            return "Gemini CLI"
        case .openClaw:
            return "OpenClaw"
        case .generic:
            return "Generic MCP"
        }
    }
}

struct MyWikiAgentConnectionPresentation {
    let projectRoot: URL?
    let mcpServerScriptURL: URL
    let knowYouBinaryURL: URL

    private let fileManager: FileManager

    init(
        projectRoot: URL?,
        mcpServerScriptURL: URL,
        knowYouBinaryURL: URL,
        fileManager: FileManager = .default
    ) {
        self.projectRoot = projectRoot
        self.mcpServerScriptURL = mcpServerScriptURL
        self.knowYouBinaryURL = knowYouBinaryURL
        self.fileManager = fileManager
    }

    var isReady: Bool {
        guard let projectRoot else { return false }
        return fileManager.fileExists(atPath: projectRoot.path)
            && fileManager.fileExists(atPath: knowYouBinaryURL.path)
    }

    var statusTitle: String {
        guard let projectRoot else { return "Needs My Wiki" }
        guard fileManager.fileExists(atPath: projectRoot.path) else { return "Needs My Wiki" }
        guard fileManager.fileExists(atPath: knowYouBinaryURL.path) else { return "Needs KnowYou App" }
        return "Ready"
    }

    var statusDetail: String {
        guard let projectRoot else {
            return "Open KnowYou with a configured knowledge ontology project first."
        }
        guard fileManager.fileExists(atPath: projectRoot.path) else {
            return "The My Wiki project folder does not exist yet."
        }
        guard fileManager.fileExists(atPath: knowYouBinaryURL.path) else {
            return "The current KnowYou app cannot be located."
        }
        return "Ready to provide My Wiki context to local agent clients."
    }

    var projectRootPath: String {
        projectRoot?.path ?? "Not configured"
    }

    var mcpServerScriptPath: String {
        mcpServerScriptURL.path
    }

    var knowYouBinaryPath: String {
        knowYouBinaryURL.path
    }

    var securityNote: String {
        "This config is for local read-only access on this Mac. Do not send it to another person unless you intend them to access this My Wiki through your machine."
    }

    var startupNote: String {
        "KnowYou does not run a background server. Add My Wiki to a built-in agent or paste the advanced config into another MCP client, then restart or reload that client; it starts a lightweight KnowYou process when it needs My Wiki context."
    }

    var agentInstruction: String {
        """
        Before answering questions that may depend on my projects, decisions, preferences, work history, people, companies, or previous notes, use the my_wiki_context tool first. Search with the full background, not just keywords. Use returned citations to ground the answer.
        """
    }

    func instructionSetupCopy(for client: MyWikiAgentClient) -> String {
        "Copy this instruction, paste and run in \(instructionRunTarget(for: client))."
    }

    func instructionRunButtonTitle(for client: MyWikiAgentClient) -> String {
        "Run in \(instructionRunTarget(for: client))"
    }

    func instructionRunSetupCopy(for client: MyWikiAgentClient) -> String {
        "Open \(instructionRunTarget(for: client)) and run this instruction in a new terminal session."
    }

    func setupTitle(for client: MyWikiAgentClient) -> String {
        switch client {
        case .codex:
            return "Add My Wiki to Codex"
        case .claudeCode:
            return "Add My Wiki to Claude Code"
        case .claudeDesktop:
            return "Add My Wiki to Claude Desktop"
        case .cursor:
            return "Add My Wiki to Cursor"
        case .geminiCLI:
            return "Add My Wiki to Gemini CLI"
        case .openClaw:
            return "Add My Wiki to OpenClaw"
        case .generic:
            return "Add My Wiki to another agent"
        }
    }

    func setupDescription(for client: MyWikiAgentClient) -> String {
        switch client {
        case .codex:
            return "KnowYou will let Codex ask My Wiki for helpful context when your question depends on your projects, decisions, notes, or work history."
        case .claudeCode:
            return "KnowYou will let Claude Code ask My Wiki for helpful context and install the matching Skill so it knows when to ask."
        case .claudeDesktop:
            return "KnowYou will add My Wiki to Claude Desktop so it can ask for helpful context in local chats."
        case .cursor:
            return "KnowYou will let Cursor ask My Wiki for helpful context while you work and install the matching Skill."
        case .geminiCLI:
            return "KnowYou will let Gemini CLI ask My Wiki for helpful context and install the matching Skill."
        case .openClaw:
            return "KnowYou will let OpenClaw ask My Wiki for helpful context and install the matching Skill for its agents."
        case .generic:
            return "Copy the setup for another local agent so it can ask My Wiki for helpful context."
        }
    }

    private func instructionRunTarget(for client: MyWikiAgentClient) -> String {
        switch client {
        case .codex:
            return "Codex"
        case .claudeCode:
            return "Claude Code"
        case .claudeDesktop:
            return "Claude Desktop"
        case .cursor:
            return "Cursor"
        case .geminiCLI:
            return "Gemini"
        case .openClaw:
            return "OpenClaw"
        case .generic:
            return "your agent"
        }
    }

    func configuration(for client: MyWikiAgentClient) -> String? {
        guard isReady, let projectRoot else { return nil }

        switch client {
        case .codex:
            return codexTOML(projectRoot: projectRoot)
        case .openClaw:
            return openClawJSONConfig(projectRoot: projectRoot)
        case .claudeCode, .claudeDesktop, .cursor, .geminiCLI, .generic:
            return jsonMCPConfig(projectRoot: projectRoot)
        }
    }

    static func defaultMCPServerScriptURL(
        processEnvironment: [String: String] = ProcessInfo.processInfo.environment,
        sourceFilePath: String = #filePath,
        fileManager: FileManager = .default
    ) -> URL {
        if let override = processEnvironment["KNOWYOU_MY_WIKI_MCP_SERVER"], override.isEmpty == false {
            return URL(fileURLWithPath: override)
        }

        var candidateRoot = URL(fileURLWithPath: sourceFilePath).deletingLastPathComponent()
        while candidateRoot.path != candidateRoot.deletingLastPathComponent().path {
            let scriptCandidate = candidateRoot.appending(path: "Tools/MyWikiMCP/src/server.mjs")
            if fileManager.fileExists(atPath: scriptCandidate.path) {
                return scriptCandidate
            }
            candidateRoot.deleteLastPathComponent()
        }

        return URL(fileURLWithPath: fileManager.currentDirectoryPath)
            .appending(path: "Tools/MyWikiMCP/src/server.mjs")
    }

    private func codexTOML(projectRoot: URL) -> String {
        """
        [mcp_servers.knowyou-my-wiki]
        command = "\(tomlEscape(knowYouBinaryURL.path))"
        args = ["--my-wiki-mcp", "--project-root", "\(tomlEscape(projectRoot.path))"]
        """
    }

    private func jsonMCPConfig(projectRoot: URL) -> String? {
        let object: [String: Any] = [
            "mcpServers": [
                "knowyou-my-wiki": [
                    "command": knowYouBinaryURL.path,
                    "args": ["--my-wiki-mcp", "--project-root", projectRoot.path],
                ],
            ],
        ]

        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    private func openClawJSONConfig(projectRoot: URL) -> String? {
        let object: [String: Any] = [
            "mcp": [
                "servers": [
                    "knowyou-my-wiki": [
                        "command": knowYouBinaryURL.path,
                        "args": ["--my-wiki-mcp", "--project-root", projectRoot.path],
                    ],
                ],
            ],
        ]

        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    private func tomlEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
