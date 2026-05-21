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
    private static let writeLocks = KnowledgeImportStoreWriteLocks()

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
        if let existingDocument {
            try Self.validateExistingDocument(existingDocument, matches: snapshot)
        }

        let documentID = Self.documentID(
            connectorInstanceID: snapshot.connectorInstanceID,
            remoteID: snapshot.remoteID
        )
        let directory = rootDirectory
            .appending(path: snapshot.connectorID.rawValue, directoryHint: .isDirectory)
            .appending(path: Self.safePathComponent(snapshot.connectorInstanceID), directoryHint: .isDirectory)
            .appending(path: Self.safePathComponent(documentID), directoryHint: .isDirectory)
        let writeLock = Self.writeLocks.lock(for: directory.path)
        writeLock.lock()
        defer { writeLock.unlock() }

        let contentURL = directory.appending(path: "content.md")
        let metadataURL = directory.appending(path: "metadata.json")
        let firstImportedAt: Date
        if let existingDocument {
            firstImportedAt = existingDocument.firstImportedAt
        } else {
            firstImportedAt = try existingMetadataDocument(at: metadataURL)?.firstImportedAt ?? now
        }
        let metadataDocumentID = existingDocument?.id ?? documentID
        let contentHash = SHA256Hasher.hash(snapshot.contentMarkdown)
        let document = ImportedKnowledgeDocument(
            id: metadataDocumentID,
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
        let data = try JSONEncoder.knowledgeImport().encode(document)
        try writePreparedDocument(markdown: snapshot.contentMarkdown, metadata: data, to: directory)
        return document
    }

    static func documentID(connectorInstanceID: String, remoteID: String) -> String {
        "ci:\(connectorInstanceID.count):\(connectorInstanceID)|remote:\(remoteID.count):\(remoteID)"
    }

    private static func validateExistingDocument(
        _ existingDocument: ImportedKnowledgeDocument,
        matches snapshot: KnowledgeImportSnapshot
    ) throws {
        guard existingDocument.connectorInstanceID == snapshot.connectorInstanceID,
              existingDocument.connectorID == snapshot.connectorID,
              existingDocument.remoteID == snapshot.remoteID else {
            throw KnowledgeImportStoreError.existingDocumentIdentityMismatch(
                expectedConnectorInstanceID: snapshot.connectorInstanceID,
                expectedConnectorID: snapshot.connectorID,
                expectedRemoteID: snapshot.remoteID,
                actualConnectorInstanceID: existingDocument.connectorInstanceID,
                actualConnectorID: existingDocument.connectorID,
                actualRemoteID: existingDocument.remoteID
            )
        }
    }

    private func existingMetadataDocument(at metadataURL: URL) throws -> ImportedKnowledgeDocument? {
        guard fileManager.fileExists(atPath: metadataURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: metadataURL)
        return try JSONDecoder.knowledgeImport().decode(ImportedKnowledgeDocument.self, from: data)
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

private final class KnowledgeImportStoreWriteLocks: @unchecked Sendable {
    private let lock = NSLock()
    private var locksByPath = [String: NSLock]()

    func lock(for path: String) -> NSLock {
        lock.lock()
        defer { lock.unlock() }

        if let existingLock = locksByPath[path] {
            return existingLock
        }

        let newLock = NSLock()
        locksByPath[path] = newLock
        return newLock
    }
}

private extension JSONEncoder {
    static func knowledgeImport() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = KnowledgeImportDateCoding.encodingStrategy
        return encoder
    }
}

private extension JSONDecoder {
    static func knowledgeImport() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = KnowledgeImportDateCoding.decodingStrategy
        return decoder
    }
}

private enum KnowledgeImportStoreError: Error, CustomStringConvertible {
    case existingDocumentIdentityMismatch(
        expectedConnectorInstanceID: String,
        expectedConnectorID: KnowledgeConnectorID,
        expectedRemoteID: String,
        actualConnectorInstanceID: String,
        actualConnectorID: KnowledgeConnectorID,
        actualRemoteID: String
    )

    var description: String {
        switch self {
        case let .existingDocumentIdentityMismatch(
            expectedConnectorInstanceID,
            expectedConnectorID,
            expectedRemoteID,
            actualConnectorInstanceID,
            actualConnectorID,
            actualRemoteID
        ):
            return """
            Existing document identity mismatch: expected \
            connectorInstanceID=\(expectedConnectorInstanceID), connectorID=\(expectedConnectorID.rawValue), remoteID=\(expectedRemoteID); \
            got connectorInstanceID=\(actualConnectorInstanceID), connectorID=\(actualConnectorID.rawValue), remoteID=\(actualRemoteID)
            """
        }
    }
}

private enum KnowledgeImportDateCoding {
    static let encodingStrategy: JSONEncoder.DateEncodingStrategy = .custom { date, encoder in
        var container = encoder.singleValueContainer()
        try container.encode(iso8601WithFractionalSeconds().string(from: date))
    }

    static let decodingStrategy: JSONDecoder.DateDecodingStrategy = .custom { decoder in
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        if let date = iso8601WithFractionalSeconds().date(from: value) ?? iso8601().date(from: value) {
            return date
        }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO-8601 date: \(value)")
    }

    private static func iso8601WithFractionalSeconds() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }

    private static func iso8601() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }
}
