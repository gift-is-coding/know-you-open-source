import Foundation

enum LaunchAgentManagerError: LocalizedError {
    case missingExecutablePath
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingExecutablePath:
            return "Unable to resolve the KnowYou executable path."
        case .commandFailed(let description):
            return description
        }
    }
}

struct LaunchAgentManager {
    typealias CommandRunner = ([String]) throws -> Void

    let fileManager: FileManager
    let label: String
    let homeDirectoryURL: URL
    let commandRunner: CommandRunner
    let userIDProvider: () -> uid_t

    init(
        fileManager: FileManager = .default,
        label: String = "dev.knowyou.sync-memory",
        homeDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser,
        commandRunner: @escaping CommandRunner = LaunchAgentManager.runCommand,
        userIDProvider: @escaping () -> uid_t = { getuid() }
    ) {
        self.fileManager = fileManager
        self.label = label
        self.homeDirectoryURL = homeDirectoryURL
        self.commandRunner = commandRunner
        self.userIDProvider = userIDProvider
    }

    func defaultPlistURL() -> URL {
        homeDirectoryURL
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(label).plist")
    }

    func renderPlist(executablePath: String, hour: Int, minute: Int) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(label)</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(executablePath)</string>
                <string>--sync-memory-now</string>
            </array>
            <key>StartCalendarInterval</key>
            <dict>
                <key>Hour</key>
                <integer>\(hour)</integer>
                <key>Minute</key>
                <integer>\(minute)</integer>
            </dict>
            <key>RunAtLoad</key>
            <true/>
        </dict>
        </plist>
        """
    }

    func syncRegistration(
        executablePath: String?,
        hour: Int,
        minute: Int,
        isEnabled: Bool
    ) throws {
        if isEnabled {
            guard let executablePath, executablePath.isEmpty == false else {
                throw LaunchAgentManagerError.missingExecutablePath
            }
            _ = try installOrUpdate(executablePath: executablePath, hour: hour, minute: minute)
        } else {
            try remove()
        }
    }

    @discardableResult
    func installOrUpdate(
        executablePath: String,
        hour: Int,
        minute: Int,
        plistURL: URL? = nil
    ) throws -> URL {
        let plistURL = plistURL ?? defaultPlistURL()
        try fileManager.createDirectory(
            at: plistURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try renderPlist(executablePath: executablePath, hour: hour, minute: minute)
            .write(to: plistURL, atomically: true, encoding: .utf8)

        try? runLaunchctl(arguments: ["bootout", launchctlDomain, plistURL.path])
        try runLaunchctl(arguments: ["bootstrap", launchctlDomain, plistURL.path])
        try runLaunchctl(arguments: ["enable", "\(launchctlDomain)/\(label)"])
        return plistURL
    }

    func remove(plistURL: URL? = nil) throws {
        let plistURL = plistURL ?? defaultPlistURL()
        guard fileManager.fileExists(atPath: plistURL.path) else { return }
        try? runLaunchctl(arguments: ["bootout", launchctlDomain, plistURL.path])
        try fileManager.removeItem(at: plistURL)
    }

    private var launchctlDomain: String {
        "gui/\(userIDProvider())"
    }

    private func runLaunchctl(arguments: [String]) throws {
        try commandRunner(["/bin/launchctl"] + arguments)
    }

    private static func runCommand(_ command: [String]) throws {
        guard let executable = command.first else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = Array(command.dropFirst())

        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw LaunchAgentManagerError.commandFailed(
                message?.isEmpty == false ? message! : "\(executable) exited with status \(process.terminationStatus)"
            )
        }
    }
}
