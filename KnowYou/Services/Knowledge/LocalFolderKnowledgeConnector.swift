import Foundation

struct LocalFolderKnowledgeConnector: KnowledgeImportConnector {
    let connectorInstanceID: String
    let connectorID: KnowledgeConnectorID = .localFolderImport

    private let scanner: FileKnowledgeSnapshotScanner

    init(connectorInstanceID: String, rootURL: URL) {
        self.connectorInstanceID = connectorInstanceID
        self.scanner = FileKnowledgeSnapshotScanner(
            connectorInstanceID: connectorInstanceID,
            connectorID: .localFolderImport,
            rootURL: rootURL,
            originKind: "local-file"
        )
    }

    func fetchSnapshots() async throws -> [KnowledgeImportSnapshot] {
        try scanner.fetchSnapshots()
    }
}

struct FileBackedPlatformKnowledgeConnector: KnowledgeImportConnector {
    let connectorInstanceID: String
    let connectorID: KnowledgeConnectorID

    private let scanner: FileKnowledgeSnapshotScanner

    init(connectorInstanceID: String, connectorID: KnowledgeConnectorID, rootURL: URL) {
        precondition(
            [.feishuImport, .notionImport, .googleDriveImport].contains(connectorID),
            "FileBackedPlatformKnowledgeConnector only supports external platform imports."
        )
        self.connectorInstanceID = connectorInstanceID
        self.connectorID = connectorID
        self.scanner = FileKnowledgeSnapshotScanner(
            connectorInstanceID: connectorInstanceID,
            connectorID: connectorID,
            rootURL: rootURL,
            originKind: "\(Self.slug(for: connectorID))-local-file"
        )
    }

    func fetchSnapshots() async throws -> [KnowledgeImportSnapshot] {
        try scanner.fetchSnapshots()
    }

    private static func slug(for connectorID: KnowledgeConnectorID) -> String {
        switch connectorID {
        case .feishuImport:
            return "feishu"
        case .notionImport:
            return "notion"
        case .googleDriveImport:
            return "google-drive"
        case .localFolderImport, .obsidianImport, .obsidianExport, .openClawExport:
            return connectorID.rawValue
        }
    }
}

struct FileKnowledgeSnapshotScanner: @unchecked Sendable {
    typealias RemoteIDPredicate = @Sendable (String) -> Bool
    typealias ContentPredicate = @Sendable (String, String) -> Bool

    let connectorInstanceID: String
    let connectorID: KnowledgeConnectorID
    let rootURL: URL
    let originKind: String
    let fileManager: FileManager
    let shouldSkipRemoteID: RemoteIDPredicate
    let shouldSkipContent: ContentPredicate

    init(
        connectorInstanceID: String,
        connectorID: KnowledgeConnectorID,
        rootURL: URL,
        originKind: String,
        fileManager: FileManager = .default,
        shouldSkipRemoteID: @escaping RemoteIDPredicate = { _ in false },
        shouldSkipContent: @escaping ContentPredicate = { _, _ in false }
    ) {
        self.connectorInstanceID = connectorInstanceID
        self.connectorID = connectorID
        self.rootURL = rootURL
        self.originKind = originKind
        self.fileManager = fileManager
        self.shouldSkipRemoteID = shouldSkipRemoteID
        self.shouldSkipContent = shouldSkipContent
    }

    func fetchSnapshots() throws -> [KnowledgeImportSnapshot] {
        let rootURL = Self.canonicalFileURL(rootURL)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: rootURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw KnowledgeImportConnectorError.unavailable("Cannot enumerate \(rootURL.path)")
        }

        var enumerationError: Error?
        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, error in
                enumerationError = error
                return false
            }
        ) else {
            throw KnowledgeImportConnectorError.unavailable("Cannot enumerate \(rootURL.path)")
        }

        var snapshots: [KnowledgeImportSnapshot] = []
        for case let fileURL as URL in enumerator {
            let fileURL = Self.canonicalFileURL(fileURL)
            let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey])
            guard resourceValues.isRegularFile == true,
                  let mimeType = Self.mimeType(for: fileURL) else {
                continue
            }

            let remoteID = try Self.relativePath(from: rootURL, to: fileURL)
            guard !shouldSkipRemoteID(remoteID) else {
                continue
            }

            let contentMarkdown: String
            do {
                contentMarkdown = try String(contentsOf: fileURL, encoding: .utf8)
            } catch {
                throw KnowledgeImportConnectorError.invalidResponse(
                    "Cannot read \(remoteID) at \(fileURL.standardizedFileURL.path): \(error.localizedDescription)"
                )
            }
            guard !shouldSkipContent(remoteID, contentMarkdown) else {
                continue
            }

            snapshots.append(
                KnowledgeImportSnapshot(
                    connectorInstanceID: connectorInstanceID,
                    connectorID: connectorID,
                    remoteID: remoteID,
                    title: fileURL.deletingPathExtension().lastPathComponent,
                    sourcePath: fileURL.standardizedFileURL.path,
                    remoteURL: nil,
                    mimeType: mimeType,
                    contentMarkdown: contentMarkdown,
                    remoteUpdatedAt: resourceValues.contentModificationDate,
                    originKind: originKind
                )
            )
        }

        if let enumerationError {
            throw KnowledgeImportConnectorError.unavailable(enumerationError.localizedDescription)
        }

        return snapshots.sorted { $0.remoteID < $1.remoteID }
    }

    private static func mimeType(for fileURL: URL) -> String? {
        switch fileURL.pathExtension.lowercased() {
        case "md", "markdown":
            "text/markdown"
        case "txt":
            "text/plain"
        default:
            nil
        }
    }

    private static func canonicalFileURL(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }

    private static func relativePath(from rootURL: URL, to fileURL: URL) throws -> String {
        let rootPath = rootURL.path
        let filePath = fileURL.path
        let prefix = rootPath.hasSuffix("/") ? rootPath : "\(rootPath)/"
        if filePath.hasPrefix(prefix) {
            return String(filePath.dropFirst(prefix.count))
        }

        if filePath.lowercased().hasPrefix(prefix.lowercased()) {
            return String(filePath.dropFirst(prefix.count))
        }

        throw KnowledgeImportConnectorError.invalidResponse(
            "Enumerated file \(filePath) is outside scan root \(rootPath)"
        )
    }
}
