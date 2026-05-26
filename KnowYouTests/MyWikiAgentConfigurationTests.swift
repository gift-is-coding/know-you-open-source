import XCTest
@testable import KnowYou

final class MyWikiAgentConfigurationTests: XCTestCase {
    func testBundledMyWikiSkillHasDiscoverableFrontmatter() throws {
        let skillDirectory = MyWikiAgentConfigurationInstaller.defaultMyWikiSkillSourceDirectory()
        let skill = try String(contentsOf: skillDirectory.appending(path: "SKILL.md"), encoding: .utf8)

        XCTAssertTrue(skill.hasPrefix("---\nname: my-wiki-context\n"))
        XCTAssertTrue(skill.contains("description: Use when an agent needs private KnowYou My Wiki context"))
    }

    func testInstallerWritesConfigAndInstallsSkillForAllBuiltInAgents() throws {
        let sandbox = try temporaryDirectory()
        let skillSourceDirectory = try makeSkillDirectory(in: sandbox.appending(path: "source-skill"))
        let installer = MyWikiAgentConfigurationInstaller(
            codexConfigURL: sandbox.appending(path: ".codex/config.toml"),
            claudeCodeConfigURL: sandbox.appending(path: ".claude.json"),
            claudeDesktopConfigURL: sandbox.appending(path: "Library/Application Support/Claude/claude_desktop_config.json"),
            cursorConfigURL: sandbox.appending(path: ".cursor/mcp.json"),
            geminiCLIConfigURL: sandbox.appending(path: ".gemini/settings.json"),
            openClawConfigURL: sandbox.appending(path: ".openclaw/openclaw.json"),
            skillSourceDirectory: skillSourceDirectory,
            skillInstallDirectories: [
                .codex: sandbox.appending(path: ".codex/skills/my-wiki-context"),
                .claudeCode: sandbox.appending(path: ".claude/skills/my-wiki-context"),
                .cursor: sandbox.appending(path: ".cursor/skills/my-wiki-context"),
                .geminiCLI: sandbox.appending(path: ".gemini/skills/my-wiki-context"),
                .openClaw: sandbox.appending(path: ".openclaw/skills/my-wiki-context"),
            ],
            backupDateProvider: { Date(timeIntervalSince1970: 1_800_000_000) }
        )
        let configuration = """
        {
          "mcpServers": {
            "knowyou-my-wiki": {
              "command": "/tmp/KnowYou",
              "args": ["--my-wiki-mcp", "--project-root", "/tmp/KnowYouContext"]
            }
          }
        }
        """

        for client in MyWikiAgentClient.automaticInstallCases {
            let result = try installer.enable(client, configuration: configuration)

            XCTAssertEqual(result.client, client)
            XCTAssertEqual(installer.setupStatus(for: client, expectedConfiguration: configuration), .ready)
        }

        XCTAssertTrue(try String(contentsOf: sandbox.appending(path: ".codex/config.toml"), encoding: .utf8).contains("[mcp_servers.knowyou-my-wiki]"))
        XCTAssertJSONServerExists(at: sandbox.appending(path: ".claude.json"), path: ["mcpServers"])
        XCTAssertJSONServerExists(at: sandbox.appending(path: "Library/Application Support/Claude/claude_desktop_config.json"), path: ["mcpServers"])
        XCTAssertJSONServerExists(at: sandbox.appending(path: ".cursor/mcp.json"), path: ["mcpServers"])
        XCTAssertJSONServerExists(at: sandbox.appending(path: ".gemini/settings.json"), path: ["mcpServers"])
        XCTAssertJSONServerExists(at: sandbox.appending(path: ".openclaw/openclaw.json"), path: ["mcp", "servers"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: sandbox.appending(path: ".codex/skills/my-wiki-context/SKILL.md").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sandbox.appending(path: ".claude/skills/my-wiki-context/SKILL.md").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sandbox.appending(path: ".cursor/skills/my-wiki-context/SKILL.md").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sandbox.appending(path: ".gemini/skills/my-wiki-context/SKILL.md").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sandbox.appending(path: ".openclaw/skills/my-wiki-context/SKILL.md").path))
    }

    func testCodexInstallerWritesManagedBlockIntoEmptyConfig() throws {
        let sandbox = try temporaryDirectory()
        let configURL = sandbox.appending(path: ".codex/config.toml")
        let skillSourceDirectory = try makeSkillDirectory(in: sandbox.appending(path: "source-skill"))
        let skillInstallDirectory = sandbox.appending(path: ".codex/skills/my-wiki-context")
        let installer = makeCodexOnlyInstaller(
            configURL: configURL,
            skillSourceDirectory: skillSourceDirectory,
            skillInstallDirectory: skillInstallDirectory
        )
        let codexConfig = """
        [mcp_servers.knowyou-my-wiki]
        command = "/tmp/KnowYou"
        args = ["--my-wiki-mcp", "--project-root", "/tmp/KnowYouContext"]
        """

        let result = try installer.enableCodex(configuration: codexConfig)
        let written = try String(contentsOf: configURL, encoding: .utf8)

        XCTAssertTrue(result.didCreateConfig)
        XCTAssertNil(result.backupURL)
        XCTAssertTrue(result.didInstallSkill)
        XCTAssertEqual(result.skillURL, skillInstallDirectory)
        XCTAssertTrue(written.contains("# BEGIN KnowYou My Wiki MCP"))
        XCTAssertTrue(written.contains("[mcp_servers.knowyou-my-wiki]"))
        XCTAssertTrue(written.contains("# END KnowYou My Wiki MCP"))
        XCTAssertEqual(installer.codexStatus(expectedConfiguration: codexConfig), .ready)
        XCTAssertEqual(
            try String(contentsOf: skillInstallDirectory.appending(path: "SKILL.md"), encoding: .utf8),
            "# My Wiki Context\n"
        )
    }

    func testCodexInstallerPreservesExistingConfigAndCreatesBackup() throws {
        let sandbox = try temporaryDirectory()
        let configURL = sandbox.appending(path: ".codex/config.toml")
        let skillSourceDirectory = try makeSkillDirectory(in: sandbox.appending(path: "source-skill"))
        let skillInstallDirectory = sandbox.appending(path: ".codex/skills/my-wiki-context")
        try FileManager.default.createDirectory(
            at: configURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try """
        model = "gpt-5.4"

        [features]
        multi_agent = true
        """.write(to: configURL, atomically: true, encoding: .utf8)
        let installer = MyWikiAgentConfigurationInstaller(
            configURL: configURL,
            skillSourceDirectory: skillSourceDirectory,
            codexSkillDirectory: skillInstallDirectory,
            backupDateProvider: { Date(timeIntervalSince1970: 1_800_000_000) }
        )

        let result = try installer.enableCodex(configuration: "[mcp_servers.knowyou-my-wiki]\ncommand = \"/tmp/KnowYou\"")
        let written = try String(contentsOf: configURL, encoding: .utf8)
        let backupURL = try XCTUnwrap(result.backupURL)
        let backup = try String(contentsOf: backupURL, encoding: .utf8)

        XCTAssertFalse(result.didCreateConfig)
        XCTAssertTrue(written.contains("model = \"gpt-5.4\""))
        XCTAssertTrue(written.contains("multi_agent = true"))
        XCTAssertTrue(written.contains("# BEGIN KnowYou My Wiki MCP"))
        XCTAssertEqual(backup, "model = \"gpt-5.4\"\n\n[features]\nmulti_agent = true")
        XCTAssertEqual(backupURL.lastPathComponent, "config.toml.20270115080000.bak")
    }

    func testCodexInstallerReplacesManagedBlockWithoutDuplicatingIt() throws {
        let sandbox = try temporaryDirectory()
        let configURL = sandbox.appending(path: ".codex/config.toml")
        let skillSourceDirectory = try makeSkillDirectory(in: sandbox.appending(path: "source-skill"))
        let skillInstallDirectory = sandbox.appending(path: ".codex/skills/my-wiki-context")
        let installer = MyWikiAgentConfigurationInstaller(
            configURL: configURL,
            skillSourceDirectory: skillSourceDirectory,
            codexSkillDirectory: skillInstallDirectory,
            backupDateProvider: { Date(timeIntervalSince1970: 1_800_000_000) }
        )

        try installer.enableCodex(configuration: "[mcp_servers.knowyou-my-wiki]\ncommand = \"/old/KnowYou\"")
        try installer.enableCodex(configuration: "[mcp_servers.knowyou-my-wiki]\ncommand = \"/new/KnowYou\"")
        let written = try String(contentsOf: configURL, encoding: .utf8)

        XCTAssertFalse(written.contains("/old/KnowYou"))
        XCTAssertTrue(written.contains("/new/KnowYou"))
        XCTAssertEqual(written.components(separatedBy: "# BEGIN KnowYou My Wiki MCP").count - 1, 1)
    }

    func testCodexInstallerReplacesOldUnmarkedSection() throws {
        let sandbox = try temporaryDirectory()
        let configURL = sandbox.appending(path: ".codex/config.toml")
        let skillSourceDirectory = try makeSkillDirectory(in: sandbox.appending(path: "source-skill"))
        let skillInstallDirectory = sandbox.appending(path: ".codex/skills/my-wiki-context")
        try FileManager.default.createDirectory(
            at: configURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try """
        model = "gpt-5.4"

        [mcp_servers.knowyou-my-wiki]
        command = "/old/KnowYou"
        args = ["--my-wiki-mcp", "--project-root", "/old/KnowYouContext"]

        [mcp_servers.other]
        command = "other"
        """.write(to: configURL, atomically: true, encoding: .utf8)
        let installer = MyWikiAgentConfigurationInstaller(
            configURL: configURL,
            skillSourceDirectory: skillSourceDirectory,
            codexSkillDirectory: skillInstallDirectory,
            backupDateProvider: { Date(timeIntervalSince1970: 1_800_000_000) }
        )

        try installer.enableCodex(configuration: "[mcp_servers.knowyou-my-wiki]\ncommand = \"/new/KnowYou\"")
        let written = try String(contentsOf: configURL, encoding: .utf8)

        XCTAssertFalse(written.contains("/old/KnowYou"))
        XCTAssertTrue(written.contains("/new/KnowYou"))
        XCTAssertTrue(written.contains("[mcp_servers.other]"))
    }

    func testCodexInstallerReportsNotReadyWhenSkillIsMissing() throws {
        let sandbox = try temporaryDirectory()
        let configURL = sandbox.appending(path: ".codex/config.toml")
        let skillSourceDirectory = try makeSkillDirectory(in: sandbox.appending(path: "source-skill"))
        let skillInstallDirectory = sandbox.appending(path: ".codex/skills/my-wiki-context")
        let installer = MyWikiAgentConfigurationInstaller(
            configURL: configURL,
            skillSourceDirectory: skillSourceDirectory,
            codexSkillDirectory: skillInstallDirectory,
            backupDateProvider: { Date(timeIntervalSince1970: 1_800_000_000) }
        )
        let configuration = "[mcp_servers.knowyou-my-wiki]\ncommand = \"/tmp/KnowYou\""

        try installer.enableCodex(configuration: configuration)
        try FileManager.default.removeItem(at: skillInstallDirectory)

        XCTAssertEqual(installer.codexStatus(expectedConfiguration: configuration), .notSetUp)
    }

    func testAgentConnectionPresentationReportsReadyWhenProjectAndKnowYouBinaryExist() throws {
        let sandbox = try temporaryDirectory()
        let projectRoot = sandbox.appending(path: "KnowYouContext", directoryHint: .isDirectory)
        let missingServerScript = sandbox.appending(path: "Tools/MyWikiMCP/src/server.mjs")
        let knowYouBinary = sandbox.appending(path: "Build/KnowYou")
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: knowYouBinary.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("binary".utf8).write(to: knowYouBinary)

        let presentation = MyWikiAgentConnectionPresentation(
            projectRoot: projectRoot,
            mcpServerScriptURL: missingServerScript,
            knowYouBinaryURL: knowYouBinary
        )

        XCTAssertTrue(presentation.isReady)
        XCTAssertEqual(presentation.statusTitle, "Ready")
        XCTAssertEqual(presentation.statusDetail, "Ready to provide My Wiki context to local agent clients.")
        XCTAssertTrue(presentation.startupNote.contains("starts a lightweight KnowYou process"))
    }

    func testAgentConnectionPresentationHasHumanFacingSetupCopy() throws {
        let presentation = MyWikiAgentConnectionPresentation(
            projectRoot: URL(fileURLWithPath: "/tmp/KnowYouContext"),
            mcpServerScriptURL: URL(fileURLWithPath: "/tmp/server.mjs"),
            knowYouBinaryURL: URL(fileURLWithPath: "/tmp/KnowYou")
        )

        XCTAssertEqual(presentation.setupTitle(for: .codex), "Add My Wiki to Codex")
        XCTAssertTrue(presentation.setupDescription(for: .codex).contains("ask My Wiki for helpful context"))
        XCTAssertFalse(presentation.setupDescription(for: .codex).contains("MCP"))
        XCTAssertEqual(presentation.instructionSetupCopy(for: .codex), "Copy this instruction, paste and run in Codex.")
        XCTAssertEqual(presentation.instructionSetupCopy(for: .geminiCLI), "Copy this instruction, paste and run in Gemini.")
        XCTAssertEqual(presentation.instructionRunButtonTitle(for: .codex), "Run in Codex")
        XCTAssertEqual(presentation.instructionRunButtonTitle(for: .geminiCLI), "Run in Gemini")
        XCTAssertEqual(presentation.instructionRunSetupCopy(for: .geminiCLI), "Open Gemini and run this instruction in a new terminal session.")
        XCTAssertTrue(presentation.agentInstruction.contains("my_wiki_context"))
        XCTAssertTrue(presentation.agentInstruction.contains("full background"))
    }

    func testAgentConnectionStepBadgePaletteHasReadableContrast() {
        XCTAssertGreaterThanOrEqual(MyWikiAgentStepBadgePalette.standard.contrastRatio, 4.5)
    }

    func testAgentInstructionLauncherBuildsInteractiveCLIScripts() throws {
        let launcher = MyWikiAgentInstructionLauncher(fileManager: .default)
        let instruction = "Use Brad's My Wiki context."

        XCTAssertTrue(launcher.canRunInstruction(in: .codex))
        XCTAssertTrue(launcher.canRunInstruction(in: .geminiCLI))
        XCTAssertTrue(launcher.canRunInstruction(in: .claudeCode))
        XCTAssertTrue(launcher.canRunInstruction(in: .openClaw))
        XCTAssertFalse(launcher.canRunInstruction(in: .cursor))
        XCTAssertFalse(launcher.canRunInstruction(in: .claudeDesktop))
        XCTAssertFalse(launcher.canRunInstruction(in: .generic))

        XCTAssertTrue(launcher.terminalScript(for: .codex, instruction: instruction).contains("exec codex "))
        XCTAssertTrue(launcher.terminalScript(for: .geminiCLI, instruction: instruction).contains("exec gemini -i "))
        XCTAssertTrue(launcher.terminalScript(for: .claudeCode, instruction: instruction).contains("exec claude "))
        XCTAssertTrue(launcher.terminalScript(for: .openClaw, instruction: instruction).contains("exec openclaw tui --local --message "))
        XCTAssertTrue(launcher.terminalScript(for: .codex, instruction: instruction).contains("'Use Brad'\\''s My Wiki context.'"))
    }

    func testAgentConnectionReadinessCopyAvoidsMCPJargon() throws {
        let sandbox = try temporaryDirectory()
        let projectRoot = sandbox.appending(path: "KnowYouContext", directoryHint: .isDirectory)
        let missingServerScript = sandbox.appending(path: "Tools/MyWikiMCP/src/server.mjs")
        let knowYouBinary = sandbox.appending(path: "Build/KnowYou")
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: knowYouBinary.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("binary".utf8).write(to: knowYouBinary)

        let presentation = MyWikiAgentConnectionPresentation(
            projectRoot: projectRoot,
            mcpServerScriptURL: missingServerScript,
            knowYouBinaryURL: knowYouBinary
        )

        XCTAssertEqual(presentation.statusTitle, "Ready")
        XCTAssertEqual(presentation.statusDetail, "Ready to provide My Wiki context to local agent clients.")
        XCTAssertFalse(presentation.statusTitle.contains("MCP"))
        XCTAssertFalse(presentation.statusDetail.contains("MCP"))
    }

    func testAgentConnectionCodexConfigUsesTomlMCPServer() throws {
        let sandbox = try temporaryDirectory()
        let projectRoot = sandbox.appending(path: "KnowYou Context", directoryHint: .isDirectory)
        let serverScript = sandbox.appending(path: "Tools/My Wiki MCP/src/server.mjs")
        let knowYouBinary = sandbox.appending(path: "Build/Know\"You")
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: knowYouBinary.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("binary".utf8).write(to: knowYouBinary)

        let presentation = MyWikiAgentConnectionPresentation(
            projectRoot: projectRoot,
            mcpServerScriptURL: serverScript,
            knowYouBinaryURL: knowYouBinary
        )

        let config = try XCTUnwrap(presentation.configuration(for: .codex))
        XCTAssertTrue(config.contains("[mcp_servers.knowyou-my-wiki]"))
        XCTAssertTrue(config.contains("command = \"\(knowYouBinary.path.replacingOccurrences(of: "\"", with: "\\\""))\""))
        XCTAssertTrue(config.contains("\"--my-wiki-mcp\""))
        XCTAssertTrue(config.contains("\"--project-root\""))
        XCTAssertTrue(config.contains("\"\(projectRoot.path)\""))
        XCTAssertFalse(config.contains("command = \"node\""))
        XCTAssertFalse(config.contains("KNOWYOU_MY_WIKI_PROJECT"))
        XCTAssertFalse(config.contains("KNOWYOU_BINARY"))
    }

    func testAgentConnectionJSONConfigIsValidAndEscaped() throws {
        let sandbox = try temporaryDirectory()
        let projectRoot = sandbox.appending(path: "KnowYou Context", directoryHint: .isDirectory)
        let serverScript = sandbox.appending(path: "Tools/MyWikiMCP/src/server.mjs")
        let knowYouBinary = sandbox.appending(path: "Build/KnowYou")
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: knowYouBinary.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("binary".utf8).write(to: knowYouBinary)

        let presentation = MyWikiAgentConnectionPresentation(
            projectRoot: projectRoot,
            mcpServerScriptURL: serverScript,
            knowYouBinaryURL: knowYouBinary
        )

        let config = try XCTUnwrap(presentation.configuration(for: .claudeDesktop))
        let data = try XCTUnwrap(config.data(using: .utf8))
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let servers = try XCTUnwrap(object["mcpServers"] as? [String: Any])
        let server = try XCTUnwrap(servers["knowyou-my-wiki"] as? [String: Any])
        let args = try XCTUnwrap(server["args"] as? [String])

        XCTAssertEqual(server["command"] as? String, knowYouBinary.path)
        XCTAssertEqual(args, ["--my-wiki-mcp", "--project-root", projectRoot.path])
        XCTAssertNil(server["env"])
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "KnowYouTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeSkillDirectory(in url: URL) throws -> URL {
        try FileManager.default.createDirectory(
            at: url.appending(path: "agents"),
            withIntermediateDirectories: true
        )
        try "# My Wiki Context\n".write(to: url.appending(path: "SKILL.md"), atomically: true, encoding: .utf8)
        try "name: my-wiki-context\n".write(to: url.appending(path: "agents/openai.yaml"), atomically: true, encoding: .utf8)
        return url
    }

    private func makeCodexOnlyInstaller(
        configURL: URL,
        skillSourceDirectory: URL,
        skillInstallDirectory: URL
    ) -> MyWikiAgentConfigurationInstaller {
        MyWikiAgentConfigurationInstaller(
            codexConfigURL: configURL,
            skillSourceDirectory: skillSourceDirectory,
            skillInstallDirectories: [.codex: skillInstallDirectory],
            backupDateProvider: { Date(timeIntervalSince1970: 1_800_000_000) }
        )
    }

    private func XCTAssertJSONServerExists(
        at url: URL,
        path: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        do {
            let data = try Data(contentsOf: url)
            let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any], file: file, line: line)
            var current: Any = root
            for key in path {
                let dictionary = try XCTUnwrap(current as? [String: Any], file: file, line: line)
                current = try XCTUnwrap(dictionary[key], file: file, line: line)
            }
            let servers = try XCTUnwrap(current as? [String: Any], file: file, line: line)
            let server = try XCTUnwrap(servers["knowyou-my-wiki"] as? [String: Any], file: file, line: line)

            XCTAssertEqual(server["command"] as? String, "/tmp/KnowYou", file: file, line: line)
            XCTAssertEqual(server["args"] as? [String], ["--my-wiki-mcp", "--project-root", "/tmp/KnowYouContext"], file: file, line: line)
            XCTAssertNil(server["env"], file: file, line: line)
        } catch {
            XCTFail("Expected JSON server at \(url.path): \(error)", file: file, line: line)
        }
    }
}
