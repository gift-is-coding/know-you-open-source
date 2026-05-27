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

        mergedRecords.append(contentsOf: existingByID.values.sorted(by: Self.sortRecordsByRelativePath))
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
            $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending
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
        record.relativePath.split(separator: "/").map(String.init)
    }
}

struct MyWikiSourceCatalogStore {
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
        return try JSONDecoder.myWikiSourceCatalog().decode(MyWikiSourceCatalogSnapshot.self, from: data)
    }

    func save(_ snapshot: MyWikiSourceCatalogSnapshot) throws {
        try fileManager.createDirectory(
            at: catalogURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder.myWikiSourceCatalog().encode(snapshot)
        try data.write(to: catalogURL, options: .atomic)
    }

    private var catalogURL: URL {
        projectRoot.appending(path: ".knowyou/source-catalog.json")
    }
}

private extension JSONEncoder {
    static func myWikiSourceCatalog() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = MyWikiSourceCatalogDateCoding.encodingStrategy
        return encoder
    }
}

private extension JSONDecoder {
    static func myWikiSourceCatalog() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = MyWikiSourceCatalogDateCoding.decodingStrategy
        return decoder
    }
}

private enum MyWikiSourceCatalogDateCoding {
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
