import Foundation

struct ObsidianKnowledgeConnector: KnowledgeImportConnector {
    let connectorInstanceID: String
    let connectorID: KnowledgeConnectorID = .obsidianImport

    private let scanner: FileKnowledgeSnapshotScanner

    init(connectorInstanceID: String, vaultURL: URL) {
        self.connectorInstanceID = connectorInstanceID
        self.scanner = FileKnowledgeSnapshotScanner(
            connectorInstanceID: connectorInstanceID,
            connectorID: .obsidianImport,
            rootURL: vaultURL,
            originKind: "obsidian-vault",
            shouldSkipRemoteID: Self.isKnowYouDailyMemoryExportPath,
            shouldSkipContent: Self.containsKnowYouExportMarker
        )
    }

    func fetchSnapshots() async throws -> [KnowledgeImportSnapshot] {
        try scanner.fetchSnapshots()
    }

    private static func isKnowYouDailyMemoryExportPath(_ remoteID: String) -> Bool {
        remoteID.lowercased().hasPrefix("knowyou/daily memories/")
    }

    private static func containsKnowYouExportMarker(remoteID: String, contentMarkdown: String) -> Bool {
        let frontmatterMarker = #"(?m)^\s*knowyou_export\s*:\s*daily_memory\s*$"#
        if contentMarkdown.range(of: frontmatterMarker, options: [.regularExpression, .caseInsensitive]) != nil {
            return true
        }

        let jsonOriginMarker = #""originKind"\s*:\s*"daily_memory_export""#
        return contentMarkdown.range(of: jsonOriginMarker, options: [.regularExpression, .caseInsensitive]) != nil
    }
}
