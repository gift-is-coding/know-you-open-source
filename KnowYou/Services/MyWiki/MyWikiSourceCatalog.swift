import Foundation

enum MyWikiSourceKind: String, Codable, Equatable, Sendable {
    case diary
    case externalDocument
    case manualFile
}

enum MyWikiSourceProcessingStatus: String, Codable, Equatable, Sendable {
    case notIncluded = "Not included"
    case pending = "Pending"
    case indexed = "Indexed"
    case changed = "Changed"
    case excludedIndexed = "Excluded, indexed"
    case failed = "Failed"
}

enum MyWikiSourceSelectionState: Hashable, Sendable {
    case included
    case excluded
    case mixed
}

enum MyWikiSourceCatalogBulkAction: Sendable {
    case includeVisible
    case excludeVisible
    case invertVisible
}

struct MyWikiSourceCandidate: Equatable, Sendable {
    var sourceID: String
    var sourceKind: MyWikiSourceKind
    var connectorInstanceID: String?
    var connectorID: KnowledgeConnectorID?
    var displayTitle: String
    var relativePath: String
    var sourcePath: String?
    var sourceURL: String?
    var contentHash: String
    var remoteUpdatedAt: Date?
    var defaultIncluded: Bool
    var materializedRelativePath: String
    var folderContext: String
}

struct MyWikiSourceCatalogRecord: Codable, Equatable, Identifiable, Sendable {
    var id: String { sourceID }

    var sourceID: String
    var sourceKind: MyWikiSourceKind
    var connectorInstanceID: String?
    var connectorID: KnowledgeConnectorID?
    var displayTitle: String
    var relativePath: String
    var sourcePath: String?
    var sourceURL: String?
    var contentHash: String
    var remoteUpdatedAt: Date?
    var included: Bool
    var includedDefault: Bool
    var lastIndexedHash: String?
    var lastIndexedAt: Date?
    var lastIngestError: String?
    var rawSourcePath: String
    var wikiSummaryPath: String?
    var folderContext: String

    var status: MyWikiSourceProcessingStatus {
        if included, lastIngestError != nil {
            return .failed
        }

        if included == false {
            return lastIndexedHash == nil ? .notIncluded : .excludedIndexed
        }

        guard let lastIndexedHash else {
            return .pending
        }

        return lastIndexedHash == contentHash ? .indexed : .changed
    }

    init(candidate: MyWikiSourceCandidate) {
        self.sourceID = candidate.sourceID
        self.sourceKind = candidate.sourceKind
        self.connectorInstanceID = candidate.connectorInstanceID
        self.connectorID = candidate.connectorID
        self.displayTitle = candidate.displayTitle
        self.relativePath = candidate.relativePath
        self.sourcePath = candidate.sourcePath
        self.sourceURL = candidate.sourceURL
        self.contentHash = candidate.contentHash
        self.remoteUpdatedAt = candidate.remoteUpdatedAt
        self.included = candidate.defaultIncluded
        self.includedDefault = candidate.defaultIncluded
        self.lastIndexedHash = nil
        self.lastIndexedAt = nil
        self.lastIngestError = nil
        self.rawSourcePath = "raw/sources/\(candidate.materializedRelativePath)"
        self.wikiSummaryPath = nil
        self.folderContext = candidate.folderContext
    }

    init(
        sourceID: String,
        sourceKind: MyWikiSourceKind,
        connectorInstanceID: String?,
        connectorID: KnowledgeConnectorID?,
        displayTitle: String,
        relativePath: String,
        sourcePath: String?,
        sourceURL: String?,
        contentHash: String,
        remoteUpdatedAt: Date?,
        included: Bool,
        includedDefault: Bool,
        lastIndexedHash: String?,
        lastIndexedAt: Date?,
        lastIngestError: String?,
        rawSourcePath: String,
        wikiSummaryPath: String?,
        folderContext: String
    ) {
        self.sourceID = sourceID
        self.sourceKind = sourceKind
        self.connectorInstanceID = connectorInstanceID
        self.connectorID = connectorID
        self.displayTitle = displayTitle
        self.relativePath = relativePath
        self.sourcePath = sourcePath
        self.sourceURL = sourceURL
        self.contentHash = contentHash
        self.remoteUpdatedAt = remoteUpdatedAt
        self.included = included
        self.includedDefault = includedDefault
        self.lastIndexedHash = lastIndexedHash
        self.lastIndexedAt = lastIndexedAt
        self.lastIngestError = lastIngestError
        self.rawSourcePath = rawSourcePath
        self.wikiSummaryPath = wikiSummaryPath
        self.folderContext = folderContext
    }

    mutating func update(from candidate: MyWikiSourceCandidate) {
        sourceKind = candidate.sourceKind
        connectorInstanceID = candidate.connectorInstanceID
        connectorID = candidate.connectorID
        displayTitle = candidate.displayTitle
        relativePath = candidate.relativePath
        sourcePath = candidate.sourcePath
        sourceURL = candidate.sourceURL
        contentHash = candidate.contentHash
        remoteUpdatedAt = candidate.remoteUpdatedAt
        includedDefault = candidate.defaultIncluded
        rawSourcePath = "raw/sources/\(candidate.materializedRelativePath)"
        folderContext = candidate.folderContext
    }
}

struct MyWikiSourceCatalogSnapshot: Codable, Equatable, Sendable {
    var records: [MyWikiSourceCatalogRecord]

    mutating func apply(action: MyWikiSourceCatalogBulkAction, visibleSourceIDs: [String]) {
        let visibleSourceIDs = Set(visibleSourceIDs)
        guard visibleSourceIDs.isEmpty == false else { return }

        for index in records.indices where visibleSourceIDs.contains(records[index].sourceID) {
            switch action {
            case .includeVisible:
                records[index].included = true
            case .excludeVisible:
                records[index].included = false
            case .invertVisible:
                records[index].included.toggle()
            }
        }
    }

    func merged(with candidates: [MyWikiSourceCandidate]) -> MyWikiSourceCatalogSnapshot {
        var existingByID = Dictionary(uniqueKeysWithValues: records.map { ($0.sourceID, $0) })
        var mergedRecords: [MyWikiSourceCatalogRecord] = []

        for candidate in candidates.sorted(by: Self.sortCandidates) {
            if var record = existingByID.removeValue(forKey: candidate.sourceID) {
                record.update(from: candidate)
                mergedRecords.append(record)
            } else {
                mergedRecords.append(MyWikiSourceCatalogRecord(candidate: candidate))
            }
        }

        let retainedHistoricalRecords = existingByID.values
            .filter { $0.lastIndexedHash != nil }
            .sorted(by: Self.sortRecordsByRelativePath)
        mergedRecords.append(contentsOf: retainedHistoricalRecords)
        return MyWikiSourceCatalogSnapshot(records: mergedRecords)
    }

    private static func sortCandidates(_ lhs: MyWikiSourceCandidate, _ rhs: MyWikiSourceCandidate) -> Bool {
        if lhs.sourceKind != rhs.sourceKind {
            return lhs.sourceKind.rawValue < rhs.sourceKind.rawValue
        }

        if lhs.relativePath != rhs.relativePath {
            return lhs.relativePath.localizedStandardCompare(rhs.relativePath) == .orderedAscending
        }

        return lhs.sourceID.localizedStandardCompare(rhs.sourceID) == .orderedAscending
    }

    private static func sortRecordsByRelativePath(
        _ lhs: MyWikiSourceCatalogRecord,
        _ rhs: MyWikiSourceCatalogRecord
    ) -> Bool {
        if lhs.relativePath != rhs.relativePath {
            return lhs.relativePath.localizedStandardCompare(rhs.relativePath) == .orderedAscending
        }

        return lhs.sourceID.localizedStandardCompare(rhs.sourceID) == .orderedAscending
    }
}

enum MyWikiSourceLibraryDisplayPolicy {
    static let manualImportsStorageRoot = "Manual Imports"
    static let manualUploadsDisplayRoot = "Manual Uploads"

    static func displayRelativePath(for record: MyWikiSourceCatalogRecord) -> String {
        guard record.sourceKind == .manualFile else {
            return record.relativePath
        }
        return displayRelativePath(forRawRelativePath: record.relativePath)
    }

    static func displayRelativePath(forRawRelativePath relativePath: String) -> String {
        if relativePath == manualImportsStorageRoot {
            return manualUploadsDisplayRoot
        }

        let prefix = "\(manualImportsStorageRoot)/"
        guard relativePath.hasPrefix(prefix) else {
            return relativePath
        }

        return "\(manualUploadsDisplayRoot)/\(relativePath.dropFirst(prefix.count))"
    }
}

struct MyWikiSourceLibraryPresentation: Equatable, Sendable {
    var snapshot: MyWikiSourceCatalogSnapshot
    var query: String
    var statusFilter: MyWikiSourceProcessingStatus?
    var includedOnly: Bool
    var visibleRecords: [MyWikiSourceCatalogRecord]
    var tree: MyWikiSourceCatalogNode
    var totalCount: Int
    var includedCount: Int
    var pendingCount: Int
    var changedCount: Int
    var failedCount: Int

    init(
        snapshot: MyWikiSourceCatalogSnapshot,
        query: String = "",
        statusFilter: MyWikiSourceProcessingStatus? = nil,
        includedOnly: Bool = false
    ) {
        self.snapshot = snapshot
        self.query = query
        self.statusFilter = statusFilter
        self.includedOnly = includedOnly
        self.totalCount = snapshot.records.count
        self.includedCount = snapshot.records.filter(\.included).count
        self.pendingCount = snapshot.records.filter { $0.status == .pending }.count
        self.changedCount = snapshot.records.filter { $0.status == .changed }.count
        self.failedCount = snapshot.records.filter { $0.status == .failed }.count

        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.visibleRecords = snapshot.records
            .filter { record in
                guard normalizedQuery.isEmpty == false else { return true }
                let displayRelativePath = MyWikiSourceLibraryDisplayPolicy.displayRelativePath(for: record)
                return record.displayTitle.lowercased().contains(normalizedQuery)
                    || record.relativePath.lowercased().contains(normalizedQuery)
                    || displayRelativePath.lowercased().contains(normalizedQuery)
            }
            .filter { record in
                guard let statusFilter else { return true }
                return record.status == statusFilter
            }
            .filter { record in
                includedOnly == false || record.included
            }
            .sorted(by: Self.sortRecords)
        self.tree = MyWikiSourceCatalogTreeBuilder(
            displayPath: MyWikiSourceLibraryDisplayPolicy.displayRelativePath(for:)
        ).build(records: visibleRecords)
    }

    private static func sortRecords(
        _ lhs: MyWikiSourceCatalogRecord,
        _ rhs: MyWikiSourceCatalogRecord
    ) -> Bool {
        if lhs.relativePath != rhs.relativePath {
            return lhs.relativePath.localizedStandardCompare(rhs.relativePath) == .orderedAscending
        }
        return lhs.sourceID.localizedStandardCompare(rhs.sourceID) == .orderedAscending
    }
}

struct MyWikiSourceCatalogNode: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case root
        case directory
        case source(MyWikiSourceCatalogRecord)
    }

    var id: String
    var title: String
    var kind: Kind
    var selectionState: MyWikiSourceSelectionState
    var children: [MyWikiSourceCatalogNode]
}

struct MyWikiSourceCatalogTreeBuilder {
    private let displayPath: (MyWikiSourceCatalogRecord) -> String

    init(displayPath: @escaping (MyWikiSourceCatalogRecord) -> String = { $0.relativePath }) {
        self.displayPath = displayPath
    }

    func build(records: [MyWikiSourceCatalogRecord]) -> MyWikiSourceCatalogNode {
        let children = buildChildren(records: records, prefix: "", depth: 0)
        return MyWikiSourceCatalogNode(
            id: "root",
            title: "Sources",
            kind: .root,
            selectionState: selectionState(for: children),
            children: children
        )
    }

    private func buildChildren(records: [MyWikiSourceCatalogRecord], prefix: String, depth: Int) -> [MyWikiSourceCatalogNode] {
        let sortedRecords = records.sorted {
            displayPath($0).localizedStandardCompare(displayPath($1)) == .orderedAscending
        }
        let leaves = sortedRecords.filter { pathComponents(for: $0).count == depth + 1 }
        let nested = sortedRecords.filter { pathComponents(for: $0).count > depth + 1 }
        let groupedNested = Dictionary(grouping: nested) { pathComponents(for: $0)[depth] }

        var nodes = leaves.map { record in
            MyWikiSourceCatalogNode(
                id: record.sourceID,
                title: record.displayTitle,
                kind: .source(record),
                selectionState: record.included ? .included : .excluded,
                children: []
            )
        }

        let directoryNodes = groupedNested.keys
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .map { directoryName in
                let directoryRecords = groupedNested[directoryName] ?? []
                let path = prefix.isEmpty ? directoryName : "\(prefix)/\(directoryName)"
                let children = buildChildren(records: directoryRecords, prefix: path, depth: depth + 1)
                return MyWikiSourceCatalogNode(
                    id: path,
                    title: directoryName,
                    kind: .directory,
                    selectionState: selectionState(for: children),
                    children: children
                )
            }

        nodes.append(contentsOf: directoryNodes)
        return nodes.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    private func selectionState(for children: [MyWikiSourceCatalogNode]) -> MyWikiSourceSelectionState {
        let leafStates = descendantLeafStates(from: children)
        guard let first = leafStates.first else {
            return .excluded
        }
        return leafStates.allSatisfy { $0 == first } ? first : .mixed
    }

    private func descendantLeafStates(from nodes: [MyWikiSourceCatalogNode]) -> [MyWikiSourceSelectionState] {
        nodes.flatMap { node -> [MyWikiSourceSelectionState] in
            switch node.kind {
            case .source:
                return [node.selectionState]
            case .root, .directory:
                return descendantLeafStates(from: node.children)
            }
        }
    }

    private func pathComponents(for record: MyWikiSourceCatalogRecord) -> [String] {
        displayPath(record).split(separator: "/").map(String.init)
    }
}

struct MyWikiSourceCatalogStore {
    private static let writeLocks = MyWikiSourceCatalogStoreWriteLocks()

    let projectRoot: URL
    let fileManager: FileManager

    init(projectRoot: URL, fileManager: FileManager = .default) {
        self.projectRoot = projectRoot
        self.fileManager = fileManager
    }

    static func emptySnapshot() -> MyWikiSourceCatalogSnapshot {
        MyWikiSourceCatalogSnapshot(records: [])
    }

    func load() throws -> MyWikiSourceCatalogSnapshot {
        let url = catalogURL
        guard fileManager.fileExists(atPath: url.path) else {
            return Self.emptySnapshot()
        }

        let data = try Data(contentsOf: url)
        return try JSONDecoder.knowledgeImport().decode(MyWikiSourceCatalogSnapshot.self, from: data)
    }

    func save(_ snapshot: MyWikiSourceCatalogSnapshot) throws {
        try fileManager.createDirectory(
            at: catalogURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder.knowledgeImport().encode(snapshot)
        try data.write(to: catalogURL, options: .atomic)
    }

    func update(
        _ transform: (inout MyWikiSourceCatalogSnapshot) throws -> Void
    ) throws -> MyWikiSourceCatalogSnapshot {
        let writeLock = Self.writeLocks.lock(for: catalogURL.path)
        writeLock.lock()
        defer { writeLock.unlock() }

        var snapshot = try load()
        try transform(&snapshot)
        try save(snapshot)
        return snapshot
    }

    private var catalogURL: URL {
        projectRoot.appending(path: ".knowyou/source-catalog.json")
    }
}

private final class MyWikiSourceCatalogStoreWriteLocks: @unchecked Sendable {
    private let guardLock = NSLock()
    private var locksByPath: [String: NSLock] = [:]

    func lock(for path: String) -> NSLock {
        guardLock.lock()
        defer { guardLock.unlock() }

        if let existingLock = locksByPath[path] {
            return existingLock
        }

        let newLock = NSLock()
        locksByPath[path] = newLock
        return newLock
    }
}
