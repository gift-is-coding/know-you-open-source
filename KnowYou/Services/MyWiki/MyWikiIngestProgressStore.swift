import Foundation

struct MyWikiIngestProgress: Equatable {
    enum State: String, Equatable {
        case running
        case succeeded
        case failed
        case unknown
    }

    let state: State
    let message: String
    let updatedAt: String?
    let sourcesProcessed: Int
    let totalSources: Int

    var fraction: Double {
        guard totalSources > 0 else { return 0 }
        return min(1, max(0, Double(sourcesProcessed) / Double(totalSources)))
    }

    var title: String {
        switch state {
        case .running:
            return "Processing sources"
        case .succeeded:
            return "Updated"
        case .failed:
            return message.localizedCaseInsensitiveContains("stopped for preview")
                ? "Preview generated"
                : "Needs attention"
        case .unknown:
            return "Wiki status"
        }
    }

    var detail: String {
        guard totalSources > 0 else { return message }
        return "\(sourcesProcessed)/\(totalSources) sources"
    }
}

struct MyWikiIngestProgressStore {
    func load(projectRoot: URL) throws -> MyWikiIngestProgress? {
        let statusURL = projectRoot.appending(path: ".llm-wiki/last-ingest-status.json")
        guard FileManager.default.fileExists(atPath: statusURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: statusURL)
        let status = try JSONDecoder().decode(MyWikiIngestStatusFile.self, from: data)
        let rawSourceCount = countMarkdownSources(projectRoot: projectRoot)
        let statusTotal = status.sourcesTotal ?? rawSourceCount
        let state = MyWikiIngestProgress.State(rawValue: status.status) ?? .unknown
        let processed = status.sourcesProcessed ?? (state == .succeeded ? statusTotal : 0)
        let totalSources = statusTotal == 0 ? max(processed, rawSourceCount) : statusTotal

        return MyWikiIngestProgress(
            state: state,
            message: status.message,
            updatedAt: status.updatedAt,
            sourcesProcessed: max(0, min(processed, totalSources == 0 ? processed : totalSources)),
            totalSources: totalSources
        )
    }

    private func countMarkdownSources(projectRoot: URL) -> Int {
        let sourceRoot = projectRoot.appending(path: "raw/sources", directoryHint: .isDirectory)
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: sourceRoot,
            includingPropertiesForKeys: nil
        ) else {
            return 0
        }
        return urls.filter { $0.pathExtension.lowercased() == "md" }.count
    }
}

private struct MyWikiIngestStatusFile: Decodable {
    let status: String
    let message: String
    let updatedAt: String?
    let sourcesProcessed: Int?
    let sourcesTotal: Int?
}
