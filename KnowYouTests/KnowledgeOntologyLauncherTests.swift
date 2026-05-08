import XCTest
@testable import KnowYou

final class KnowledgeOntologyLauncherTests: XCTestCase {
    func testDefaultDevelopmentSourceUsesEnvironmentOverride() {
        let override = "/tmp/custom-llm-wiki"
        let url = KnowledgeOntologyLauncher.defaultDevelopmentSourceURL(
            processEnvironment: ["KNOWYOU_LLM_WIKI_SOURCE": override]
        )

        XCTAssertEqual(url.path, override)
    }

    func testDefaultDevelopmentSourceCanResolveFromSourceFilePath() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        let serviceFile = root.appending(path: "KnowYou/Services/KnowledgeOntology/KnowledgeOntologyLauncher.swift")
        let uiFile = root.appending(path: "KnowYou/UI/MainWindowView.swift")
        let devSource = root.appending(path: "ThirdParty/llm_wiki", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: serviceFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: uiFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: devSource, withIntermediateDirectories: true)

        let serviceURL = KnowledgeOntologyLauncher.defaultDevelopmentSourceURL(
            processEnvironment: [:],
            sourceFilePath: serviceFile.path,
            fileManager: .default
        )
        let uiURL = KnowledgeOntologyLauncher.defaultDevelopmentSourceURL(
            processEnvironment: [:],
            sourceFilePath: uiFile.path,
            fileManager: .default
        )

        XCTAssertEqual(serviceURL.path, devSource.path)
        XCTAssertEqual(uiURL.path, devSource.path)
    }

    func testResolveLaunchTargetPrefersBundledHelper() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        let bundledApp = root.appending(path: "Resources/KnowledgeOntology/LLM Wiki.app", directoryHint: .isDirectory)
        let devSource = root.appending(path: "ThirdParty/llm_wiki", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: bundledApp, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: devSource, withIntermediateDirectories: true)

        let target = KnowledgeOntologyLauncher.resolveLaunchTarget(
            bundledHelperAppURL: bundledApp,
            developmentSourceURL: devSource,
            fileManager: .default
        )

        XCTAssertEqual(target, .bundledHelperApp(bundledApp))
    }

    func testResolveLaunchTargetFallsBackToDevelopmentSource() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        let bundledApp = root.appending(path: "Resources/KnowledgeOntology/LLM Wiki.app", directoryHint: .isDirectory)
        let devSource = root.appending(path: "ThirdParty/llm_wiki", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: devSource, withIntermediateDirectories: true)

        let target = KnowledgeOntologyLauncher.resolveLaunchTarget(
            bundledHelperAppURL: bundledApp,
            developmentSourceURL: devSource,
            fileManager: .default
        )

        XCTAssertEqual(target, .developmentSource(devSource))
    }

    func testResolveLaunchTargetReportsMissingWhenNoReusableSubsystemExists() {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let target = KnowledgeOntologyLauncher.resolveLaunchTarget(
            bundledHelperAppURL: root.appending(path: "Missing.app", directoryHint: .isDirectory),
            developmentSourceURL: root.appending(path: "missing-source", directoryHint: .isDirectory),
            fileManager: .default
        )

        XCTAssertEqual(target, .missing)
    }
}
