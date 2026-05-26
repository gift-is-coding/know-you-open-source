import AppKit
import Foundation

struct MyWikiAgentInstructionLauncher {
    private let fileManager: FileManager
    private let workspace: NSWorkspace

    init(
        fileManager: FileManager = .default,
        workspace: NSWorkspace = .shared
    ) {
        self.fileManager = fileManager
        self.workspace = workspace
    }

    func canRunInstruction(in client: MyWikiAgentClient) -> Bool {
        commandLine(for: client, instruction: "test") != nil
    }

    func runInstruction(in client: MyWikiAgentClient, instruction: String) throws {
        guard canRunInstruction(in: client) else {
            throw MyWikiAgentInstructionLauncherError.unsupportedClient(client.title)
        }

        let scriptURL = fileManager.temporaryDirectory
            .appending(path: "KnowYou-MyWiki-\(client.rawValue)-\(UUID().uuidString).command")
        try terminalScript(for: client, instruction: instruction)
            .write(to: scriptURL, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        if workspace.open(scriptURL) == false {
            throw MyWikiAgentInstructionLauncherError.launchFailed(client.title)
        }
    }

    func terminalScript(for client: MyWikiAgentClient, instruction: String) -> String {
        let title = client.title
        let command = commandLine(for: client, instruction: instruction) ?? "echo \(shellQuote("\(title) cannot be opened automatically yet."))"
        return """
        #!/bin/zsh -l
        clear
        echo "Starting \(title) with My Wiki instructions..."
        echo
        \(command)
        """
    }

    private func commandLine(for client: MyWikiAgentClient, instruction: String) -> String? {
        let quotedInstruction = shellQuote(instruction)
        switch client {
        case .codex:
            return "exec codex \(quotedInstruction)"
        case .geminiCLI:
            return "exec gemini -i \(quotedInstruction)"
        case .claudeCode:
            return "exec claude \(quotedInstruction)"
        case .openClaw:
            return "exec openclaw tui --local --message \(quotedInstruction)"
        case .claudeDesktop, .cursor, .generic:
            return nil
        }
    }

    private func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}

enum MyWikiAgentInstructionLauncherError: LocalizedError {
    case unsupportedClient(String)
    case launchFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedClient(let client):
            return "\(client) does not have a supported local CLI runner yet."
        case .launchFailed(let client):
            return "Could not open \(client)."
        }
    }
}
