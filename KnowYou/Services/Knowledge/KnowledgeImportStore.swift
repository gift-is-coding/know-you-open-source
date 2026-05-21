import Foundation

struct KnowledgeImportSnapshot: Equatable, Sendable {
    var connectorInstanceID: String
    var connectorID: KnowledgeConnectorID
    var remoteID: String
    var title: String
    var sourcePath: String?
    var remoteURL: String?
    var mimeType: String
    var markdown: String
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

    func save(_ snapshot: KnowledgeImportSnapshot, now: Date = Date()) throws -> ImportedKnowledgeDocument {
        let documentID = Self.documentID(
            connectorInstanceID: snapshot.connectorInstanceID,
            remoteID: snapshot.remoteID
        )
        let directory = rootDirectory
            .appending(path: snapshot.connectorID.rawValue, directoryHint: .isDirectory)
            .appending(path: snapshot.connectorInstanceID, directoryHint: .isDirectory)
            .appending(path: Self.safePathComponent(documentID), directoryHint: .isDirectory)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let contentURL = directory.appending(path: "content.md")
        try snapshot.markdown.write(to: contentURL, atomically: true, encoding: .utf8)

        let metadataURL = directory.appending(path: "metadata.json")
        let contentHash = SHA256Hasher.hash(snapshot.markdown)
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
            firstImportedAt: now,
            lastSyncedAt: now,
            deletedAt: nil,
            localContentPath: contentURL.path,
            localMetadataPath: metadataURL.path,
            normalizationVersion: 1,
            originKind: snapshot.originKind
        )
        let data = try JSONEncoder.knowledgeImport.encode(document)
        try data.write(to: metadataURL, options: .atomic)
        return document
    }

    static func documentID(connectorInstanceID: String, remoteID: String) -> String {
        "\(connectorInstanceID):\(remoteID)"
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
