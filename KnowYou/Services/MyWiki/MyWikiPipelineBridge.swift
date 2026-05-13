import Foundation

enum MyWikiPipelineTarget: Equatable {
    case bundledHelperApp(URL)
    case developmentSource(URL)
    case missing

    var statusDescription: String {
        switch self {
        case .bundledHelperApp(let url):
            return "Using bundled llm_wiki pipeline: \(url.path)"
        case .developmentSource(let url):
            return "Using development llm_wiki pipeline: \(url.path)"
        case .missing:
            return "llm_wiki pipeline is not available."
        }
    }
}

enum MyWikiPipelineBridgeError: LocalizedError {
    case missingPipeline

    var errorDescription: String? {
        switch self {
        case .missingPipeline:
            return "Could not find the bundled llm_wiki helper or ThirdParty/llm_wiki source."
        }
    }
}

struct MyWikiPipelineBridge {
    static func resolveTarget(
        bundledHelperAppURL: URL?,
        developmentSourceURL: URL,
        fileManager: FileManager = .default
    ) -> MyWikiPipelineTarget {
        let legacyTarget = KnowledgeOntologyLauncher.resolveLaunchTarget(
            bundledHelperAppURL: bundledHelperAppURL,
            developmentSourceURL: developmentSourceURL,
            fileManager: fileManager
        )

        switch legacyTarget {
        case .bundledHelperApp(let url):
            return .bundledHelperApp(url)
        case .developmentSource(let url):
            return .developmentSource(url)
        case .missing:
            return .missing
        }
    }

    func runIngest(target: MyWikiPipelineTarget, projectRoot: URL) throws {
        switch target {
        case .bundledHelperApp, .developmentSource:
            try FileManager.default.createDirectory(
                at: projectRoot.appending(path: ".llm-wiki", directoryHint: .isDirectory),
                withIntermediateDirectories: true
            )
            try MyWikiStarterExtractor().materialize(projectRoot: projectRoot)
        case .missing:
            try MyWikiStarterExtractor().materialize(projectRoot: projectRoot)
        }
    }

    @MainActor
    func openAdvancedWorkspace(target: MyWikiPipelineTarget, projectRoot: URL) throws {
        try KnowledgeOntologyLauncher().launch(
            target: knowledgeOntologyTarget(from: target),
            projectRoot: projectRoot
        )
    }

    private func knowledgeOntologyTarget(from target: MyWikiPipelineTarget) -> KnowledgeOntologyLaunchTarget {
        switch target {
        case .bundledHelperApp(let url):
            return .bundledHelperApp(url)
        case .developmentSource(let url):
            return .developmentSource(url)
        case .missing:
            return .missing
        }
    }
}
