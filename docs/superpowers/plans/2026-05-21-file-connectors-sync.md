# File Connectors Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a local-first Knowledge Imports connector system that imports Obsidian, local folder, Feishu, Notion, and Google Drive documents into a KnowYou-owned local Markdown cache while keeping existing daily diary export one-way and loop-safe.

**Architecture:** Add a new Knowledge Imports domain beside existing Sync Memory export. Imported documents are represented by Swift domain models, indexed in SQLite, and stored as `content.md` plus `metadata.json` under Application Support. Local/Obsidian connectors and API connectors feed a shared import coordinator; AppState exposes separate export/import config, status, scheduling, and UI presentation.

**Tech Stack:** Swift 6, SwiftUI, GRDB, XCTest, URLSession with URLProtocol fakes, KeychainHelper, LaunchAgentManager, local file system APIs.

---

## Reference Notes

- Notion official API: `POST /v1/search` finds pages shared with an integration; `GET /v1/blocks/{block_id}/children` returns paginated child blocks and must be called recursively for nested content.
- Google Drive official API: `GET https://www.googleapis.com/drive/v3/files` lists files; `GET https://www.googleapis.com/drive/v3/files/{fileId}/export?mimeType=...` exports Google Workspace documents and requires OAuth scopes such as `drive.readonly`.
- Google desktop OAuth official guidance supports installed-app authorization with an authorization code and token exchange. Use Keychain for refresh/access tokens.
- Feishu/Lark official cloud docs API provides Markdown document content through `GET /open-apis/docs/v1/content`; OAuth authorization starts at the Feishu authorization endpoint and yields an auth code.

## File Structure

Create these production files:

- `KnowYou/Domain/KnowledgeImport.swift`: connector IDs, connector kind, connector config summary, imported document, sync status, and sync result value types.
- `KnowYou/Services/Knowledge/KnowledgeImportStore.swift`: local `content.md` and `metadata.json` file writer/reader.
- `KnowYou/Services/Knowledge/KnowledgeImportCoordinator.swift`: common sync runner that invokes connector implementations and persists snapshots.
- `KnowYou/Services/Knowledge/KnowledgeImportConnector.swift`: shared protocol and error types.
- `KnowYou/Services/Knowledge/LocalFolderKnowledgeConnector.swift`: Markdown/text scanner for local folders.
- `KnowYou/Services/Knowledge/ObsidianKnowledgeConnector.swift`: Obsidian vault scanner that skips KnowYou daily export mirrors.
- `KnowYou/Services/Knowledge/KnowledgeHTTPClient.swift`: small URLSession wrapper for API connectors.
- `KnowYou/Services/Knowledge/FeishuKnowledgeConnector.swift`: Feishu/Lark Markdown content importer.
- `KnowYou/Services/Knowledge/NotionKnowledgeConnector.swift`: Notion search + recursive block-to-Markdown importer.
- `KnowYou/Services/Knowledge/GoogleDriveKnowledgeConnector.swift`: Drive file list + Google Docs export importer.
- `KnowYou/Services/Knowledge/KnowledgeImportConfig.swift`: UserDefaults config plus Keychain-backed credentials.
- `KnowYou/UI/Settings/ConnectorsPanel.swift`: replacement panel containing Daily Memory Export and Knowledge Imports sections.

Modify these existing files:

- `KnowYou/Services/Storage/Migrations.swift`: add knowledge import tables.
- `KnowYou/Services/Storage/DatabaseWriter.swift`: add CRUD methods for connector instances, imported docs, sync status, and tombstones.
- `KnowYou/Services/SyncMemory/SyncMemoryCoordinator.swift`: write KnowYou export markers.
- `KnowYou/Services/SyncMemory/LaunchAgentManager.swift`: add `knowledgeImportRegistration`.
- `KnowYou/App/AppEnvironment.swift`: expose `knowledgeSourcesDirectoryURL` and own the import coordinator dependencies.
- `KnowYou/App/AppState.swift`: add config/status state, manual import action, and schedule persistence.
- `KnowYou/UI/MainWindowView.swift`: route secondary menu from Sync Memory to Connectors.
- `docs/architecture.md` and `docs/requirements-spec.md`: update product boundaries.
- `KnowYou.xcodeproj/project.pbxproj`: include all new Swift files in app and test targets.

Create these test files:

- `KnowYouTests/KnowledgeImportModelTests.swift`
- `KnowYouTests/KnowledgeImportStoreTests.swift`
- `KnowYouTests/KnowledgeImportDatabaseTests.swift`
- `KnowYouTests/KnowledgeImportCoordinatorTests.swift`
- `KnowYouTests/LocalFolderKnowledgeConnectorTests.swift`
- `KnowYouTests/ObsidianKnowledgeConnectorTests.swift`
- `KnowYouTests/KnowledgeAPIConnectorTests.swift`
- `KnowYouTests/ConnectorsPanelTests.swift`

---

### Task 1: Knowledge Import Domain And Config

**Files:**
- Create: `KnowYou/Domain/KnowledgeImport.swift`
- Create: `KnowYou/Services/Knowledge/KnowledgeImportConfig.swift`
- Test: `KnowYouTests/KnowledgeImportModelTests.swift`
- Modify: `KnowYou.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write the failing model/config tests**

```swift
import XCTest
@testable import KnowYou

final class KnowledgeImportModelTests: XCTestCase {
    func testConnectorIDSeparatesExportAndImportDirections() {
        XCTAssertEqual(KnowledgeConnectorID.obsidianImport.rawValue, "obsidian-import")
        XCTAssertEqual(KnowledgeConnectorID.obsidianExport.rawValue, "obsidian-export")
        XCTAssertNotEqual(KnowledgeConnectorID.obsidianImport, .obsidianExport)
    }

    func testConfigPersistenceKeepsImportSeparateFromSyncMemoryExport() {
        let suiteName = "KnowledgeImportModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var config = KnowledgeImportConfig.default
        config.isImportEnabled = true
        config.dailyImportHour = 7
        config.dailyImportMinute = 45
        config.connectorInstances = [
            KnowledgeConnectorInstanceConfig(
                id: "local-main",
                connectorID: .localFolderImport,
                displayName: "Docs",
                sourcePath: "/Users/test/Documents",
                isEnabled: true
            )
        ]
        config.save(to: defaults)

        let loaded = KnowledgeImportConfig.load(from: defaults)
        XCTAssertTrue(loaded.isImportEnabled)
        XCTAssertEqual(loaded.dailyImportHour, 7)
        XCTAssertEqual(loaded.dailyImportMinute, 45)
        XCTAssertEqual(loaded.connectorInstances.first?.connectorID, .localFolderImport)
    }
}
```

- [ ] **Step 2: Run model tests and verify failure**

Run:

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/KnowledgeImportModelTests
```

Expected: compile fails because `KnowledgeConnectorID`, `KnowledgeImportConfig`, and `KnowledgeConnectorInstanceConfig` do not exist.

- [ ] **Step 3: Add domain models**

Create `KnowYou/Domain/KnowledgeImport.swift`:

```swift
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
```

- [ ] **Step 4: Add config persistence**

Create `KnowYou/Services/Knowledge/KnowledgeImportConfig.swift`:

```swift
import Foundation

struct KnowledgeImportConfig: Codable, Equatable, Sendable {
    var isImportEnabled = false
    var dailyImportHour = 7
    var dailyImportMinute = 30
    var connectorInstances: [KnowledgeConnectorInstanceConfig] = []

    static let `default` = KnowledgeImportConfig()
    private static let storageKey = "knowledgeImportConfig"

    func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }

    static func load(from defaults: UserDefaults = .standard) -> KnowledgeImportConfig {
        guard
            let data = defaults.data(forKey: storageKey),
            let decoded = try? JSONDecoder().decode(KnowledgeImportConfig.self, from: data)
        else {
            return .default
        }
        return decoded
    }
}

struct KnowledgeImportCredentialStore: Sendable {
    let keychain: KeychainStoring
    let service: String

    init(keychain: KeychainStoring = KeychainHelper.shared, service: String = KeychainHelper.service) {
        self.keychain = keychain
        self.service = service
    }

    func saveBearerToken(_ token: String, connectorInstanceID: String) {
        keychain.save(token, forKey: "knowledge-import.\(connectorInstanceID).bearer-token", service: service)
    }

    func bearerToken(connectorInstanceID: String) -> String? {
        keychain.load(forKey: "knowledge-import.\(connectorInstanceID).bearer-token", service: service)
    }

    func deleteBearerToken(connectorInstanceID: String) {
        keychain.delete(forKey: "knowledge-import.\(connectorInstanceID).bearer-token", service: service)
    }
}
```

- [ ] **Step 5: Add target membership and run tests**

Add new Swift files to the Xcode project under `Domain` and `Services/Knowledge`, and add the test file to `KnowYouTests`.

Run:

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/KnowledgeImportModelTests
```

Expected: tests pass.

- [ ] **Step 6: Commit**

```bash
git add KnowYou/Domain/KnowledgeImport.swift KnowYou/Services/Knowledge/KnowledgeImportConfig.swift KnowYouTests/KnowledgeImportModelTests.swift KnowYou.xcodeproj/project.pbxproj
git commit -m "Add knowledge import domain config"
```

---

### Task 2: SQLite Index For Imported Knowledge

**Files:**
- Modify: `KnowYou/Services/Storage/Migrations.swift`
- Modify: `KnowYou/Services/Storage/DatabaseWriter.swift`
- Test: `KnowYouTests/KnowledgeImportDatabaseTests.swift`
- Modify: `KnowYou.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write failing database tests**

```swift
import XCTest
@testable import KnowYou

final class KnowledgeImportDatabaseTests: XCTestCase {
    func testUpsertImportedDocumentUpdatesSameRemoteIdentity() throws {
        let writer = try DatabaseWriter.inMemory()
        let first = makeDocument(remoteID: "remote-1", contentHash: "hash-a", title: "Original")
        let second = makeDocument(remoteID: "remote-1", contentHash: "hash-b", title: "Updated")

        try writer.upsertImportedKnowledgeDocument(first)
        try writer.upsertImportedKnowledgeDocument(second)

        let documents = try writer.fetchImportedKnowledgeDocuments(connectorInstanceID: "local-main")
        XCTAssertEqual(documents.count, 1)
        XCTAssertEqual(documents[0].title, "Updated")
        XCTAssertEqual(documents[0].contentHash, "hash-b")
    }

    func testMarkDeletedRecordsTombstoneWithoutRemovingRow() throws {
        let writer = try DatabaseWriter.inMemory()
        let document = makeDocument(remoteID: "remote-2", contentHash: "hash-c", title: "Deleted")
        try writer.upsertImportedKnowledgeDocument(document)

        let deletedAt = Date(timeIntervalSince1970: 1_779_000_000)
        try writer.markImportedKnowledgeDocumentDeleted(
            connectorInstanceID: "local-main",
            remoteID: "remote-2",
            deletedAt: deletedAt
        )

        let documents = try writer.fetchImportedKnowledgeDocuments(connectorInstanceID: "local-main", includeDeleted: true)
        XCTAssertEqual(documents.count, 1)
        XCTAssertEqual(documents[0].deletedAt, deletedAt)
    }

    private func makeDocument(remoteID: String, contentHash: String, title: String) -> ImportedKnowledgeDocument {
        ImportedKnowledgeDocument(
            id: "local-main:\(remoteID)",
            connectorInstanceID: "local-main",
            connectorID: .localFolderImport,
            remoteID: remoteID,
            title: title,
            sourcePath: "/tmp/\(remoteID).md",
            remoteURL: nil,
            mimeType: "text/markdown",
            contentHash: contentHash,
            remoteUpdatedAt: Date(timeIntervalSince1970: 1_778_000_000),
            firstImportedAt: Date(timeIntervalSince1970: 1_778_000_001),
            lastSyncedAt: Date(timeIntervalSince1970: 1_778_000_002),
            deletedAt: nil,
            localContentPath: "/cache/\(remoteID)/content.md",
            localMetadataPath: "/cache/\(remoteID)/metadata.json",
            normalizationVersion: 1,
            originKind: "local-file"
        )
    }
}
```

- [ ] **Step 2: Run database tests and verify failure**

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/KnowledgeImportDatabaseTests
```

Expected: compile fails because database methods do not exist.

- [ ] **Step 3: Add migrations**

In `Migrations.migrator()`, after `addDayKeyToRuns`, register:

```swift
migrator.registerMigration("createKnowledgeImports") { db in
    try db.create(table: "knowledge_import_documents", ifNotExists: true) { table in
        table.column("id", .text).primaryKey()
        table.column("connectorInstanceID", .text).notNull()
        table.column("connectorID", .text).notNull()
        table.column("remoteID", .text).notNull()
        table.column("title", .text).notNull()
        table.column("sourcePath", .text)
        table.column("remoteURL", .text)
        table.column("mimeType", .text).notNull()
        table.column("contentHash", .text).notNull()
        table.column("remoteUpdatedAt", .datetime)
        table.column("firstImportedAt", .datetime).notNull()
        table.column("lastSyncedAt", .datetime).notNull()
        table.column("deletedAt", .datetime)
        table.column("localContentPath", .text).notNull()
        table.column("localMetadataPath", .text).notNull()
        table.column("normalizationVersion", .integer).notNull()
        table.column("originKind", .text).notNull()
        table.uniqueKey(["connectorInstanceID", "remoteID"], onConflict: .replace)
    }

    try db.create(table: "knowledge_import_status", ifNotExists: true) { table in
        table.column("connectorInstanceID", .text).primaryKey()
        table.column("lastStartedAt", .datetime)
        table.column("lastSucceededAt", .datetime)
        table.column("lastFailedAt", .datetime)
        table.column("lastErrorMessage", .text)
        table.column("lastChangedDocumentCount", .integer).notNull().defaults(to: 0)
    }
}
```

- [ ] **Step 4: Add DatabaseWriter methods**

Add methods to `DatabaseWriter`:

```swift
func upsertImportedKnowledgeDocument(_ document: ImportedKnowledgeDocument) throws {
    try dbQueue.write { db in
        try db.execute(
            sql: """
            INSERT INTO knowledge_import_documents
            (id, connectorInstanceID, connectorID, remoteID, title, sourcePath, remoteURL, mimeType, contentHash,
             remoteUpdatedAt, firstImportedAt, lastSyncedAt, deletedAt, localContentPath, localMetadataPath,
             normalizationVersion, originKind)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(connectorInstanceID, remoteID) DO UPDATE SET
                title = excluded.title,
                sourcePath = excluded.sourcePath,
                remoteURL = excluded.remoteURL,
                mimeType = excluded.mimeType,
                contentHash = excluded.contentHash,
                remoteUpdatedAt = excluded.remoteUpdatedAt,
                lastSyncedAt = excluded.lastSyncedAt,
                deletedAt = excluded.deletedAt,
                localContentPath = excluded.localContentPath,
                localMetadataPath = excluded.localMetadataPath,
                normalizationVersion = excluded.normalizationVersion,
                originKind = excluded.originKind
            """,
            arguments: [
                document.id,
                document.connectorInstanceID,
                document.connectorID.rawValue,
                document.remoteID,
                document.title,
                document.sourcePath,
                document.remoteURL,
                document.mimeType,
                document.contentHash,
                document.remoteUpdatedAt,
                document.firstImportedAt,
                document.lastSyncedAt,
                document.deletedAt,
                document.localContentPath,
                document.localMetadataPath,
                document.normalizationVersion,
                document.originKind,
            ]
        )
    }
}

func fetchImportedKnowledgeDocuments(
    connectorInstanceID: String? = nil,
    includeDeleted: Bool = false
) throws -> [ImportedKnowledgeDocument] {
    try dbQueue.read { db in
        var clauses: [String] = []
        var arguments: [DatabaseValueConvertible?] = []
        if let connectorInstanceID {
            clauses.append("connectorInstanceID = ?")
            arguments.append(connectorInstanceID)
        }
        if !includeDeleted {
            clauses.append("deletedAt IS NULL")
        }
        let whereSQL = clauses.isEmpty ? "" : " WHERE " + clauses.joined(separator: " AND ")
        let rows = try Row.fetchAll(
            db,
            sql: "SELECT * FROM knowledge_import_documents\(whereSQL) ORDER BY title ASC",
            arguments: StatementArguments(arguments)
        )
        return try rows.map(Self.importedKnowledgeDocument(from:))
    }
}

func markImportedKnowledgeDocumentDeleted(
    connectorInstanceID: String,
    remoteID: String,
    deletedAt: Date
) throws {
    try dbQueue.write { db in
        try db.execute(
            sql: """
            UPDATE knowledge_import_documents
            SET deletedAt = ?, lastSyncedAt = ?
            WHERE connectorInstanceID = ? AND remoteID = ?
            """,
            arguments: [deletedAt, deletedAt, connectorInstanceID, remoteID]
        )
    }
}
```

Add private row decoding:

```swift
private static func importedKnowledgeDocument(from row: Row) throws -> ImportedKnowledgeDocument {
    let connectorIDString: String = row["connectorID"]
    guard let connectorID = KnowledgeConnectorID(rawValue: connectorIDString) else {
        throw DatabaseWriterRowError.invalidValue(field: "knowledge_import_documents.connectorID", value: connectorIDString)
    }
    return ImportedKnowledgeDocument(
        id: row["id"],
        connectorInstanceID: row["connectorInstanceID"],
        connectorID: connectorID,
        remoteID: row["remoteID"],
        title: row["title"],
        sourcePath: row["sourcePath"],
        remoteURL: row["remoteURL"],
        mimeType: row["mimeType"],
        contentHash: row["contentHash"],
        remoteUpdatedAt: row["remoteUpdatedAt"],
        firstImportedAt: row["firstImportedAt"],
        lastSyncedAt: row["lastSyncedAt"],
        deletedAt: row["deletedAt"],
        localContentPath: row["localContentPath"],
        localMetadataPath: row["localMetadataPath"],
        normalizationVersion: row["normalizationVersion"],
        originKind: row["originKind"]
    )
}
```

- [ ] **Step 5: Run database tests**

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/KnowledgeImportDatabaseTests
```

Expected: tests pass.

- [ ] **Step 6: Commit**

```bash
git add KnowYou/Services/Storage/Migrations.swift KnowYou/Services/Storage/DatabaseWriter.swift KnowYouTests/KnowledgeImportDatabaseTests.swift KnowYou.xcodeproj/project.pbxproj
git commit -m "Add knowledge import database index"
```

---

### Task 3: Local Markdown Cache Store

**Status:** Completed in commits `e41050d` through `f9cb6e8`. The final implementation keeps the planned local Markdown cache shape and adds durability hardening for DB-authoritative resyncs, corrupt metadata recovery, fractional date preservation, path normalization, and same-document concurrent/stale-write protection.

**Files:**
- Create: `KnowYou/Services/Knowledge/KnowledgeImportStore.swift`
- Test: `KnowYouTests/KnowledgeImportStoreTests.swift`
- Modify: `KnowYou.xcodeproj/project.pbxproj`

- [x] **Step 1: Write failing store tests**

```swift
import XCTest
@testable import KnowYou

final class KnowledgeImportStoreTests: XCTestCase {
    func testSaveSnapshotWritesContentAndMetadata() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = KnowledgeImportStore(rootDirectory: root, fileManager: .default)
        let snapshot = KnowledgeImportSnapshot(
            connectorInstanceID: "local-main",
            connectorID: .localFolderImport,
            remoteID: "docs/readme.md",
            title: "Readme",
            sourcePath: "/Users/test/docs/readme.md",
            remoteURL: nil,
            mimeType: "text/markdown",
            markdown: "# Hello",
            remoteUpdatedAt: Date(timeIntervalSince1970: 1_778_000_000),
            originKind: "local-file"
        )

        let document = try store.save(snapshot, now: Date(timeIntervalSince1970: 1_778_000_100))

        XCTAssertEqual(try String(contentsOf: URL(fileURLWithPath: document.localContentPath), encoding: .utf8), "# Hello")
        XCTAssertTrue(FileManager.default.fileExists(atPath: document.localMetadataPath))
        XCTAssertEqual(document.contentHash.count, 64)
    }
}
```

- [x] **Step 2: Run store tests and verify failure**

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/KnowledgeImportStoreTests
```

Expected: compile fails because `KnowledgeImportStore` and `KnowledgeImportSnapshot` do not exist.

- [x] **Step 3: Implement store**

Create `KnowYou/Services/Knowledge/KnowledgeImportStore.swift`:

```swift
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
```

- [x] **Step 4: Run store tests**

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/KnowledgeImportStoreTests
```

Expected: tests pass.

- [x] **Step 5: Commit**

```bash
git add KnowYou/Services/Knowledge/KnowledgeImportStore.swift KnowYouTests/KnowledgeImportStoreTests.swift KnowYou.xcodeproj/project.pbxproj
git commit -m "Add knowledge import local store"
```

---

### Task 4: Import Connector Protocol And Coordinator

**Status:** Completed in commits `05ff643` through `0e0e53d`. The final implementation keeps the planned connector/coordinator shape and adds connector errors, store-backed save results, per-connector apply serialization, transactional DB batch upserts, deterministic duplicate handling, rehydration/no-op changed-count semantics, and connector-level failure isolation.

**Files:**
- Create: `KnowYou/Services/Knowledge/KnowledgeImportConnector.swift`
- Create: `KnowYou/Services/Knowledge/KnowledgeImportCoordinator.swift`
- Test: `KnowYouTests/KnowledgeImportCoordinatorTests.swift`
- Modify: `KnowYou.xcodeproj/project.pbxproj`

- [x] **Step 1: Write failing coordinator tests**

```swift
import XCTest
@testable import KnowYou

final class KnowledgeImportCoordinatorTests: XCTestCase {
    func testSyncContinuesWhenOneConnectorFails() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let writer = try DatabaseWriter.inMemory()
        let store = KnowledgeImportStore(rootDirectory: root)
        let coordinator = KnowledgeImportCoordinator(databaseWriter: writer, store: store)

        let result = await coordinator.sync(connectors: [
            FailingConnector(instanceID: "bad"),
            StaticConnector(instanceID: "good")
        ])

        XCTAssertEqual(result.succeededConnectorIDs, ["good"])
        XCTAssertEqual(result.failedConnectorIDs, ["bad"])
        XCTAssertEqual(try writer.fetchImportedKnowledgeDocuments(connectorInstanceID: "good").count, 1)
    }
}

private struct StaticConnector: KnowledgeImportConnector {
    let instanceID: String
    let connectorID: KnowledgeConnectorID = .localFolderImport
    func snapshots() async throws -> [KnowledgeImportSnapshot] {
        [KnowledgeImportSnapshot(
            connectorInstanceID: instanceID,
            connectorID: connectorID,
            remoteID: "one.md",
            title: "One",
            sourcePath: "/tmp/one.md",
            remoteURL: nil,
            mimeType: "text/markdown",
            markdown: "# One",
            remoteUpdatedAt: nil,
            originKind: "test"
        )]
    }
}

private struct FailingConnector: KnowledgeImportConnector {
    let instanceID: String
    let connectorID: KnowledgeConnectorID = .localFolderImport
    func snapshots() async throws -> [KnowledgeImportSnapshot] {
        throw KnowledgeImportConnectorError.unavailable("network down")
    }
}
```

- [x] **Step 2: Run coordinator tests and verify failure**

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/KnowledgeImportCoordinatorTests
```

Expected: compile fails because coordinator/protocol types do not exist.

- [x] **Step 3: Implement protocol and coordinator**

Create `KnowledgeImportConnector.swift`:

```swift
import Foundation

enum KnowledgeImportConnectorError: LocalizedError, Equatable {
    case unavailable(String)
    case unauthorized(String)
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let message), .unauthorized(let message), .invalidResponse(let message):
            return message
        }
    }
}

protocol KnowledgeImportConnector: Sendable {
    var instanceID: String { get }
    var connectorID: KnowledgeConnectorID { get }
    func snapshots() async throws -> [KnowledgeImportSnapshot]
}

struct KnowledgeImportRunResult: Equatable, Sendable {
    var succeededConnectorIDs: [String] = []
    var failedConnectorIDs: [String] = []
    var changedDocumentCount: Int = 0
}
```

Create `KnowledgeImportCoordinator.swift`:

```swift
import Foundation

struct KnowledgeImportCoordinator {
    let databaseWriter: DatabaseWriter
    let store: KnowledgeImportStore

    func sync(connectors: [any KnowledgeImportConnector]) async -> KnowledgeImportRunResult {
        var result = KnowledgeImportRunResult()
        for connector in connectors {
            do {
                let snapshots = try await connector.snapshots()
                for snapshot in snapshots {
                    let document = try store.save(snapshot)
                    try databaseWriter.upsertImportedKnowledgeDocument(document)
                    result.changedDocumentCount += 1
                }
                result.succeededConnectorIDs.append(connector.instanceID)
            } catch {
                result.failedConnectorIDs.append(connector.instanceID)
            }
        }
        return result
    }
}
```

- [x] **Step 4: Run coordinator tests**

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/KnowledgeImportCoordinatorTests
```

Expected: tests pass.

- [x] **Step 5: Commit**

```bash
git add KnowYou/Services/Knowledge/KnowledgeImportConnector.swift KnowYou/Services/Knowledge/KnowledgeImportCoordinator.swift KnowYouTests/KnowledgeImportCoordinatorTests.swift KnowYou.xcodeproj/project.pbxproj
git commit -m "Add knowledge import coordinator"
```

---

### Task 5: Local Folder And Obsidian Import Connectors

**Status:** Completed in commits `1a36183` through `f1d89a6`. The final implementation adds local and Obsidian import connectors with canonical root/path handling, deterministic relative remote IDs, contextual read errors, case-insensitive KnowYou export marker detection, and Obsidian daily export directory loop prevention.

**Files:**
- Create: `KnowYou/Services/Knowledge/LocalFolderKnowledgeConnector.swift`
- Create: `KnowYou/Services/Knowledge/ObsidianKnowledgeConnector.swift`
- Test: `KnowYouTests/LocalFolderKnowledgeConnectorTests.swift`
- Test: `KnowYouTests/ObsidianKnowledgeConnectorTests.swift`
- Modify: `KnowYou.xcodeproj/project.pbxproj`

- [x] **Step 1: Write failing local folder tests**

```swift
import XCTest
@testable import KnowYou

final class LocalFolderKnowledgeConnectorTests: XCTestCase {
    func testScansMarkdownAndTextFilesOnly() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "# Alpha".write(to: root.appending(path: "alpha.md"), atomically: true, encoding: .utf8)
        try "Beta".write(to: root.appending(path: "beta.txt"), atomically: true, encoding: .utf8)
        try "PDF".write(to: root.appending(path: "gamma.pdf"), atomically: true, encoding: .utf8)

        let connector = LocalFolderKnowledgeConnector(instanceID: "local-main", rootURL: root)
        let snapshots = try await connector.snapshots()

        XCTAssertEqual(snapshots.map(\.title).sorted(), ["alpha", "beta"])
        XCTAssertEqual(Set(snapshots.map(\.mimeType)), ["text/markdown", "text/plain"])
    }
}
```

- [x] **Step 2: Write failing Obsidian loop-skip tests**

```swift
import XCTest
@testable import KnowYou

final class ObsidianKnowledgeConnectorTests: XCTestCase {
    func testSkipsKnowYouDailyMemoryExportDirectoryAndMarkers() async throws {
        let vault = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: vault) }
        let notes = vault.appending(path: "Notes", directoryHint: .isDirectory)
        let export = vault.appending(path: "KnowYou/Daily Memories", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: notes, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: export, withIntermediateDirectories: true)
        try "# Keep".write(to: notes.appending(path: "keep.md"), atomically: true, encoding: .utf8)
        try "---\nknowyou_export: daily_memory\n---\n# Skip Marker".write(to: notes.appending(path: "skip-marker.md"), atomically: true, encoding: .utf8)
        try "# Skip Export".write(to: export.appending(path: "2026-05-21.md"), atomically: true, encoding: .utf8)

        let connector = ObsidianKnowledgeConnector(instanceID: "obsidian-main", vaultURL: vault)
        let snapshots = try await connector.snapshots()

        XCTAssertEqual(snapshots.map(\.title), ["keep"])
    }
}
```

- [x] **Step 3: Run connector tests and verify failure**

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/LocalFolderKnowledgeConnectorTests -only-testing:KnowYouTests/ObsidianKnowledgeConnectorTests
```

Expected: compile fails because connector types do not exist.

- [x] **Step 4: Implement local folder connector**

Create `LocalFolderKnowledgeConnector.swift`:

```swift
import Foundation

struct LocalFolderKnowledgeConnector: KnowledgeImportConnector {
    let instanceID: String
    let connectorID: KnowledgeConnectorID = .localFolderImport
    let rootURL: URL
    let fileManager: FileManager

    init(instanceID: String, rootURL: URL, fileManager: FileManager = .default) {
        self.instanceID = instanceID
        self.rootURL = rootURL
        self.fileManager = fileManager
    }

    func snapshots() async throws -> [KnowledgeImportSnapshot] {
        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw KnowledgeImportConnectorError.unavailable("Local folder is unavailable: \(rootURL.path)")
        }

        var snapshots: [KnowledgeImportSnapshot] = []
        for case let fileURL as URL in enumerator {
            guard let mimeType = Self.supportedMimeType(for: fileURL) else { continue }
            guard shouldImport(fileURL: fileURL) else { continue }
            let markdown = try String(contentsOf: fileURL, encoding: .utf8)
            let relativePath = Self.relativePath(fileURL: fileURL, rootURL: rootURL)
            let values = try fileURL.resourceValues(forKeys: [.contentModificationDateKey])
            snapshots.append(KnowledgeImportSnapshot(
                connectorInstanceID: instanceID,
                connectorID: connectorID,
                remoteID: relativePath,
                title: fileURL.deletingPathExtension().lastPathComponent,
                sourcePath: fileURL.path,
                remoteURL: nil,
                mimeType: mimeType,
                markdown: markdown,
                remoteUpdatedAt: values.contentModificationDate,
                originKind: "local-file"
            ))
        }
        return snapshots.sorted { $0.remoteID < $1.remoteID }
    }

    func shouldImport(fileURL: URL) -> Bool {
        true
    }

    static func supportedMimeType(for url: URL) -> String? {
        switch url.pathExtension.lowercased() {
        case "md", "markdown": return "text/markdown"
        case "txt": return "text/plain"
        default: return nil
        }
    }

    static func relativePath(fileURL: URL, rootURL: URL) -> String {
        let rootPath = rootURL.standardizedFileURL.path
        let filePath = fileURL.standardizedFileURL.path
        guard filePath.hasPrefix(rootPath + "/") else { return fileURL.lastPathComponent }
        return String(filePath.dropFirst(rootPath.count + 1))
    }
}
```

- [x] **Step 5: Implement Obsidian connector**

Create `ObsidianKnowledgeConnector.swift`:

```swift
import Foundation

struct ObsidianKnowledgeConnector: KnowledgeImportConnector {
    let instanceID: String
    let connectorID: KnowledgeConnectorID = .obsidianImport
    let vaultURL: URL
    let fileManager: FileManager

    init(instanceID: String, vaultURL: URL, fileManager: FileManager = .default) {
        self.instanceID = instanceID
        self.vaultURL = vaultURL
        self.fileManager = fileManager
    }

    func snapshots() async throws -> [KnowledgeImportSnapshot] {
        let local = LocalFolderKnowledgeConnector(instanceID: instanceID, rootURL: vaultURL, fileManager: fileManager)
        return try await local.snapshots()
            .filter { snapshot in
                guard let sourcePath = snapshot.sourcePath else { return true }
                return shouldImport(fileURL: URL(fileURLWithPath: sourcePath))
            }
            .map { snapshot in
                KnowledgeImportSnapshot(
                    connectorInstanceID: snapshot.connectorInstanceID,
                    connectorID: connectorID,
                    remoteID: snapshot.remoteID,
                    title: snapshot.title,
                    sourcePath: snapshot.sourcePath,
                    remoteURL: snapshot.remoteURL,
                    mimeType: snapshot.mimeType,
                    markdown: snapshot.markdown,
                    remoteUpdatedAt: snapshot.remoteUpdatedAt,
                    originKind: "obsidian-vault"
                )
            }
    }

    func shouldImport(fileURL: URL) -> Bool {
        let standardized = fileURL.standardizedFileURL.path
        let exportRoot = vaultURL
            .appending(path: "KnowYou", directoryHint: .isDirectory)
            .appending(path: "Daily Memories", directoryHint: .isDirectory)
            .standardizedFileURL
            .path
        if standardized == exportRoot || standardized.hasPrefix(exportRoot + "/") {
            return false
        }
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return true
        }
        return !Self.hasKnowYouExportMarker(text)
    }

    static func hasKnowYouExportMarker(_ markdown: String) -> Bool {
        markdown.contains("knowyou_export: daily_memory")
            || markdown.contains("\"originKind\" : \"daily_memory_export\"")
            || markdown.contains("\"originKind\":\"daily_memory_export\"")
    }
}
```

- [x] **Step 6: Run connector tests**

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/LocalFolderKnowledgeConnectorTests -only-testing:KnowYouTests/ObsidianKnowledgeConnectorTests
```

Expected: tests pass.

- [x] **Step 7: Commit**

```bash
git add KnowYou/Services/Knowledge/LocalFolderKnowledgeConnector.swift KnowYou/Services/Knowledge/ObsidianKnowledgeConnector.swift KnowYouTests/LocalFolderKnowledgeConnectorTests.swift KnowYouTests/ObsidianKnowledgeConnectorTests.swift KnowYou.xcodeproj/project.pbxproj
git commit -m "Add local knowledge import connectors"
```

---

### Task 6: Daily Memory Export Markers

**Files:**
- Modify: `KnowYou/Services/SyncMemory/SyncMemoryCoordinator.swift`
- Test: `KnowYouTests/SyncMemoryCoordinatorTests.swift`

**Status:** Completed in commits `f1e34ae` through `68f9e5c`. Daily Memory export now writes a `knowyou_export: daily_memory` frontmatter marker idempotently, preserves and augments existing frontmatter, treats body-only marker text as normal content, and keeps Obsidian import loop-safe by skipping only exact KnowYou export paths, exact export frontmatter markers, or valid JSON sidecars.

- [x] **Step 1: Add failing export marker test**

Add to `SyncMemoryCoordinatorTests`:

```swift
func testSyncDiariesAddsKnowYouExportMarker() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let sourceVault = root.appendingPathComponent("source", isDirectory: true)
    let obsidianTarget = root.appendingPathComponent("obsidian/KnowYou/Daily Memories", isDirectory: true)
    try FileManager.default.createDirectory(at: sourceVault, withIntermediateDirectories: true)
    try "# Fresh".write(
        to: sourceVault.appendingPathComponent("2026-04-14.md"),
        atomically: true,
        encoding: .utf8
    )
    defer { try? FileManager.default.removeItem(at: root) }

    let coordinator = SyncMemoryCoordinator(fileManager: .default)
    _ = try coordinator.syncDiaries(sourceVault: sourceVault, destinations: [.obsidian: obsidianTarget])

    let synced = try String(contentsOf: obsidianTarget.appendingPathComponent("2026-04-14.md"), encoding: .utf8)
    XCTAssertTrue(synced.hasPrefix("---\nknowyou_export: daily_memory\n---\n"))
    XCTAssertTrue(synced.contains("# Fresh"))
}
```

- [x] **Step 2: Run sync memory tests and verify failure**

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/SyncMemoryCoordinatorTests
```

Expected: new marker test fails because copied files do not contain frontmatter.

- [x] **Step 3: Write marker during export**

In `SyncMemoryCoordinator`, replace direct `copyItem` with marker-aware write:

```swift
let destinationFile = directory.appendingPathComponent(diaryFile.lastPathComponent)
let markdown = try String(contentsOf: diaryFile, encoding: .utf8)
let exportMarkdown = Self.markedDailyMemoryExport(markdown)
try exportMarkdown.write(to: destinationFile, atomically: true, encoding: .utf8)
```

Add helper:

```swift
static func markedDailyMemoryExport(_ markdown: String) -> String {
    if markdown.hasPrefix("---\n"), markdown.contains("knowyou_export: daily_memory") {
        return markdown
    }
    return """
    ---
    knowyou_export: daily_memory
    ---
    \(markdown)
    """
}
```

Remove the old `removeItem` before copy branch; `String.write(..., atomically: true)` safely overwrites the destination file.

- [x] **Step 4: Update overwrite expectation**

In `testSyncDiariesOverwritesPreviouslySyncedFileWithSameName`, change expected content to:

```swift
"""
---
knowyou_export: daily_memory
---
# Fresh
"""
```

- [x] **Step 5: Run sync memory tests**

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/SyncMemoryCoordinatorTests
```

Expected: tests pass.

- [x] **Step 6: Commit**

```bash
git add KnowYou/Services/SyncMemory/SyncMemoryCoordinator.swift KnowYouTests/SyncMemoryCoordinatorTests.swift
git commit -m "Mark daily memory exports"
```

---

### Task 7: API Connector HTTP Clients

**Files:**
- Create: `KnowYou/Services/Knowledge/KnowledgeHTTPClient.swift`
- Create: `KnowYou/Services/Knowledge/FeishuKnowledgeConnector.swift`
- Create: `KnowYou/Services/Knowledge/NotionKnowledgeConnector.swift`
- Create: `KnowYou/Services/Knowledge/GoogleDriveKnowledgeConnector.swift`
- Test: `KnowYouTests/KnowledgeAPIConnectorTests.swift`
- Modify: `KnowYou.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write failing API connector tests**

```swift
import XCTest
@testable import KnowYou

final class KnowledgeAPIConnectorTests: XCTestCase {
    override func setUp() {
        super.setUp()
        KnowledgeAPIStubURLProtocol.reset()
    }

    func testFeishuFetchesMarkdownContentEndpoint() async throws {
        KnowledgeAPIStubURLProtocol.response = .success("""
        {"data":{"content":"# Feishu Doc","title":"Feishu Doc","url":"https://example.feishu.cn/docx/doc123"}}
        """)
        let client = KnowledgeHTTPClient(session: KnowledgeAPIStubURLProtocol.makeSession())
        let connector = FeishuKnowledgeConnector(instanceID: "feishu-main", documentID: "doc123", bearerToken: "token", client: client)

        let snapshots = try await connector.snapshots()

        XCTAssertEqual(snapshots.first?.markdown, "# Feishu Doc")
        XCTAssertEqual(KnowledgeAPIStubURLProtocol.lastRequest?.url?.path, "/open-apis/docs/v1/content")
    }

    func testNotionConvertsHeadingAndParagraphBlocksToMarkdown() async throws {
        KnowledgeAPIStubURLProtocol.responses = [
            .success("""
            {"object":"list","results":[{"object":"page","id":"page-1","last_edited_time":"2026-05-21T00:00:00.000Z","url":"https://notion.so/page-1","properties":{"title":{"title":[{"plain_text":"Page One"}]}}}],"next_cursor":null,"has_more":false}
            """),
            .success("""
            {"object":"list","results":[{"object":"block","id":"h1","type":"heading_1","heading_1":{"rich_text":[{"plain_text":"Title"}]},"has_children":false},{"object":"block","id":"p1","type":"paragraph","paragraph":{"rich_text":[{"plain_text":"Body"}]},"has_children":false}],"next_cursor":null,"has_more":false}
            """)
        ]
        let client = KnowledgeHTTPClient(session: KnowledgeAPIStubURLProtocol.makeSession())
        let connector = NotionKnowledgeConnector(instanceID: "notion-main", bearerToken: "token", client: client)

        let snapshots = try await connector.snapshots()

        XCTAssertEqual(snapshots.first?.markdown, "# Title\n\nBody")
    }

    func testGoogleDriveExportsGoogleDocAsMarkdown() async throws {
        KnowledgeAPIStubURLProtocol.responses = [
            .success("""
            {"files":[{"id":"file-1","name":"Doc One","mimeType":"application/vnd.google-apps.document","modifiedTime":"2026-05-21T00:00:00.000Z","webViewLink":"https://docs.google.com/document/d/file-1"}],"nextPageToken":null}
            """),
            .success("# Drive Doc")
        ]
        let client = KnowledgeHTTPClient(session: KnowledgeAPIStubURLProtocol.makeSession())
        let connector = GoogleDriveKnowledgeConnector(instanceID: "drive-main", bearerToken: "token", client: client)

        let snapshots = try await connector.snapshots()

        XCTAssertEqual(snapshots.first?.markdown, "# Drive Doc")
        XCTAssertEqual(KnowledgeAPIStubURLProtocol.requests.last?.url?.path, "/drive/v3/files/file-1/export")
    }
}
```

Add `KnowledgeAPIStubURLProtocol` in the same test file using the existing pattern from `CodexOAuthRefresherTests`: static `responses`, static `lastRequest`, `startLoading()`, and `makeSession()`.

- [ ] **Step 2: Run API tests and verify failure**

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/KnowledgeAPIConnectorTests
```

Expected: compile fails because API connector types do not exist.

- [ ] **Step 3: Implement HTTP client**

Create `KnowledgeHTTPClient.swift`:

```swift
import Foundation

struct KnowledgeHTTPClient: Sendable {
    let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func data(for request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw KnowledgeImportConnectorError.invalidResponse("Missing HTTP response.")
        }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 || http.statusCode == 403 {
                throw KnowledgeImportConnectorError.unauthorized("Knowledge connector authorization failed.")
            }
            throw KnowledgeImportConnectorError.unavailable("Knowledge connector request failed with HTTP \(http.statusCode).")
        }
        return data
    }

    static func bearerRequest(url: URL, token: String, method: String = "GET") -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }
}
```

- [ ] **Step 4: Implement Feishu connector**

Use `https://open.feishu.cn/open-apis/docs/v1/content?document_id=<id>` and parse `data.content`:

```swift
struct FeishuKnowledgeConnector: KnowledgeImportConnector {
    let instanceID: String
    let connectorID: KnowledgeConnectorID = .feishuImport
    let documentID: String
    let bearerToken: String
    let client: KnowledgeHTTPClient

    func snapshots() async throws -> [KnowledgeImportSnapshot] {
        var components = URLComponents(string: "https://open.feishu.cn/open-apis/docs/v1/content")!
        components.queryItems = [URLQueryItem(name: "document_id", value: documentID)]
        let data = try await client.data(for: KnowledgeHTTPClient.bearerRequest(url: components.url!, token: bearerToken))
        let decoded = try JSONDecoder().decode(FeishuContentResponse.self, from: data)
        return [KnowledgeImportSnapshot(
            connectorInstanceID: instanceID,
            connectorID: connectorID,
            remoteID: documentID,
            title: decoded.data.title ?? documentID,
            sourcePath: nil,
            remoteURL: decoded.data.url,
            mimeType: "text/markdown",
            markdown: decoded.data.content,
            remoteUpdatedAt: nil,
            originKind: "feishu-doc"
        )]
    }
}

private struct FeishuContentResponse: Decodable {
    struct Payload: Decodable {
        let content: String
        let title: String?
        let url: String?
    }
    let data: Payload
}
```

- [ ] **Step 5: Implement Notion connector**

Implement `POST https://api.notion.com/v1/search` and `GET https://api.notion.com/v1/blocks/{id}/children`, with `Notion-Version: 2026-03-11`. Convert `heading_1`, `heading_2`, `heading_3`, `paragraph`, `bulleted_list_item`, `numbered_list_item`, `to_do`, and `code` to Markdown. Unsupported blocks produce no line but do not fail the document.

- [ ] **Step 6: Implement Google Drive connector**

Implement `GET https://www.googleapis.com/drive/v3/files?q=trashed=false&fields=files(id,name,mimeType,modifiedTime,webViewLink),nextPageToken` and export Google Docs with:

```swift
https://www.googleapis.com/drive/v3/files/<fileID>/export?mimeType=text/markdown
```

For `text/markdown` and `text/plain` Drive files, call `GET https://www.googleapis.com/drive/v3/files/<fileID>?alt=media` and save bytes as UTF-8 text.

- [ ] **Step 7: Run API connector tests**

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/KnowledgeAPIConnectorTests
```

Expected: tests pass without real network calls.

- [ ] **Step 8: Commit**

```bash
git add KnowYou/Services/Knowledge/KnowledgeHTTPClient.swift KnowYou/Services/Knowledge/FeishuKnowledgeConnector.swift KnowYou/Services/Knowledge/NotionKnowledgeConnector.swift KnowYou/Services/Knowledge/GoogleDriveKnowledgeConnector.swift KnowYouTests/KnowledgeAPIConnectorTests.swift KnowYou.xcodeproj/project.pbxproj
git commit -m "Add API knowledge import connectors"
```

---

### Task 8: AppState Integration And Scheduling

**Files:**
- Modify: `KnowYou/App/AppEnvironment.swift`
- Modify: `KnowYou/App/AppState.swift`
- Modify: `KnowYou/Services/SyncMemory/LaunchAgentManager.swift`
- Test: `KnowYouTests/MainWindowViewModelTests.swift`
- Test: `KnowYouTests/LaunchAgentManagerTests.swift`

- [ ] **Step 1: Add failing AppState test**

Add to `MainWindowViewModelTests`:

```swift
func testImportKnowledgeNowRunsEnabledConnectorsWithoutChangingSyncMemoryExportConfig() async throws {
    let harness = try makeHarness()
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try "# Imported".write(to: root.appending(path: "imported.md"), atomically: true, encoding: .utf8)

    var importConfig = KnowledgeImportConfig.default
    importConfig.connectorInstances = [
        KnowledgeConnectorInstanceConfig(
            id: "local-main",
            connectorID: .localFolderImport,
            displayName: "Docs",
            sourcePath: root.path,
            isEnabled: true
        )
    ]
    harness.appState.saveKnowledgeImportConfig(importConfig)

    await harness.appState.importKnowledgeNow()

    XCTAssertTrue(harness.appState.knowledgeImportStatusMessage?.contains("Imported 1 document") == true)
    XCTAssertFalse(harness.appState.syncMemoryConfig.autoSyncEnabled)
}
```

- [ ] **Step 2: Add failing LaunchAgent test**

Add to `LaunchAgentManagerTests`:

```swift
func testKnowledgeImportRegistrationUsesSeparateArgument() throws {
    var commands: [[String]] = []
    let manager = LaunchAgentManager(
        fileManager: .default,
        label: "dev.knowyou.knowledge-import",
        homeDirectoryURL: temporaryHome,
        commandRunner: { commands.append($0) },
        userIDProvider: { 501 }
    )

    try manager.knowledgeImportRegistration(
        executablePath: "/Applications/KnowYou.app/Contents/MacOS/KnowYou",
        hour: 7,
        minute: 30,
        isEnabled: true
    )

    let plist = try String(contentsOf: manager.defaultPlistURL(), encoding: .utf8)
    XCTAssertTrue(plist.contains("--import-knowledge-now"))
    XCTAssertTrue(plist.contains("dev.knowyou.knowledge-import"))
    XCTAssertFalse(plist.contains("--sync-memory-now"))
    XCTAssertFalse(commands.isEmpty)
}
```

- [ ] **Step 3: Run targeted tests and verify failure**

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/MainWindowViewModelTests/testImportKnowledgeNowRunsEnabledConnectorsWithoutChangingSyncMemoryExportConfig -only-testing:KnowYouTests/LaunchAgentManagerTests/testKnowledgeImportRegistrationUsesSeparateArgument
```

Expected: compile fails because AppState and LaunchAgent methods do not exist.

- [ ] **Step 4: Add AppEnvironment knowledge directory**

In `AppEnvironment`, add:

```swift
var knowledgeSourcesDirectoryURL: URL {
    databaseURL.deletingLastPathComponent()
        .appending(path: "KnowledgeSources", directoryHint: .isDirectory)
}
```

- [ ] **Step 5: Add LaunchAgent registration method**

In `LaunchAgentManager`, add:

```swift
func knowledgeImportRegistration(
    executablePath: String?,
    hour: Int,
    minute: Int,
    isEnabled: Bool
) throws {
    try registration(
        executablePath: executablePath,
        hour: hour,
        minute: minute,
        isEnabled: isEnabled,
        launchArgument: "--import-knowledge-now",
        runAtLoad: true
    )
}
```

- [ ] **Step 6: Add AppState import state and actions**

Add AppState properties:

```swift
var knowledgeImportConfig: KnowledgeImportConfig
var knowledgeImportStatusMessage: String?
```

Initialize with:

```swift
self.knowledgeImportConfig = KnowledgeImportConfig.load(from: userDefaults)
```

Add methods:

```swift
func saveKnowledgeImportConfig(_ config: KnowledgeImportConfig) {
    knowledgeImportConfig = config
    knowledgeImportConfig.save(to: userDefaults)
    do {
        let manager = LaunchAgentManager(label: "dev.knowyou.knowledge-import")
        try manager.knowledgeImportRegistration(
            executablePath: Bundle.main.executableURL?.path,
            hour: config.dailyImportHour,
            minute: config.dailyImportMinute,
            isEnabled: config.isImportEnabled
        )
        setKnowledgeImportStatus(config.isImportEnabled ? "Knowledge import enabled" : "Knowledge import disabled")
    } catch {
        setKnowledgeImportStatus("Knowledge import setup failed: \(error.localizedDescription)")
    }
}

func importKnowledgeNow() async {
    guard let environment else {
        setKnowledgeImportStatus("Knowledge import unavailable")
        return
    }
    let connectors = makeKnowledgeImportConnectors(from: knowledgeImportConfig)
    guard connectors.isEmpty == false else {
        setKnowledgeImportStatus("No Knowledge Imports enabled")
        return
    }
    let coordinator = KnowledgeImportCoordinator(
        databaseWriter: environment.databaseWriter,
        store: KnowledgeImportStore(rootDirectory: environment.knowledgeSourcesDirectoryURL)
    )
    let result = await coordinator.sync(connectors: connectors)
    let noun = result.changedDocumentCount == 1 ? "document" : "documents"
    setKnowledgeImportStatus("Imported \(result.changedDocumentCount) \(noun)")
}

private func setKnowledgeImportStatus(_ message: String) {
    knowledgeImportStatusMessage = message
    statusMessage = message
}
```

Add connector factory initially for local and Obsidian configs:

```swift
private func makeKnowledgeImportConnectors(from config: KnowledgeImportConfig) -> [any KnowledgeImportConnector] {
    config.connectorInstances.compactMap { instance in
        guard instance.isEnabled else { return nil }
        switch instance.connectorID {
        case .localFolderImport:
            guard let path = instance.sourcePath else { return nil }
            return LocalFolderKnowledgeConnector(instanceID: instance.id, rootURL: URL(fileURLWithPath: path, isDirectory: true))
        case .obsidianImport:
            guard let path = instance.sourcePath else { return nil }
            return ObsidianKnowledgeConnector(instanceID: instance.id, vaultURL: URL(fileURLWithPath: path, isDirectory: true))
        case .feishuImport, .notionImport, .googleDriveImport:
            return nil
        case .obsidianExport, .openClawExport:
            return nil
        }
    }
}
```

- [ ] **Step 7: Wire API connector factory through credentials**

Extend the factory for API connectors:

```swift
let credentialStore = KnowledgeImportCredentialStore(keychain: keychain, service: keychainService)
```

Then add cases:

```swift
case .feishuImport:
    guard let token = credentialStore.bearerToken(connectorInstanceID: instance.id),
          let documentID = instance.sourcePath else { return nil }
    return FeishuKnowledgeConnector(instanceID: instance.id, documentID: documentID, bearerToken: token, client: KnowledgeHTTPClient())
case .notionImport:
    guard let token = credentialStore.bearerToken(connectorInstanceID: instance.id) else { return nil }
    return NotionKnowledgeConnector(instanceID: instance.id, bearerToken: token, client: KnowledgeHTTPClient())
case .googleDriveImport:
    guard let token = credentialStore.bearerToken(connectorInstanceID: instance.id) else { return nil }
    return GoogleDriveKnowledgeConnector(instanceID: instance.id, bearerToken: token, client: KnowledgeHTTPClient())
```

- [ ] **Step 8: Run targeted tests**

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/MainWindowViewModelTests/testImportKnowledgeNowRunsEnabledConnectorsWithoutChangingSyncMemoryExportConfig -only-testing:KnowYouTests/LaunchAgentManagerTests/testKnowledgeImportRegistrationUsesSeparateArgument
```

Expected: tests pass.

- [ ] **Step 9: Commit**

```bash
git add KnowYou/App/AppEnvironment.swift KnowYou/App/AppState.swift KnowYou/Services/SyncMemory/LaunchAgentManager.swift KnowYouTests/MainWindowViewModelTests.swift KnowYouTests/LaunchAgentManagerTests.swift
git commit -m "Wire knowledge imports into app state"
```

---

### Task 9: Connectors Panel Presentation

**Files:**
- Create: `KnowYou/UI/Settings/ConnectorsPanel.swift`
- Modify: `KnowYou/UI/MainWindowView.swift`
- Test: `KnowYouTests/ConnectorsPanelTests.swift`
- Modify: `KnowYou.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write failing presentation tests**

```swift
import XCTest
@testable import KnowYou

final class ConnectorsPanelTests: XCTestCase {
    func testPresentationSeparatesDailyExportAndKnowledgeImportRows() {
        let presentation = ConnectorsPanelPresentation(
            syncMemoryConfig: {
                var config = SyncMemoryConfig.default
                config.obsidian.isEnabled = true
                config.obsidian.resolvedPath = "/vault/KnowYou/Daily Memories"
                return config
            }(),
            knowledgeImportConfig: KnowledgeImportConfig(
                isImportEnabled: true,
                dailyImportHour: 7,
                dailyImportMinute: 30,
                connectorInstances: [
                    KnowledgeConnectorInstanceConfig(
                        id: "obsidian-main",
                        connectorID: .obsidianImport,
                        displayName: "Vault",
                        sourcePath: "/vault",
                        isEnabled: true
                    )
                ]
            ),
            syncMemoryStatusMessage: "Export ready",
            knowledgeImportStatusMessage: "Import ready"
        )

        XCTAssertEqual(presentation.exportRows.map(\.title), ["Obsidian Export", "OpenClaw Export"])
        XCTAssertEqual(presentation.importRows.map(\.title), ["Vault"])
        XCTAssertEqual(presentation.importRows.first?.direction, "Import")
        XCTAssertEqual(presentation.exportRows.first?.direction, "Export")
    }
}
```

- [ ] **Step 2: Run panel tests and verify failure**

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/ConnectorsPanelTests
```

Expected: compile fails because panel presentation does not exist.

- [ ] **Step 3: Implement presentation model**

Create `ConnectorsPanel.swift`:

```swift
import SwiftUI

struct ConnectorPanelRow: Equatable, Identifiable {
    var id: String
    var title: String
    var direction: String
    var status: String
    var detail: String
}

struct ConnectorsPanelPresentation: Equatable {
    var exportRows: [ConnectorPanelRow]
    var importRows: [ConnectorPanelRow]
    var syncMemoryStatusMessage: String?
    var knowledgeImportStatusMessage: String?

    init(
        syncMemoryConfig: SyncMemoryConfig,
        knowledgeImportConfig: KnowledgeImportConfig,
        syncMemoryStatusMessage: String?,
        knowledgeImportStatusMessage: String?
    ) {
        exportRows = [
            ConnectorPanelRow(
                id: "obsidian-export",
                title: "Obsidian Export",
                direction: "Export",
                status: syncMemoryConfig.obsidian.isEnabled ? "Ready" : "Disabled",
                detail: syncMemoryConfig.obsidian.resolvedPath ?? "Not connected"
            ),
            ConnectorPanelRow(
                id: "openclaw-export",
                title: "OpenClaw Export",
                direction: "Export",
                status: syncMemoryConfig.openClaw.isEnabled ? "Ready" : "Disabled",
                detail: syncMemoryConfig.openClaw.resolvedPath ?? "Not connected"
            ),
        ]
        importRows = knowledgeImportConfig.connectorInstances.map { instance in
            ConnectorPanelRow(
                id: instance.id,
                title: instance.displayName,
                direction: "Import",
                status: instance.isEnabled ? "Ready" : "Disabled",
                detail: instance.sourcePath ?? instance.accountID ?? "Not connected"
            )
        }
        self.syncMemoryStatusMessage = syncMemoryStatusMessage
        self.knowledgeImportStatusMessage = knowledgeImportStatusMessage
    }
}

struct ConnectorsPanel: View {
    let presentation: ConnectorsPanelPresentation
    let onExportNow: () -> Void
    let onImportNow: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Connectors")
                .font(.title3.weight(.semibold))
            connectorSection(title: "Daily Memory Export", rows: presentation.exportRows, actionTitle: "Export Now", action: onExportNow)
            connectorSection(title: "Knowledge Imports", rows: presentation.importRows, actionTitle: "Import Now", action: onImportNow)
            HStack {
                Spacer()
                Button("Close", action: onClose)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 520, minHeight: 420)
    }

    private func connectorSection(title: String, rows: [ConnectorPanelRow], actionTitle: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Button(actionTitle, action: action)
            }
            ForEach(rows) { row in
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(row.title).font(.body.weight(.semibold))
                        Text(row.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Spacer()
                    Text(row.direction).font(.caption.weight(.semibold))
                    Text(row.status).font(.caption)
                }
                .padding(10)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }
}
```

- [ ] **Step 4: Wire MainWindowView menu and panel state**

Replace the menu entry currently opening `SyncMemoryPanel` with a `Connectors` label, and present `ConnectorsPanel` using existing `isShowingSyncMemoryPanel` state or rename that state to `isShowingConnectorsPanel` in a single mechanical pass.

Use this presentation constructor:

```swift
ConnectorsPanelPresentation(
    syncMemoryConfig: appState.syncMemoryConfig,
    knowledgeImportConfig: appState.knowledgeImportConfig,
    syncMemoryStatusMessage: appState.syncMemoryStatusMessage,
    knowledgeImportStatusMessage: appState.knowledgeImportStatusMessage
)
```

Call:

```swift
onExportNow: { appState.syncMemoryNow() }
onImportNow: { Task { await appState.importKnowledgeNow() } }
```

- [ ] **Step 5: Run panel tests**

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/ConnectorsPanelTests
```

Expected: tests pass.

- [ ] **Step 6: Commit**

```bash
git add KnowYou/UI/Settings/ConnectorsPanel.swift KnowYou/UI/MainWindowView.swift KnowYouTests/ConnectorsPanelTests.swift KnowYou.xcodeproj/project.pbxproj
git commit -m "Add connectors panel presentation"
```

---

### Task 10: Documentation And Verification

**Files:**
- Modify: `docs/architecture.md`
- Modify: `docs/requirements-spec.md`

- [ ] **Step 1: Update architecture documentation**

In `docs/architecture.md`, update the system overview to describe six runtime layers:

```markdown
4. 连接器层：Daily Memory Export 单向导出、Knowledge Imports 单向导入、本地缓存、API 连接器、LaunchAgent 定时运行
```

Add a new section after the existing Sync Memory discussion:

```markdown
### Knowledge Imports

Knowledge Imports 与 Daily Memory Export 是两个方向相反的能力。Daily Memory Export 把 KnowYou 生成的每日日记复制到外部工具；Knowledge Imports 把用户选择的外部资料导入 KnowYou 本地缓存。

导入内容存放在 `Application Support/KnowYou/KnowledgeSources/`，每个文档写为 `content.md` 和 `metadata.json`，并在 SQLite 中记录 connector instance、remote identity、content hash、同步状态和 tombstone。Obsidian 导入默认跳过 `<vault>/KnowYou/Daily Memories/`，并跳过带有 `knowyou_export: daily_memory` marker 的文件，避免把 KnowYou 自己导出的日记再导入回来。
```

- [ ] **Step 2: Update requirements documentation**

In `docs/requirements-spec.md`, replace the current product boundary that says external knowledge-base sync is out of scope with:

```markdown
- 支持外部知识源到本地缓存的单向导入，但不支持双向外部知识库编辑
```

Add functional requirements:

```markdown
- 系统必须把 Knowledge Imports 和 Daily Memory Export 分开建模。
- Knowledge Imports 必须把导入内容保存到本地缓存，而不是依赖动态远端链接。
- Obsidian 导入必须默认跳过 `<vault>/KnowYou/Daily Memories/`。
- 导入器必须跳过带有 `knowyou_export: daily_memory` 的 KnowYou 导出文件。
- 单个导入连接器失败不得阻塞其他连接器。
- API 连接器凭据必须存放在 Keychain 或等价安全存储中。
```

- [ ] **Step 3: Run targeted test suite**

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/KnowledgeImportModelTests -only-testing:KnowYouTests/KnowledgeImportDatabaseTests -only-testing:KnowYouTests/KnowledgeImportStoreTests -only-testing:KnowYouTests/KnowledgeImportCoordinatorTests -only-testing:KnowYouTests/LocalFolderKnowledgeConnectorTests -only-testing:KnowYouTests/ObsidianKnowledgeConnectorTests -only-testing:KnowYouTests/KnowledgeAPIConnectorTests -only-testing:KnowYouTests/ConnectorsPanelTests -only-testing:KnowYouTests/SyncMemoryCoordinatorTests
```

Expected: targeted tests pass.

- [ ] **Step 4: Run full verification**

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS'
xcodebuild build -scheme KnowYou -destination 'platform=macOS'
```

Expected: both commands succeed. CoreSimulator warnings are acceptable for macOS destination if the command exits successfully.

- [ ] **Step 5: Review diff**

```bash
git diff --stat HEAD
git diff -- docs/architecture.md docs/requirements-spec.md
```

Expected: docs reflect one-way Knowledge Imports and no bidirectional editing claim.

- [ ] **Step 6: Commit**

```bash
git add docs/architecture.md docs/requirements-spec.md
git commit -m "Document knowledge import connectors"
```

---

## Plan Self-Review

- Spec coverage: covered local cache, SQLite index, local/Obsidian import, Feishu/Notion/Google Drive API boundaries, loop prevention, separate scheduling, UI separation, credentials in Keychain, tests, and documentation updates.
- Scope boundary: this plan implements one-way import and keeps external write-back out of scope.
- Type consistency: `KnowledgeConnectorID`, `KnowledgeImportConfig`, `KnowledgeImportSnapshot`, `ImportedKnowledgeDocument`, `KnowledgeImportCoordinator`, and `KnowledgeImportConnector` are introduced before use.
- Verification: targeted tests are run after each task; full `xcodebuild test` and `xcodebuild build` are required before completion.
