import Foundation

struct SyncMemoryCopyResult: Equatable {
    var copiedFileNames: [String]
    var destinationDirectoryPath: String
}

enum SyncMemoryCoordinatorError: LocalizedError {
    case noDiaryMarkdownFound

    var errorDescription: String? {
        switch self {
        case .noDiaryMarkdownFound:
            return "No diary markdown file found to sync."
        }
    }
}

struct SyncMemoryCoordinator {
    let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func syncDiaries(
        sourceVault: URL,
        destinations: [SyncMemoryChannel: URL]
    ) throws -> [SyncMemoryChannel: SyncMemoryCopyResult] {
        let diaryFiles = try markdownFiles(in: sourceVault)
        var results: [SyncMemoryChannel: SyncMemoryCopyResult] = [:]

        for (channel, directory) in destinations {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            for diaryFile in diaryFiles {
                let destinationFile = directory.appendingPathComponent(diaryFile.lastPathComponent)
                if fileManager.fileExists(atPath: destinationFile.path) {
                    try fileManager.removeItem(at: destinationFile)
                }
                try fileManager.copyItem(at: diaryFile, to: destinationFile)
            }
            results[channel] = SyncMemoryCopyResult(
                copiedFileNames: diaryFiles.map(\.lastPathComponent),
                destinationDirectoryPath: directory.path
            )
        }

        return results
    }

    private func markdownFiles(in sourceVault: URL) throws -> [URL] {
        let files = try fileManager.contentsOfDirectory(
            at: sourceVault,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        let markdownFiles = files
            .filter { $0.pathExtension == "md" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }

        guard !markdownFiles.isEmpty else {
            throw SyncMemoryCoordinatorError.noDiaryMarkdownFound
        }

        return markdownFiles
    }
}
