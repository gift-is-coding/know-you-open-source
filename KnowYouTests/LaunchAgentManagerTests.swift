import XCTest
@testable import KnowYou

final class LaunchAgentManagerTests: XCTestCase {
    func testAgentPlistIncludesStartCalendarIntervalAndProgramArguments() {
        let manager = LaunchAgentManager(fileManager: .default)

        let plist = manager.renderPlist(
            executablePath: "/Applications/KnowYou.app/Contents/MacOS/KnowYou",
            hour: 21,
            minute: 15
        )

        XCTAssertTrue(plist.contains("<key>Label</key>"))
        XCTAssertTrue(plist.contains("dev.knowyou.sync-memory"))
        XCTAssertTrue(plist.contains("<key>Hour</key>"))
        XCTAssertTrue(plist.contains("<integer>21</integer>"))
        XCTAssertTrue(plist.contains("<key>Minute</key>"))
        XCTAssertTrue(plist.contains("<integer>15</integer>"))
        XCTAssertTrue(plist.contains("/Applications/KnowYou.app/Contents/MacOS/KnowYou"))
    }

    func testInstallOrUpdateWritesPlistAndBootstrapsAgent() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let plistURL = root
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("LaunchAgents", isDirectory: true)
            .appendingPathComponent("dev.knowyou.sync-memory.plist")
        var recordedCommands: [[String]] = []
        let manager = LaunchAgentManager(
            fileManager: .default,
            homeDirectoryURL: root,
            commandRunner: { command in
                recordedCommands.append(command)
            },
            userIDProvider: { 501 }
        )

        let writtenURL = try manager.installOrUpdate(
            executablePath: "/Applications/KnowYou.app/Contents/MacOS/KnowYou",
            hour: 8,
            minute: 45,
            plistURL: plistURL
        )

        XCTAssertEqual(writtenURL, plistURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: plistURL.path))
        let plistContents = try String(contentsOf: plistURL, encoding: .utf8)
        XCTAssertTrue(plistContents.contains("<integer>8</integer>"))
        XCTAssertTrue(plistContents.contains("<integer>45</integer>"))
        XCTAssertEqual(recordedCommands.count, 3)
        XCTAssertEqual(recordedCommands[0], ["/bin/launchctl", "bootout", "gui/501", plistURL.path])
        XCTAssertEqual(recordedCommands[1], ["/bin/launchctl", "bootstrap", "gui/501", plistURL.path])
        XCTAssertEqual(recordedCommands[2], ["/bin/launchctl", "enable", "gui/501/dev.knowyou.sync-memory"])
    }

    func testRemoveDeletesPlistAndBootsOutAgent() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let plistURL = root
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("LaunchAgents", isDirectory: true)
            .appendingPathComponent("dev.knowyou.sync-memory.plist")
        try FileManager.default.createDirectory(at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "test".write(to: plistURL, atomically: true, encoding: .utf8)

        var recordedCommands: [[String]] = []
        let manager = LaunchAgentManager(
            fileManager: .default,
            homeDirectoryURL: root,
            commandRunner: { command in
                recordedCommands.append(command)
            },
            userIDProvider: { 501 }
        )

        try manager.remove(plistURL: plistURL)

        XCTAssertFalse(FileManager.default.fileExists(atPath: plistURL.path))
        XCTAssertEqual(recordedCommands, [[
            "/bin/launchctl", "bootout", "gui/501", plistURL.path,
        ]])
    }
}
