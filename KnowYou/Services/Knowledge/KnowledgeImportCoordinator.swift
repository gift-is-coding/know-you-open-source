import Foundation

struct KnowledgeImportRunResult: Equatable {
    var startedAt: Date
    var finishedAt: Date
    var connectorResults: [KnowledgeImportConnectorRunResult]

    var succeededConnectorInstanceIDs: [String] {
        connectorResults
            .filter { $0.status == .succeeded }
            .map(\.connectorInstanceID)
    }

    var failedConnectorInstanceIDs: [String] {
        connectorResults
            .filter { $0.status == .failed }
            .map(\.connectorInstanceID)
    }

    var changedDocumentCount: Int {
        connectorResults.reduce(0) { $0 + $1.changedDocumentCount }
    }
}

struct KnowledgeImportConnectorRunResult: Equatable {
    enum Status: Equatable {
        case succeeded
        case failed
    }

    var connectorInstanceID: String
    var connectorID: KnowledgeConnectorID
    var status: Status
    var changedDocumentCount: Int
    var errorMessage: String?
}

struct KnowledgeImportCoordinator {
    let store: KnowledgeImportStore
    let databaseWriter: DatabaseWriter
    let now: () -> Date

    init(
        store: KnowledgeImportStore,
        databaseWriter: DatabaseWriter,
        now: @escaping () -> Date = Date.init
    ) {
        self.store = store
        self.databaseWriter = databaseWriter
        self.now = now
    }

    func sync(connectors: [any KnowledgeImportConnector]) async -> KnowledgeImportRunResult {
        let startedAt = now()
        var connectorResults = [KnowledgeImportConnectorRunResult]()

        for connector in connectors {
            do {
                let snapshots = try await connector.fetchSnapshots()
                try Self.validate(snapshots: snapshots, match: connector)

                let uniqueSnapshots = Self.newestSnapshotsByRemoteID(from: snapshots)
                let existingDocuments = try databaseWriter.fetchImportedKnowledgeDocuments(
                    connectorInstanceID: connector.connectorInstanceID,
                    includeDeleted: true
                )
                var existingDocumentsByRemoteID = Dictionary(
                    uniqueKeysWithValues: existingDocuments.map { ($0.remoteID, $0) }
                )
                var changedDocumentCount = 0

                for snapshot in uniqueSnapshots {
                    let existingDocument = existingDocumentsByRemoteID[snapshot.remoteID]
                    let saveResult = try store.saveWithResult(
                        snapshot,
                        now: now(),
                        existingDocument: existingDocument
                    )
                    let document = saveResult.document
                    if saveResult.didChange {
                        changedDocumentCount += 1
                    }
                    try databaseWriter.upsertImportedKnowledgeDocument(document)
                    existingDocumentsByRemoteID[snapshot.remoteID] = document
                }

                connectorResults.append(
                    KnowledgeImportConnectorRunResult(
                        connectorInstanceID: connector.connectorInstanceID,
                        connectorID: connector.connectorID,
                        status: .succeeded,
                        changedDocumentCount: changedDocumentCount,
                        errorMessage: nil
                    )
                )
            } catch {
                connectorResults.append(
                    KnowledgeImportConnectorRunResult(
                        connectorInstanceID: connector.connectorInstanceID,
                        connectorID: connector.connectorID,
                        status: .failed,
                        changedDocumentCount: 0,
                        errorMessage: Self.errorMessage(from: error)
                    )
                )
            }
        }

        return KnowledgeImportRunResult(
            startedAt: startedAt,
            finishedAt: now(),
            connectorResults: connectorResults
        )
    }

    private static func validate(
        snapshots: [KnowledgeImportSnapshot],
        match connector: any KnowledgeImportConnector
    ) throws {
        for snapshot in snapshots {
            guard snapshot.connectorInstanceID == connector.connectorInstanceID,
                  snapshot.connectorID == connector.connectorID else {
                throw KnowledgeImportCoordinatorError.snapshotIdentityMismatch(
                    connectorInstanceID: connector.connectorInstanceID,
                    connectorID: connector.connectorID,
                    snapshotConnectorInstanceID: snapshot.connectorInstanceID,
                    snapshotConnectorID: snapshot.connectorID,
                    remoteID: snapshot.remoteID
                )
            }
        }
    }

    private static func newestSnapshotsByRemoteID(
        from snapshots: [KnowledgeImportSnapshot]
    ) -> [KnowledgeImportSnapshot] {
        var snapshotsByRemoteID = [String: KnowledgeImportSnapshot]()
        var remoteIDOrder = [String]()

        for snapshot in snapshots {
            if let existingSnapshot = snapshotsByRemoteID[snapshot.remoteID] {
                if isSnapshot(snapshot, fresherThanOrEqualTo: existingSnapshot) {
                    snapshotsByRemoteID[snapshot.remoteID] = snapshot
                }
            } else {
                snapshotsByRemoteID[snapshot.remoteID] = snapshot
                remoteIDOrder.append(snapshot.remoteID)
            }
        }

        return remoteIDOrder.compactMap { snapshotsByRemoteID[$0] }
    }

    private static func isSnapshot(
        _ candidate: KnowledgeImportSnapshot,
        fresherThanOrEqualTo other: KnowledgeImportSnapshot
    ) -> Bool {
        if let candidateRemoteUpdatedAt = candidate.remoteUpdatedAt,
           let otherRemoteUpdatedAt = other.remoteUpdatedAt {
            return candidateRemoteUpdatedAt >= otherRemoteUpdatedAt
        }

        if candidate.remoteUpdatedAt != nil && other.remoteUpdatedAt == nil {
            return true
        }
        if candidate.remoteUpdatedAt == nil && other.remoteUpdatedAt != nil {
            return false
        }

        return true
    }

    private static func errorMessage(from error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let errorDescription = localizedError.errorDescription {
            return errorDescription
        }
        return String(describing: error)
    }
}

private enum KnowledgeImportCoordinatorError: LocalizedError {
    case snapshotIdentityMismatch(
        connectorInstanceID: String,
        connectorID: KnowledgeConnectorID,
        snapshotConnectorInstanceID: String,
        snapshotConnectorID: KnowledgeConnectorID,
        remoteID: String
    )

    var errorDescription: String? {
        switch self {
        case let .snapshotIdentityMismatch(
            connectorInstanceID,
            connectorID,
            snapshotConnectorInstanceID,
            snapshotConnectorID,
            remoteID
        ):
            return """
            Snapshot identity mismatch for remoteID \(remoteID): connector \(connectorInstanceID) \
            (\(connectorID.rawValue)) received snapshot for \(snapshotConnectorInstanceID) \
            (\(snapshotConnectorID.rawValue)).
            """
        }
    }
}
