import XCTest
@testable import KnowYou

final class MyWikiPipelineBridgeTests: XCTestCase {
    func testResolvePipelineUsesDevelopmentSourceWhenHelperMissing() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        let dev = root.appending(path: "ThirdParty/llm_wiki", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dev, withIntermediateDirectories: true)

        let target = MyWikiPipelineBridge.resolveTarget(
            bundledHelperAppURL: nil,
            developmentSourceURL: dev
        )

        XCTAssertEqual(target.statusDescription, "Using development llm_wiki pipeline: \(dev.path)")
    }

    func testRunIngestMaterializesStarterPagesFromRawSources() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        let rawSources = root.appending(path: "raw/sources", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: rawSources, withIntermediateDirectories: true)
        try """
        # 2026-05-13

        KnowYou 的 My Wiki 需要更轻量，先展示总结和搜索。
        Codex agent 后续需要读取这些背景。
        """.write(
            to: rawSources.appending(path: "knowyou-diary-2026-05-13.md"),
            atomically: true,
            encoding: .utf8
        )

        let dev = root.appending(path: "ThirdParty/llm_wiki", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dev, withIntermediateDirectories: true)

        try MyWikiPipelineBridge().runIngest(target: .developmentSource(dev), projectRoot: root)

        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appending(path: ".llm-wiki").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appending(path: "wiki/summaries/recent-diary-summary.md").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appending(path: "wiki/projects/knowyou.md").path))
    }

    func testRunIngestStillMaterializesStarterPagesWhenPipelineIsMissing() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        let rawSources = root.appending(path: "raw/sources", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: rawSources, withIntermediateDirectories: true)
        try """
        # 2026-05-13

        KnowYou needs My Wiki to show useful summaries and follow-ups even before the full pipeline is available.
        """.write(
            to: rawSources.appending(path: "knowyou-diary-2026-05-13.md"),
            atomically: true,
            encoding: .utf8
        )

        try MyWikiPipelineBridge().runIngest(target: .missing, projectRoot: root)

        let summaryURL = root.appending(path: "wiki/summaries/recent-diary-summary.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: summaryURL.path))

        let snapshot = try MyWikiMarkdownStore().loadDashboard(projectRoot: root)
        XCTAssertEqual(snapshot.summaries.first?.title, "Recent Journal Summary")
    }
}
