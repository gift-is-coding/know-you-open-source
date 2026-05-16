import Foundation

enum MyWikiSourceStatus: String, Equatable {
    case pending = "Pending"
    case processing = "Processing"
    case indexed = "Indexed"
    case failed = "Failed"
    case needsReview = "Needs review"
}

struct MyWikiSourceItem: Identifiable, Equatable {
    var id: String { fileName }

    let fileName: String
    let fileURL: URL
    let summaryURL: URL?
    let status: MyWikiSourceStatus
}

struct MyWikiSourceImportResult: Equatable {
    let importedFileNames: [String]
    let skippedFileNames: [String]
}

struct MyWikiSourceLibrary {
    let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func loadSources(projectRoot: URL) throws -> [MyWikiSourceItem] {
        let rawSources = rawSourcesDirectory(projectRoot: projectRoot)
        guard fileManager.fileExists(atPath: rawSources.path) else { return [] }

        return try fileManager.contentsOfDirectory(
            at: rawSources,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        .filter(Self.isSupportedSourceFile)
        .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        .map { file in
            let summaryURL = sourceSummaryURL(for: file, projectRoot: projectRoot)
            return MyWikiSourceItem(
                fileName: file.lastPathComponent,
                fileURL: file,
                summaryURL: summaryURL,
                status: summaryURL == nil ? .pending : .indexed
            )
        }
    }

    func importFolder(_ folder: URL, projectRoot: URL) throws -> MyWikiSourceImportResult {
        let files = try fileManager.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        .filter(Self.isSupportedSourceFile)
        .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        return try importFiles(files, projectRoot: projectRoot)
    }

    func importFiles(_ files: [URL], projectRoot: URL) throws -> MyWikiSourceImportResult {
        let rawSources = rawSourcesDirectory(projectRoot: projectRoot)
        try fileManager.createDirectory(at: rawSources, withIntermediateDirectories: true)

        var imported: [String] = []
        var skipped: [String] = []

        for file in files {
            guard Self.isSupportedSourceFile(file) else {
                skipped.append(file.lastPathComponent)
                continue
            }

            let destination = nextAvailableDestination(
                for: file.lastPathComponent,
                in: rawSources
            )
            if file.standardizedFileURL.path == destination.standardizedFileURL.path {
                skipped.append(file.lastPathComponent)
                continue
            }

            try fileManager.copyItem(at: file, to: destination)
            imported.append(destination.lastPathComponent)
        }

        return MyWikiSourceImportResult(importedFileNames: imported, skippedFileNames: skipped)
    }

    private func rawSourcesDirectory(projectRoot: URL) -> URL {
        projectRoot.appending(path: "raw/sources", directoryHint: .isDirectory)
    }

    private func sourceSummaryURL(for sourceURL: URL, projectRoot: URL) -> URL? {
        let wikiSources = projectRoot.appending(path: "wiki/sources", directoryHint: .isDirectory)
        let sameName = wikiSources.appending(path: sourceURL.lastPathComponent)
        if fileManager.fileExists(atPath: sameName.path) {
            return sameName
        }

        let markdownName = sourceURL.deletingPathExtension().lastPathComponent + ".md"
        let markdownSummary = wikiSources.appending(path: markdownName)
        return fileManager.fileExists(atPath: markdownSummary.path) ? markdownSummary : nil
    }

    private func nextAvailableDestination(for fileName: String, in directory: URL) -> URL {
        let original = URL(fileURLWithPath: fileName)
        let baseName = original.deletingPathExtension().lastPathComponent
        let pathExtension = original.pathExtension

        var candidate = directory.appending(path: fileName)
        var index = 2
        while fileManager.fileExists(atPath: candidate.path) {
            let suffix = pathExtension.isEmpty ? "" : ".\(pathExtension)"
            candidate = directory.appending(path: "\(baseName)-\(index)\(suffix)")
            index += 1
        }
        return candidate
    }

    private static func isSupportedSourceFile(_ url: URL) -> Bool {
        ["md", "markdown", "txt"].contains(url.pathExtension.lowercased())
    }
}
