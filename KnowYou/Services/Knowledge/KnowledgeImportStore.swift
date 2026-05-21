import Foundation

struct KnowledgeImportSnapshot: Equatable, Sendable {
    var connectorInstanceID: String
    var connectorID: KnowledgeConnectorID
    var remoteID: String
    var title: String
    var sourcePath: String?
    var remoteURL: String?
    var mimeType: String
    var contentMarkdown: String
    var remoteUpdatedAt: Date?
    var originKind: String
}

struct KnowledgeImportStore {
    let rootDirectory: URL
    let fileManager: FileManager

    init(rootDirectory: URL, fileManager: FileManager = .default) {
        self.rootDirectory = rootDirectory
        self.fileManager = fileManager
    }

    func save(
        _ snapshot: KnowledgeImportSnapshot,
        now: Date = Date(),
        existingDocument: ImportedKnowledgeDocument? = nil
    ) throws -> ImportedKnowledgeDocument {
        let documentID = Self.documentID(
            connectorInstanceID: snapshot.connectorInstanceID,
            remoteID: snapshot.remoteID
        )
        let directory = rootDirectory
            .appending(path: snapshot.connectorID.rawValue, directoryHint: .isDirectory)
            .appending(path: Self.safePathComponent(snapshot.connectorInstanceID), directoryHint: .isDirectory)
            .appending(path: Self.safePathComponent(documentID), directoryHint: .isDirectory)
        let contentURL = directory.appending(path: "content.md")
        let metadataURL = directory.appending(path: "metadata.json")
        let firstImportedAt: Date
        if let existingDocument {
            firstImportedAt = existingDocument.firstImportedAt
        } else {
            firstImportedAt = try existingMetadataDocument(at: metadataURL)?.firstImportedAt ?? now
        }
        let contentHash = SHA256Hasher.hash(snapshot.contentMarkdown)
        let document = ImportedKnowledgeDocument(
            id: documentID,
            connectorInstanceID: snapshot.connectorInstanceID,
            connectorID: snapshot.connectorID,
            remoteID: snapshot.remoteID,
            title: snapshot.title,
            sourcePath: snapshot.sourcePath,
            remoteURL: snapshot.remoteURL,
            mimeType: snapshot.mimeType,
            contentHash: contentHash,
            remoteUpdatedAt: snapshot.remoteUpdatedAt,
            firstImportedAt: firstImportedAt,
            lastSyncedAt: now,
            deletedAt: nil,
            localContentPath: contentURL.path,
            localMetadataPath: metadataURL.path,
            normalizationVersion: 1,
            originKind: snapshot.originKind
        )
        let data = try JSONEncoder.knowledgeImport.encode(document)
        try writePreparedDocument(markdown: snapshot.contentMarkdown, metadata: data, to: directory)
        return document
    }

    static func documentID(connectorInstanceID: String, remoteID: String) -> String {
        "ci:\(connectorInstanceID.count):\(connectorInstanceID)|remote:\(remoteID.count):\(remoteID)"
    }

    private func existingMetadataDocument(at metadataURL: URL) throws -> ImportedKnowledgeDocument? {
        guard fileManager.fileExists(atPath: metadataURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: metadataURL)
        return try JSONDecoder.knowledgeImport.decode(ImportedKnowledgeDocument.self, from: data)
    }

    private func writePreparedDocument(markdown: String, metadata: Data, to directory: URL) throws {
        let parentDirectory = directory.deletingLastPathComponent()
        let temporaryDirectory = parentDirectory.appending(
            path: ".\(directory.lastPathComponent).tmp-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        do {
            try markdown.write(to: temporaryDirectory.appending(path: "content.md"), atomically: true, encoding: .utf8)
            try metadata.write(to: temporaryDirectory.appending(path: "metadata.json"), options: .atomic)
            if fileManager.fileExists(atPath: directory.path) {
                _ = try fileManager.replaceItemAt(
                    directory,
                    withItemAt: temporaryDirectory,
                    backupItemName: nil,
                    options: []
                )
                return
            }
            try fileManager.moveItem(at: temporaryDirectory, to: directory)
        } catch {
            try? fileManager.removeItem(at: temporaryDirectory)
            throw error
        }
    }

    private static func safePathComponent(_ value: String) -> String {
        SHA256Hasher.hash(value)
    }
}

private extension JSONEncoder {
    static let knowledgeImport: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}

private extension JSONDecoder {
    static let knowledgeImport: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
