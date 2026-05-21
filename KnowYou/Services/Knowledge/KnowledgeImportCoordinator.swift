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

struct KnowledgeImportCoordinatorApplyHooks: Sendable {
    var beforeDatabaseUpsert: @Sendable (_ connectorInstanceID: String, _ documents: [ImportedKnowledgeDocument]) -> Void

    init(
        beforeDatabaseUpsert: @escaping @Sendable (_ connectorInstanceID: String, _ documents: [ImportedKnowledgeDocument]) -> Void = { _, _ in }
    ) {
        self.beforeDatabaseUpsert = beforeDatabaseUpsert
    }
}

struct KnowledgeImportCoordinator: @unchecked Sendable {
    private static let applyLocks = KnowledgeImportCoordinatorApplyLocks()

    let store: KnowledgeImportStore
    let databaseWriter: DatabaseWriter
    let now: @Sendable () -> Date
    let applyHooks: KnowledgeImportCoordinatorApplyHooks

    init(
        store: KnowledgeImportStore,
        databaseWriter: DatabaseWriter,
        now: @escaping @Sendable () -> Date = Date.init,
        applyHooks: KnowledgeImportCoordinatorApplyHooks = KnowledgeImportCoordinatorApplyHooks()
    ) {
        self.store = store
        self.databaseWriter = databaseWriter
        self.now = now
        self.applyHooks = applyHooks
    }

    func sync(connectors: [any KnowledgeImportConnector]) async -> KnowledgeImportRunResult {
        let startedAt = now()
        var connectorResults = [KnowledgeImportConnectorRunResult]()

        for connector in connectors {
            do {
                let snapshots = try await connector.fetchSnapshots()
                try Self.validate(snapshots: snapshots, match: connector)

                let uniqueSnapshots = Self.newestSnapshotsByRemoteID(from: snapshots)
                let changedDocumentCount = try apply(uniqueSnapshots, for: connector)

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

    private func apply(
        _ snapshots: [KnowledgeImportSnapshot],
        for connector: any KnowledgeImportConnector
    ) throws -> Int {
        let applyLock = Self.applyLocks.lock(for: connector.connectorInstanceID)
        applyLock.lock()
        defer { applyLock.unlock() }

        let existingDocuments = try databaseWriter.fetchImportedKnowledgeDocuments(
            connectorInstanceID: connector.connectorInstanceID,
            includeDeleted: true
        )
        var existingDocumentsByRemoteID = Dictionary(
            uniqueKeysWithValues: existingDocuments.map { ($0.remoteID, $0) }
        )
        var saveResults = [KnowledgeImportSaveResult]()

        for snapshot in snapshots {
            let existingDocument = existingDocumentsByRemoteID[snapshot.remoteID]
            let saveResult = try store.saveWithResult(
                snapshot,
                now: now(),
                existingDocument: existingDocument
            )
            let document = saveResult.document
            saveResults.append(saveResult)
            existingDocumentsByRemoteID[snapshot.remoteID] = document
        }

        let documents = saveResults.map(\.document)
        applyHooks.beforeDatabaseUpsert(connector.connectorInstanceID, documents)
        try databaseWriter.upsertImportedKnowledgeDocuments(documents)
        return saveResults.filter(\.didChange).count
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

private final class KnowledgeImportCoordinatorApplyLocks: @unchecked Sendable {
    private let lock = NSLock()
    private var locksByConnectorInstanceID = [String: NSLock]()

    func lock(for connectorInstanceID: String) -> NSLock {
        lock.lock()
        defer { lock.unlock() }

        if let existingLock = locksByConnectorInstanceID[connectorInstanceID] {
            return existingLock
        }

        let newLock = NSLock()
        locksByConnectorInstanceID[connectorInstanceID] = newLock
        return newLock
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
