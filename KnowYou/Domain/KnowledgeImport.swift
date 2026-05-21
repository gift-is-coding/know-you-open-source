import Foundation

enum KnowledgeConnectorID: String, CaseIterable, Codable, Equatable, Sendable {
    case obsidianExport = "obsidian-export"
    case openClawExport = "openclaw-export"
    case obsidianImport = "obsidian-import"
    case localFolderImport = "local-folder-import"
    case feishuImport = "feishu-import"
    case notionImport = "notion-import"
    case googleDriveImport = "google-drive-import"

    var isImport: Bool {
        switch self {
        case .obsidianImport, .localFolderImport, .feishuImport, .notionImport, .googleDriveImport:
            return true
        case .obsidianExport, .openClawExport:
            return false
        }
    }
}

struct KnowledgeConnectorInstanceConfig: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var connectorID: KnowledgeConnectorID
    var displayName: String
    var sourcePath: String?
    var accountID: String?
    var workspaceID: String?
    var isEnabled: Bool
}

struct ImportedKnowledgeDocument: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var connectorInstanceID: String
    var connectorID: KnowledgeConnectorID
    var remoteID: String
    var title: String
    var sourcePath: String?
    var remoteURL: String?
    var mimeType: String
    var contentHash: String
    var remoteUpdatedAt: Date?
    var firstImportedAt: Date
    var lastSyncedAt: Date
    var deletedAt: Date?
    var localContentPath: String
    var localMetadataPath: String
    var normalizationVersion: Int
    var originKind: String
}

struct KnowledgeImportSyncStatus: Codable, Equatable, Sendable {
    var connectorInstanceID: String
    var lastStartedAt: Date?
    var lastSucceededAt: Date?
    var lastFailedAt: Date?
    var lastErrorMessage: String?
    var lastChangedDocumentCount: Int
}
