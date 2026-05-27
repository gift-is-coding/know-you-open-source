import Foundation

struct MyWikiSourceIngestSource: Codable, Equatable, Sendable {
    var sourcePath: String
    var sourceID: String
    var displayTitle: String
    var folderContext: String
    var sourceKind: MyWikiSourceKind
    var contentHash: String
}

struct MyWikiSourceIngestPlan: Codable, Equatable, Sendable {
    var sources: [MyWikiSourceIngestSource]
}

struct MyWikiSourceMaterializationResult: Equatable, Sendable {
    var manifestURL: URL
    var materializedCount: Int
}

struct MyWikiSourceCatalogBuilder {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func refreshCatalog(
        projectRoot: URL,
        sourceVault: URL?,
        importedDocuments: [ImportedKnowledgeDocument]
    ) throws -> MyWikiSourceCatalogSnapshot {
        let candidates = try diaryCandidates(sourceVault: sourceVault)
            + externalCandidates(importedDocuments: importedDocuments)
            + manualCandidates(projectRoot: projectRoot)

        let store = MyWikiSourceCatalogStore(projectRoot: projectRoot, fileManager: fileManager)
        return try store.update { snapshot in
            snapshot = snapshot.merged(with: candidates)
        }
    }

    func ingestPlan(snapshot: MyWikiSourceCatalogSnapshot, maxSources: Int?) -> MyWikiSourceIngestPlan {
        if let maxSources, maxSources <= 0 {
            return MyWikiSourceIngestPlan(sources: [])
        }

        var sources = snapshot.records
            .filter { record in
                guard record.included else { return false }
                switch record.status {
                case .pending, .changed, .failed:
                    return true
                case .indexed:
                    return record.wikiSummaryPath == nil
                case .notIncluded, .excludedIndexed:
                    return false
                }
            }
            .sorted { lhs, rhs in
                if lhs.relativePath != rhs.relativePath {
                    return lhs.relativePath.localizedStandardCompare(rhs.relativePath) == .orderedAscending
                }
                return lhs.sourceID.localizedStandardCompare(rhs.sourceID) == .orderedAscending
            }
            .map(Self.ingestSource)

        if let maxSources {
            sources = Array(sources.prefix(maxSources))
        }

        return MyWikiSourceIngestPlan(sources: sources)
    }

    func materialize(
        plan: MyWikiSourceIngestPlan,
        from snapshot: MyWikiSourceCatalogSnapshot,
        projectRoot: URL
    ) throws -> MyWikiSourceMaterializationResult {
        let recordsByID = Dictionary(uniqueKeysWithValues: snapshot.records.map { ($0.sourceID, $0) })
        let materializationSources = try plan.sources.map { source in
            guard let record = recordsByID[source.sourceID] else {
                throw MyWikiSourceCatalogBuilderError.unknownPlannedSource(source.sourceID)
            }
            guard source.sourcePath == record.rawSourcePath else {
                throw MyWikiSourceCatalogBuilderError.planSourcePathMismatch(
                    sourceID: source.sourceID,
                    plannedPath: source.sourcePath,
                    catalogPath: record.rawSourcePath
                )
            }
            let destination = try rawSourceURL(record.rawSourcePath, under: projectRoot)
            return (source: source, record: record, destination: destination)
        }

        var materializedCount = 0
        for materializationSource in materializationSources {
            let record = materializationSource.record
            let destination = materializationSource.destination
            try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)

            switch record.sourceKind {
            case .diary:
                guard let sourcePath = record.sourcePath else { continue }
                let sourceURL = URL(fileURLWithPath: sourcePath)
                let markdown = try String(contentsOf: sourceURL, encoding: .utf8)
                let dayKey = sourceURL.deletingPathExtension().lastPathComponent
                let exported = MyWikiProjectExporter.exportedDiaryMarkdownForCatalog(dayKey: dayKey, markdown: markdown)
                try exported.write(to: destination, atomically: true, encoding: .utf8)
            case .externalDocument, .manualFile:
                guard let sourcePath = record.sourcePath else { continue }
                try replaceFile(at: destination, withCopyOf: URL(fileURLWithPath: sourcePath))
            }
            materializedCount += 1
        }

        let manifestURL = projectRoot.appending(path: ".knowyou/ingest-manifest.json")
        try fileManager.createDirectory(at: manifestURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let manifestPlan = MyWikiSourceIngestPlan(sources: materializationSources.map(\.source))
        let data = try JSONEncoder.knowledgeImport().encode(manifestPlan)
        try data.write(to: manifestURL, options: .atomic)

        return MyWikiSourceMaterializationResult(
            manifestURL: manifestURL,
            materializedCount: materializedCount
        )
    }

    func mark(
        plan: MyWikiSourceIngestPlan,
        succeededIn snapshot: MyWikiSourceCatalogSnapshot,
        at date: Date
    ) -> MyWikiSourceCatalogSnapshot {
        let plannedIDs = Set(plan.sources.map(\.sourceID))
        var updated = snapshot
        for index in updated.records.indices where plannedIDs.contains(updated.records[index].sourceID) {
            updated.records[index].lastIndexedHash = updated.records[index].contentHash
            updated.records[index].lastIndexedAt = date
            updated.records[index].lastIngestError = nil
            updated.records[index].wikiSummaryPath = wikiSummaryPath(for: updated.records[index])
        }
        return updated
    }

    func mark(
        plan: MyWikiSourceIngestPlan,
        failedWith error: String,
        in snapshot: MyWikiSourceCatalogSnapshot
    ) -> MyWikiSourceCatalogSnapshot {
        let plannedIDs = Set(plan.sources.map(\.sourceID))
        var updated = snapshot
        for index in updated.records.indices where plannedIDs.contains(updated.records[index].sourceID) {
            updated.records[index].lastIngestError = error
        }
        return updated
    }

    private func diaryCandidates(sourceVault: URL?) throws -> [MyWikiSourceCandidate] {
        guard let sourceVault else { return [] }
        guard fileManager.fileExists(atPath: sourceVault.path) else { return [] }

        let files = try fileManager.contentsOfDirectory(
            at: sourceVault,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        let dayKeyPattern = #"^\d{4}-\d{2}-\d{2}$"#

        return try files
            .filter { $0.pathExtension == "md" }
            .filter { file in
                file.deletingPathExtension().lastPathComponent.range(
                    of: dayKeyPattern,
                    options: .regularExpression
                ) != nil
            }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .map { file in
                let dayKey = file.deletingPathExtension().lastPathComponent
                let markdown = try String(contentsOf: file, encoding: .utf8)
                let exportedMarkdown = MyWikiProjectExporter.exportedDiaryMarkdownForCatalog(
                    dayKey: dayKey,
                    markdown: markdown
                )
                return MyWikiSourceCandidate(
                    sourceID: "diary:\(dayKey)",
                    sourceKind: .diary,
                    connectorInstanceID: nil,
                    connectorID: nil,
                    displayTitle: dayKey,
                    relativePath: "My Diary/\(dayKey).md",
                    sourcePath: file.path,
                    sourceURL: nil,
                    contentHash: SHA256Hasher.hash(exportedMarkdown),
                    remoteUpdatedAt: nil,
                    defaultIncluded: true,
                    materializedRelativePath: "My Diary/knowyou-diary-\(dayKey).md",
                    folderContext: "My Diary"
                )
            }
    }

    private func externalCandidates(importedDocuments: [ImportedKnowledgeDocument]) -> [MyWikiSourceCandidate] {
        importedDocuments
            .filter { $0.deletedAt == nil }
            .map { document in
                let documentPath = normalizedRelativePath(document.remoteID)
                    ?? normalizedRelativePath(document.title)
                    ?? document.id
                let root = connectorRootName(for: document.connectorID)
                let relativePath = "\(root)/\(safePathComponent(document.connectorInstanceID))/\(documentPath)"
                return MyWikiSourceCandidate(
                    sourceID: document.id,
                    sourceKind: .externalDocument,
                    connectorInstanceID: document.connectorInstanceID,
                    connectorID: document.connectorID,
                    displayTitle: document.title,
                    relativePath: relativePath,
                    sourcePath: document.sourcePath ?? document.localContentPath,
                    sourceURL: document.remoteURL,
                    contentHash: document.contentHash,
                    remoteUpdatedAt: document.remoteUpdatedAt,
                    defaultIncluded: false,
                    materializedRelativePath: relativePath,
                    folderContext: folderContext(for: relativePath)
                )
            }
    }

    private func manualCandidates(projectRoot: URL) throws -> [MyWikiSourceCandidate] {
        let manualRoot = projectRoot.appending(path: "raw/sources/Manual Imports", directoryHint: .isDirectory)
        guard fileManager.fileExists(atPath: manualRoot.path) else { return [] }

        let resourceKeys: [URLResourceKey] = [.isRegularFileKey]
        guard let enumerator = fileManager.enumerator(
            at: manualRoot,
            includingPropertiesForKeys: resourceKeys,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var candidates: [MyWikiSourceCandidate] = []
        for case let file as URL in enumerator {
            let values = try file.resourceValues(forKeys: Set(resourceKeys))
            guard values.isRegularFile == true, Self.isManualSourceExtension(file.pathExtension) else {
                continue
            }
            let relativeUnderManual = file.pathComponentsAfter(prefix: manualRoot)
            guard relativeUnderManual.isEmpty == false else { continue }

            let relativeUnderRawSources = "Manual Imports/\(relativeUnderManual)"
            let contents = try String(contentsOf: file, encoding: .utf8)
            candidates.append(MyWikiSourceCandidate(
                sourceID: "manual:\(relativeUnderRawSources)",
                sourceKind: .manualFile,
                connectorInstanceID: nil,
                connectorID: nil,
                displayTitle: file.lastPathComponent,
                relativePath: relativeUnderRawSources,
                sourcePath: file.path,
                sourceURL: nil,
                contentHash: SHA256Hasher.hash(contents),
                remoteUpdatedAt: nil,
                defaultIncluded: true,
                materializedRelativePath: relativeUnderRawSources,
                folderContext: folderContext(for: relativeUnderRawSources)
            ))
        }

        return candidates.sorted {
            $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending
        }
    }

    private func replaceFile(at destination: URL, withCopyOf source: URL) throws {
        if destination.standardizedFileURL.path == source.standardizedFileURL.path {
            return
        }
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: source, to: destination)
    }

    private func rawSourceURL(_ relativePath: String, under projectRoot: URL) throws -> URL {
        guard let normalized = validatedProjectRelativePath(relativePath),
              normalized.hasPrefix("raw/sources/") else {
            throw MyWikiSourceCatalogBuilderError.unsafeProjectRelativePath(relativePath)
        }
        let destination = projectRoot.appending(path: normalized)
        let projectPath = projectRoot.standardizedFileURL.path
        let destinationPath = destination.standardizedFileURL.path
        guard destinationPath == projectPath || destinationPath.hasPrefix(projectPath + "/") else {
            throw MyWikiSourceCatalogBuilderError.unsafeProjectRelativePath(relativePath)
        }
        return destination
    }

    private func validatedProjectRelativePath(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false, trimmed.hasPrefix("/") == false else { return nil }

        let slashNormalized = trimmed.replacingOccurrences(of: "\\", with: "/")
        let rawComponents = slashNormalized.split(separator: "/").map(String.init)
        guard rawComponents.isEmpty == false else { return nil }
        guard rawComponents.allSatisfy({ component in
            component.isEmpty == false && component != "." && component != ".."
        }) else {
            return nil
        }

        return rawComponents.joined(separator: "/")
    }

    private static func ingestSource(for record: MyWikiSourceCatalogRecord) -> MyWikiSourceIngestSource {
        MyWikiSourceIngestSource(
            sourcePath: record.rawSourcePath,
            sourceID: record.sourceID,
            displayTitle: record.displayTitle,
            folderContext: record.folderContext,
            sourceKind: record.sourceKind,
            contentHash: record.contentHash
        )
    }

    private static func isManualSourceExtension(_ pathExtension: String) -> Bool {
        ["md", "markdown", "txt"].contains(pathExtension.lowercased())
    }

    private func connectorRootName(for connectorID: KnowledgeConnectorID) -> String {
        switch connectorID {
        case .localFolderImport:
            return "Local Folder"
        case .obsidianImport:
            return "Obsidian"
        case .feishuImport:
            return "Feishu Docs"
        case .notionImport:
            return "Notion"
        case .googleDriveImport:
            return "Google Drive"
        case .obsidianExport:
            return "Obsidian Export"
        case .openClawExport:
            return "OpenClaw Export"
        }
    }

    private func normalizedRelativePath(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }

        let slashNormalized = trimmed.replacingOccurrences(of: "\\", with: "/")
        let rawComponents = slashNormalized.split(separator: "/").map(String.init)
        let components = rawComponents.filter { component in
            component.isEmpty == false && component != "." && component != ".."
        }

        guard components.isEmpty == false else { return nil }
        let safeComponents = components.map { component in
            safePathComponent(component)
        }
        return safeComponents.joined(separator: "/")
    }

    private func safePathComponent(_ value: String) -> String {
        let sanitized = value
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "/", with: "-")
        return sanitized.isEmpty ? "untitled" : sanitized
    }

    private func folderContext(for relativePath: String) -> String {
        String(relativePath.split(separator: "/").dropLast().joined(separator: "/"))
    }

    private func wikiSummaryPath(for record: MyWikiSourceCatalogRecord) -> String {
        let rawBasename = URL(fileURLWithPath: record.rawSourcePath)
            .deletingPathExtension()
            .lastPathComponent
        let summaryBasename = rawBasename.isEmpty ? record.sourceID : rawBasename
        return "wiki/sources/\(summaryBasename).md"
    }
}

private enum MyWikiSourceCatalogBuilderError: LocalizedError {
    case unsafeProjectRelativePath(String)
    case unknownPlannedSource(String)
    case planSourcePathMismatch(sourceID: String, plannedPath: String, catalogPath: String)

    var errorDescription: String? {
        switch self {
        case .unsafeProjectRelativePath(let path):
            return "Unsafe My Wiki source catalog project-relative path: \(path)"
        case .unknownPlannedSource(let sourceID):
            return "My Wiki source ingest plan references an unknown source: \(sourceID)"
        case .planSourcePathMismatch(let sourceID, let plannedPath, let catalogPath):
            return """
            My Wiki source ingest plan path mismatch for \(sourceID): planned \(plannedPath), catalog \(catalogPath)
            """
        }
    }
}

private extension URL {
    func pathComponentsAfter(prefix: URL) -> String {
        let prefixPath = prefix.standardizedFileURL.path
        let path = standardizedFileURL.path
        guard path.hasPrefix(prefixPath + "/") else { return "" }
        return String(path.dropFirst(prefixPath.count + 1))
    }
}
