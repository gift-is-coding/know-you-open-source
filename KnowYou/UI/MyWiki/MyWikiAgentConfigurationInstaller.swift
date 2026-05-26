import Foundation

enum MyWikiAgentSetupStatus: Equatable {
    case notSetUp
    case ready

    var title: String {
        switch self {
        case .notSetUp:
            return "Not Set Up"
        case .ready:
            return "Ready"
        }
    }
}

struct MyWikiAgentConfigurationInstallResult: Equatable {
    let client: MyWikiAgentClient
    let didCreateConfig: Bool
    let backupURL: URL?
    let installedSkillURLs: [URL]

    var didInstallSkill: Bool {
        installedSkillURLs.isEmpty == false
    }

    var skillURL: URL? {
        installedSkillURLs.first
    }
}

struct MyWikiAgentConfigurationInstaller {
    private static let managedBlockStart = "# BEGIN KnowYou My Wiki MCP"
    private static let managedBlockEnd = "# END KnowYou My Wiki MCP"
    private static let serverName = "knowyou-my-wiki"

    let codexConfigURL: URL
    let claudeCodeConfigURL: URL
    let claudeDesktopConfigURL: URL
    let cursorConfigURL: URL
    let geminiCLIConfigURL: URL
    let openClawConfigURL: URL
    let skillSourceDirectory: URL
    let skillInstallDirectories: [MyWikiAgentClient: URL]
    private let fileManager: FileManager
    private let backupDateProvider: () -> Date

    var configURL: URL {
        codexConfigURL
    }

    var codexSkillDirectory: URL {
        skillInstallDirectories[.codex] ?? Self.defaultCodexSkillDirectory()
    }

    init(
        codexConfigURL: URL = Self.defaultCodexConfigURL(),
        claudeCodeConfigURL: URL = Self.defaultClaudeCodeConfigURL(),
        claudeDesktopConfigURL: URL = Self.defaultClaudeDesktopConfigURL(),
        cursorConfigURL: URL = Self.defaultCursorConfigURL(),
        geminiCLIConfigURL: URL = Self.defaultGeminiCLIConfigURL(),
        openClawConfigURL: URL = Self.defaultOpenClawConfigURL(),
        skillSourceDirectory: URL = Self.defaultMyWikiSkillSourceDirectory(),
        skillInstallDirectories: [MyWikiAgentClient: URL] = Self.defaultSkillInstallDirectories(),
        fileManager: FileManager = .default,
        backupDateProvider: @escaping () -> Date = Date.init
    ) {
        self.codexConfigURL = codexConfigURL
        self.claudeCodeConfigURL = claudeCodeConfigURL
        self.claudeDesktopConfigURL = claudeDesktopConfigURL
        self.cursorConfigURL = cursorConfigURL
        self.geminiCLIConfigURL = geminiCLIConfigURL
        self.openClawConfigURL = openClawConfigURL
        self.skillSourceDirectory = skillSourceDirectory
        self.skillInstallDirectories = skillInstallDirectories
        self.fileManager = fileManager
        self.backupDateProvider = backupDateProvider
    }

    init(
        configURL: URL = Self.defaultCodexConfigURL(),
        skillSourceDirectory: URL = Self.defaultMyWikiSkillSourceDirectory(),
        codexSkillDirectory: URL = Self.defaultCodexSkillDirectory(),
        fileManager: FileManager = .default,
        backupDateProvider: @escaping () -> Date = Date.init
    ) {
        self.init(
            codexConfigURL: configURL,
            skillSourceDirectory: skillSourceDirectory,
            skillInstallDirectories: [.codex: codexSkillDirectory],
            fileManager: fileManager,
            backupDateProvider: backupDateProvider
        )
    }

    static func defaultCodexConfigURL(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        homeDirectory
            .appending(path: ".codex", directoryHint: .isDirectory)
            .appending(path: "config.toml")
    }

    static func defaultClaudeCodeConfigURL(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        homeDirectory.appending(path: ".claude.json")
    }

    static func defaultClaudeDesktopConfigURL(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        homeDirectory
            .appending(path: "Library/Application Support/Claude", directoryHint: .isDirectory)
            .appending(path: "claude_desktop_config.json")
    }

    static func defaultCursorConfigURL(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        homeDirectory
            .appending(path: ".cursor", directoryHint: .isDirectory)
            .appending(path: "mcp.json")
    }

    static func defaultGeminiCLIConfigURL(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        homeDirectory
            .appending(path: ".gemini", directoryHint: .isDirectory)
            .appending(path: "settings.json")
    }

    static func defaultOpenClawConfigURL(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        homeDirectory
            .appending(path: ".openclaw", directoryHint: .isDirectory)
            .appending(path: "openclaw.json")
    }

    static func defaultCodexSkillDirectory(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        homeDirectory
            .appending(path: ".codex", directoryHint: .isDirectory)
            .appending(path: "skills", directoryHint: .isDirectory)
            .appending(path: "my-wiki-context", directoryHint: .isDirectory)
    }

    static func defaultClaudeCodeSkillDirectory(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        homeDirectory
            .appending(path: ".claude", directoryHint: .isDirectory)
            .appending(path: "skills", directoryHint: .isDirectory)
            .appending(path: "my-wiki-context", directoryHint: .isDirectory)
    }

    static func defaultCursorSkillDirectory(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        homeDirectory
            .appending(path: ".cursor", directoryHint: .isDirectory)
            .appending(path: "skills", directoryHint: .isDirectory)
            .appending(path: "my-wiki-context", directoryHint: .isDirectory)
    }

    static func defaultGeminiCLISkillDirectory(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        homeDirectory
            .appending(path: ".gemini", directoryHint: .isDirectory)
            .appending(path: "skills", directoryHint: .isDirectory)
            .appending(path: "my-wiki-context", directoryHint: .isDirectory)
    }

    static func defaultOpenClawSkillDirectory(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        homeDirectory
            .appending(path: ".openclaw", directoryHint: .isDirectory)
            .appending(path: "skills", directoryHint: .isDirectory)
            .appending(path: "my-wiki-context", directoryHint: .isDirectory)
    }

    static func defaultSkillInstallDirectories(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> [MyWikiAgentClient: URL] {
        [
            .codex: defaultCodexSkillDirectory(homeDirectory: homeDirectory),
            .claudeCode: defaultClaudeCodeSkillDirectory(homeDirectory: homeDirectory),
            .cursor: defaultCursorSkillDirectory(homeDirectory: homeDirectory),
            .geminiCLI: defaultGeminiCLISkillDirectory(homeDirectory: homeDirectory),
            .openClaw: defaultOpenClawSkillDirectory(homeDirectory: homeDirectory),
        ]
    }

    static func defaultMyWikiSkillSourceDirectory(
        sourceFilePath: String = #filePath,
        fileManager: FileManager = .default
    ) -> URL {
        var candidateRoot = URL(fileURLWithPath: sourceFilePath).deletingLastPathComponent()
        while candidateRoot.path != candidateRoot.deletingLastPathComponent().path {
            let skillCandidate = candidateRoot.appending(path: ".agents/skills/my-wiki-context", directoryHint: .isDirectory)
            if fileManager.fileExists(atPath: skillCandidate.appending(path: "SKILL.md").path) {
                return skillCandidate
            }
            candidateRoot.deleteLastPathComponent()
        }

        return URL(fileURLWithPath: fileManager.currentDirectoryPath)
            .appending(path: ".agents/skills/my-wiki-context", directoryHint: .isDirectory)
    }

    func codexStatus(expectedConfiguration: String) -> MyWikiAgentSetupStatus {
        setupStatus(for: .codex, expectedConfiguration: expectedConfiguration)
    }

    func setupStatus(for client: MyWikiAgentClient, expectedConfiguration: String) -> MyWikiAgentSetupStatus {
        guard client.supportsAutomaticInstall else {
            return .notSetUp
        }

        let hasConfig: Bool
        switch client {
        case .codex:
            hasConfig = codexConfigMatches(expectedConfiguration: expectedConfiguration)
        case .claudeCode:
            hasConfig = jsonConfigMatches(
                at: claudeCodeConfigURL,
                expectedConfiguration: expectedConfiguration,
                serverPath: ["mcpServers"]
            )
        case .claudeDesktop:
            hasConfig = jsonConfigMatches(
                at: claudeDesktopConfigURL,
                expectedConfiguration: expectedConfiguration,
                serverPath: ["mcpServers"]
            )
        case .cursor:
            hasConfig = jsonConfigMatches(
                at: cursorConfigURL,
                expectedConfiguration: expectedConfiguration,
                serverPath: ["mcpServers"]
            )
        case .geminiCLI:
            hasConfig = jsonConfigMatches(
                at: geminiCLIConfigURL,
                expectedConfiguration: expectedConfiguration,
                serverPath: ["mcpServers"]
            )
        case .openClaw:
            hasConfig = jsonConfigMatches(
                at: openClawConfigURL,
                expectedConfiguration: expectedConfiguration,
                serverPath: ["mcp", "servers"]
            )
        case .generic:
            hasConfig = false
        }

        guard hasConfig else {
            return .notSetUp
        }

        if client.hasCompanionSkill {
            guard let skillDirectory = skillInstallDirectories[client],
                  fileManager.fileExists(atPath: skillDirectory.appending(path: "SKILL.md").path) else {
                return .notSetUp
            }
        }

        return .ready
    }

    @discardableResult
    func enableCodex(configuration: String) throws -> MyWikiAgentConfigurationInstallResult {
        try enable(.codex, configuration: configuration)
    }

    @discardableResult
    func enable(_ client: MyWikiAgentClient, configuration: String) throws -> MyWikiAgentConfigurationInstallResult {
        switch client {
        case .codex:
            return try installCodex(configuration: configuration)
        case .claudeCode:
            return try installJSONClient(
                .claudeCode,
                configURL: claudeCodeConfigURL,
                configuration: configuration,
                serverPath: ["mcpServers"]
            )
        case .claudeDesktop:
            return try installJSONClient(
                .claudeDesktop,
                configURL: claudeDesktopConfigURL,
                configuration: configuration,
                serverPath: ["mcpServers"]
            )
        case .cursor:
            return try installJSONClient(
                .cursor,
                configURL: cursorConfigURL,
                configuration: configuration,
                serverPath: ["mcpServers"]
            )
        case .geminiCLI:
            return try installJSONClient(
                .geminiCLI,
                configURL: geminiCLIConfigURL,
                configuration: configuration,
                serverPath: ["mcpServers"]
            )
        case .openClaw:
            return try installJSONClient(
                .openClaw,
                configURL: openClawConfigURL,
                configuration: configuration,
                serverPath: ["mcp", "servers"]
            )
        case .generic:
            return MyWikiAgentConfigurationInstallResult(
                client: .generic,
                didCreateConfig: false,
                backupURL: nil,
                installedSkillURLs: []
            )
        }
    }

    private func installCodex(configuration: String) throws -> MyWikiAgentConfigurationInstallResult {
        let existingConfig = try? String(contentsOf: codexConfigURL, encoding: .utf8)
        let didCreateConfig = existingConfig == nil
        let backupURL = try backupExistingFileIfNeeded(codexConfigURL, existingText: existingConfig)
        try fileManager.createDirectory(at: codexConfigURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let updatedConfig = installManagedBlock(
            into: existingConfig ?? "",
            configuration: codexConfigurationBlock(for: configuration)
        )
        try updatedConfig.write(to: codexConfigURL, atomically: true, encoding: .utf8)
        let installedSkillURLs = try installSkillIfAvailable(for: .codex)

        return MyWikiAgentConfigurationInstallResult(
            client: .codex,
            didCreateConfig: didCreateConfig,
            backupURL: backupURL,
            installedSkillURLs: installedSkillURLs
        )
    }

    private func installJSONClient(
        _ client: MyWikiAgentClient,
        configURL: URL,
        configuration: String,
        serverPath: [String]
    ) throws -> MyWikiAgentConfigurationInstallResult {
        guard let serverConfiguration = serverConfiguration(from: configuration) else {
            throw CocoaError(.coderInvalidValue)
        }

        let existingData = try? Data(contentsOf: configURL)
        let existingObject = existingData.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        let existingText = existingData.flatMap { String(data: $0, encoding: .utf8) }
        let didCreateConfig = existingData == nil
        let backupURL = try backupExistingFileIfNeeded(configURL, existingText: existingText)

        let updatedObject = setServerConfiguration(
            serverConfiguration,
            in: existingObject,
            serverPath: serverPath
        )
        try writeJSONObject(updatedObject, to: configURL)
        let installedSkillURLs = try installSkillIfAvailable(for: client)

        return MyWikiAgentConfigurationInstallResult(
            client: client,
            didCreateConfig: didCreateConfig,
            backupURL: backupURL,
            installedSkillURLs: installedSkillURLs
        )
    }

    private func installSkillIfAvailable(for client: MyWikiAgentClient) throws -> [URL] {
        guard client.hasCompanionSkill,
              let targetDirectory = skillInstallDirectories[client] else {
            return []
        }

        let skillFile = skillSourceDirectory.appending(path: "SKILL.md")
        guard fileManager.fileExists(atPath: skillFile.path) else {
            return []
        }

        let targetParent = targetDirectory.deletingLastPathComponent()
        try fileManager.createDirectory(at: targetParent, withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: targetDirectory.path) {
            try fileManager.removeItem(at: targetDirectory)
        }
        try fileManager.copyItem(at: skillSourceDirectory, to: targetDirectory)
        return [targetDirectory]
    }

    private func backupExistingFileIfNeeded(_ url: URL, existingText: String?) throws -> URL? {
        guard let existingText else { return nil }

        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let backupURL = url.deletingLastPathComponent()
            .appending(path: "\(url.lastPathComponent).\(backupTimestamp()).bak")
        try existingText.write(to: backupURL, atomically: true, encoding: .utf8)
        return backupURL
    }

    private func codexConfigMatches(expectedConfiguration: String) -> Bool {
        guard let current = try? String(contentsOf: codexConfigURL, encoding: .utf8) else {
            return false
        }

        return current.contains(managedBlock(for: codexConfigurationBlock(for: expectedConfiguration)))
    }

    private func jsonConfigMatches(
        at url: URL,
        expectedConfiguration: String,
        serverPath: [String]
    ) -> Bool {
        guard let expectedServer = serverConfiguration(from: expectedConfiguration),
              let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let actualServer = serverConfiguration(in: root, serverPath: serverPath) else {
            return false
        }

        return normalizedJSONString(actualServer) == normalizedJSONString(expectedServer)
    }

    private func installManagedBlock(into existingConfig: String, configuration: String) -> String {
        let strippedConfig = removeOldKnowYouBlocks(from: existingConfig)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let block = managedBlock(for: configuration)

        if strippedConfig.isEmpty {
            return block
        }

        return "\(strippedConfig)\n\n\(block)"
    }

    private func managedBlock(for configuration: String) -> String {
        let body = configuration.trimmingCharacters(in: .whitespacesAndNewlines)
        return """
        \(Self.managedBlockStart)
        \(body)
        \(Self.managedBlockEnd)
        """
    }

    private func removeOldKnowYouBlocks(from config: String) -> String {
        let withoutManagedBlock = removeMarkedManagedBlocks(from: config)
        return removeUnmarkedKnowYouMCPSection(from: withoutManagedBlock)
    }

    private func removeMarkedManagedBlocks(from config: String) -> String {
        var updated = config
        while let startRange = updated.range(of: Self.managedBlockStart),
              let endRange = updated.range(of: Self.managedBlockEnd, range: startRange.lowerBound..<updated.endIndex) {
            updated.removeSubrange(startRange.lowerBound..<endRange.upperBound)
        }
        return updated
    }

    private func removeUnmarkedKnowYouMCPSection(from config: String) -> String {
        let lines = config.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var filtered: [String] = []
        var isSkippingKnowYouSection = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "[mcp_servers.\(Self.serverName)]"
                || trimmed == "[mcp_servers.\(Self.serverName).env]" {
                isSkippingKnowYouSection = true
                continue
            }

            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                isSkippingKnowYouSection = false
            }

            if isSkippingKnowYouSection == false {
                filtered.append(line)
            }
        }

        return filtered.joined(separator: "\n")
    }

    private func codexConfigurationBlock(for configuration: String) -> String {
        guard let server = serverConfiguration(from: configuration),
              let command = server["command"] as? String else {
            return configuration
        }

        let args = server["args"] as? [String] ?? []
        let env = server["env"] as? [String: String] ?? [:]
        let argsString = args
            .map { "\"\(tomlEscape($0))\"" }
            .joined(separator: ", ")
        let envLines = env.keys.sorted()
            .map { "\($0) = \"\(tomlEscape(env[$0] ?? ""))\"" }
            .joined(separator: "\n")

        if envLines.isEmpty {
            return """
            [mcp_servers.\(Self.serverName)]
            command = "\(tomlEscape(command))"
            args = [\(argsString)]
            """
        }

        return """
        [mcp_servers.\(Self.serverName)]
        command = "\(tomlEscape(command))"
        args = [\(argsString)]

        [mcp_servers.\(Self.serverName).env]
        \(envLines)
        """
    }

    private func serverConfiguration(from configuration: String) -> [String: Any]? {
        guard let data = configuration.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        if let server = serverConfiguration(in: root, serverPath: ["mcpServers"]) {
            return server
        }

        if let server = serverConfiguration(in: root, serverPath: ["mcp", "servers"]) {
            return server
        }

        if root["command"] != nil || root["url"] != nil {
            return root
        }

        return nil
    }

    private func serverConfiguration(in root: [String: Any], serverPath: [String]) -> [String: Any]? {
        var current: Any = root
        for key in serverPath {
            guard let dictionary = current as? [String: Any],
                  let next = dictionary[key] else {
                return nil
            }
            current = next
        }

        guard let servers = current as? [String: Any] else {
            return nil
        }

        return servers[Self.serverName] as? [String: Any]
    }

    private func setServerConfiguration(
        _ serverConfiguration: [String: Any],
        in root: [String: Any],
        serverPath: [String]
    ) -> [String: Any] {
        guard let key = serverPath.first else {
            return root
        }

        var updated = root
        if serverPath.count == 1 {
            var servers = updated[key] as? [String: Any] ?? [:]
            servers[Self.serverName] = serverConfiguration
            updated[key] = servers
            return updated
        }

        let child = updated[key] as? [String: Any] ?? [:]
        updated[key] = setServerConfiguration(
            serverConfiguration,
            in: child,
            serverPath: Array(serverPath.dropFirst())
        )
        return updated
    }

    private func writeJSONObject(_ object: [String: Any], to url: URL) throws {
        guard JSONSerialization.isValidJSONObject(object) else {
            throw CocoaError(.coderInvalidValue)
        }

        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: [.atomic])
    }

    private func normalizedJSONString(_ object: [String: Any]) -> String? {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    private func backupTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMddHHmmss"
        return formatter.string(from: backupDateProvider())
    }

    private func tomlEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
