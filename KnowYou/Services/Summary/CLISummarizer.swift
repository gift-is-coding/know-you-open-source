import Foundation

protocol ProcessRunning: Sendable {
    func run(executable: String, arguments: [String]) async throws -> String
}

struct SystemProcessRunner: ProcessRunning {
    func run(executable: String, arguments: [String]) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        try process.run()
        process.waitUntilExit()

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        return String(decoding: data, as: UTF8.self)
    }
}

struct CLISummarizer: SummaryGenerating {
    enum Tool: String, Sendable {
        case claudeCode
        case codex
        case gemini
    }

    let tool: Tool
    let executablePath: String
    let runner: ProcessRunning

    init(tool: Tool, executablePath: String, runner: ProcessRunning = SystemProcessRunner()) {
        self.tool = tool
        self.executablePath = executablePath
        self.runner = runner
    }

    func summarize(dayKey: String, markdown: String) async throws -> String {
        let prompt = "Summarize this day as a concise diary entry for \(dayKey):\n\n\(markdown)"
        let arguments: [String]
        switch tool {
        case .claudeCode, .gemini:
            arguments = ["-p", prompt]
        case .codex:
            arguments = [prompt]
        }
        let raw = try await runner.run(executable: executablePath, arguments: arguments)
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Summary unavailable." : trimmed
    }
}
