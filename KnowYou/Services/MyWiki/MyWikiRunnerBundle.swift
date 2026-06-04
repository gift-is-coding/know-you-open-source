import Foundation

struct MyWikiRunnerBundle: Equatable, Sendable {
    let rootURL: URL
    let nodeURL: URL
    let scriptURL: URL

    init(rootURL: URL, fileManager: FileManager = .default) throws {
        let nodeURL = rootURL.appending(path: "node")
        let scriptURL = rootURL.appending(path: "mywiki-runner.js")
        guard fileManager.isExecutableFile(atPath: nodeURL.path) else {
            throw MyWikiPipelineBridgeError.pipelineExecutionFailed("Bundled MyWiki runner node is missing or not executable.")
        }
        guard fileManager.fileExists(atPath: scriptURL.path) else {
            throw MyWikiPipelineBridgeError.pipelineExecutionFailed("Bundled MyWiki runner script is missing.")
        }
        self.rootURL = rootURL
        self.nodeURL = nodeURL
        self.scriptURL = scriptURL
    }

    static func defaultBundleURL(bundle: Bundle = .main) -> URL? {
        bundle.resourceURL?.appending(path: "MyWikiRunner", directoryHint: .isDirectory)
    }

    static func resolveDefault(bundle: Bundle = .main, fileManager: FileManager = .default) -> MyWikiRunnerBundle? {
        guard let url = defaultBundleURL(bundle: bundle) else { return nil }
        return try? MyWikiRunnerBundle(rootURL: url, fileManager: fileManager)
    }
}
