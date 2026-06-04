import Foundation

enum KnowledgeOntologyLaunchTarget: Equatable {
    case developmentSource(URL)
    case missing

    var statusDescription: String {
        switch self {
        case .developmentSource(let url):
            return "Using development llm_wiki source: \(url.path)"
        case .missing:
            return "llm_wiki source is not available."
        }
    }
}

enum KnowledgeOntologyLauncherError: LocalizedError {
    case missingReusableSubsystem

    var errorDescription: String? {
        switch self {
        case .missingReusableSubsystem:
            return "Could not find ThirdParty/llm_wiki source."
        }
    }
}

struct KnowledgeOntologyLauncher {
    static func defaultDevelopmentSourceURL(
        processEnvironment: [String: String] = ProcessInfo.processInfo.environment,
        sourceFilePath: String = #filePath,
        fileManager: FileManager = .default
    ) -> URL {
        if let override = processEnvironment["KNOWYOU_LLM_WIKI_SOURCE"], override.isEmpty == false {
            return URL(fileURLWithPath: override, isDirectory: true)
        }

        var candidateRoot = URL(fileURLWithPath: sourceFilePath).deletingLastPathComponent()
        while candidateRoot.path != candidateRoot.deletingLastPathComponent().path {
            let sourceRootCandidate = candidateRoot.appending(path: "ThirdParty/llm_wiki", directoryHint: .isDirectory)
            if fileManager.fileExists(atPath: sourceRootCandidate.path) {
                return sourceRootCandidate
            }
            candidateRoot.deleteLastPathComponent()
        }

        return URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
            .appending(path: "ThirdParty/llm_wiki", directoryHint: .isDirectory)
    }

    static func resolveLaunchTarget(
        developmentSourceURL: URL,
        fileManager: FileManager = .default
    ) -> KnowledgeOntologyLaunchTarget {
        if fileManager.fileExists(atPath: developmentSourceURL.path) {
            return .developmentSource(developmentSourceURL)
        }

        return .missing
    }

    @MainActor
    func launch(target: KnowledgeOntologyLaunchTarget, projectRoot: URL) throws {
        switch target {
        case .developmentSource(let sourceURL):
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["npm", "run", "tauri", "dev"]
            process.currentDirectoryURL = sourceURL
            var environment = ProcessInfo.processInfo.environment
            environment["KNOWYOU_KNOWLEDGE_PROJECT_PATH"] = projectRoot.path
            process.environment = environment
            try process.run()
        case .missing:
            throw KnowledgeOntologyLauncherError.missingReusableSubsystem
        }
    }
}
