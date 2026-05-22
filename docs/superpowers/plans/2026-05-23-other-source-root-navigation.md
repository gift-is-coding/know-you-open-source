# Other Source Root Navigation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the user-facing root navigation where `Other Source` is always visible, newly added connectors appear beside `My Diary`, and connector entries open browsable synced content.

**Architecture:** Introduce a typed main-content selection model instead of treating every sidebar choice as a diary date. Keep connector management reusable by extracting the existing connectors sheet body into a content view that can render both in a sheet and as the `Other Source` page. Add a lightweight knowledge-source browser backed by existing `KnowledgeImportConfig` and `DatabaseWriter.fetchImportedKnowledgeDocuments(connectorInstanceID:)`.

**Tech Stack:** Swift 6, SwiftUI, Observation `@Observable`, XCTest, GRDB-backed `DatabaseWriter`, existing `KnowledgeImportStore`/`KnowledgeImportConfig`.

---

## File Map

- Modify: `KnowYou/UI/Sidebar/DateSidebarView.swift`
  - Rename its presentation responsibility from date-only to root navigation while keeping existing type names if that minimizes churn.
  - Add fixed root rows for `My Diary` and `Other Source`.
  - Add root connector rows from `KnowledgeImportConfig.connectorInstances`.
  - Add a `+` action on `Other Source`.

- Modify: `KnowYou/App/AppState.swift`
  - Add a typed `MainContentSelection` enum.
  - Track selected connector and selected imported document.
  - Add selection methods for diary root, other-source manager, connector, and imported document.
  - Add document-loading helpers backed by `environment.databaseWriter.fetchImportedKnowledgeDocuments`.

- Modify: `KnowYou/UI/MainWindowView.swift`
  - Pass connector config into sidebar.
  - Switch main content between diary reader, other-source manager, and connector content.
  - Route `Other Source +` into the connector management page with add form open.

- Modify: `KnowYou/UI/Settings/ConnectorsPanel.swift`
  - Extract reusable `ConnectorsManagementView` from the sheet content.
  - Keep `ConnectorsPanel` as a sheet wrapper with a close button.
  - Allow the management view to start with the API add form open when called from `Other Source +`.

- Create: `KnowYou/UI/Knowledge/KnowledgeSourceContentView.swift`
  - Show connector title, status, `Sync Now`, document list, selected Markdown content, and empty/error/disabled states.

- Modify: `KnowYouTests/DailyMarkdownViewTests.swift`
  - Add sidebar presentation tests for `My Diary`, `Other Source`, connector root rows, and add action metadata.

- Modify: `KnowYouTests/MainWindowViewModelTests.swift`
  - Add AppState selection tests for `Other Source`, connector selection, deletion cleanup, and knowledge document loading.

- Create: `KnowYouTests/KnowledgeSourceContentViewTests.swift`
  - Add presentation tests for connector content empty/list/selected/disabled states.

- Modify: `KnowYouTests/ConnectorsPanelTests.swift`
  - Add tests for reusable management presentation and add-mode state.

- Modify: `docs/architecture.md`
  - Document the new root navigation and selection model.

- Modify: `docs/requirements-spec.md`
  - Add user-facing requirements for `Other Source` root navigation.

---

## Task 1: Sidebar Root Presentation

**Files:**
- Modify: `KnowYou/UI/Sidebar/DateSidebarView.swift`
- Modify: `KnowYouTests/DailyMarkdownViewTests.swift`

- [ ] **Step 1: Write failing tests for fixed root rows and connector rows**

Add these tests to `DailyMarkdownViewTests` near the existing `DateSidebarPresentation` tests:

```swift
func testSidebarPresentationShowsDiaryAndOtherSourceRootsBeforeDates() {
    let presentation = DateSidebarPresentation(
        dates: ["2026-05-23", "2026-05-22"],
        selectedItemID: "diary:2026-05-23",
        knowledgeImportConfig: .default,
        today: makeDate(year: 2026, month: 5, day: 23),
        calendar: gregorianCalendar
    )

    XCTAssertEqual(presentation.rootItems.map(\.id), ["diary-root", "other-source"])
    XCTAssertEqual(presentation.rootItems.map(\.title), ["My Diary", "Other Source"])
    XCTAssertEqual(presentation.rootItems.map(\.systemImage), ["book.closed", "tray.full"])
    XCTAssertTrue(presentation.rootItems[1].showsAddButton)
    XCTAssertEqual(presentation.sections.first?.title, "May 2026")
    XCTAssertEqual(presentation.sections.first?.items.map(\.id), ["diary:2026-05-23", "diary:2026-05-22"])
}

func testSidebarPresentationAddsConnectorInstancesAsRootItems() {
    let config = KnowledgeImportConfig(
        isImportEnabled: true,
        dailyImportHour: 7,
        dailyImportMinute: 30,
        connectorInstances: [
            KnowledgeConnectorInstanceConfig(
                id: "feishu-main",
                connectorID: .feishuImport,
                displayName: "飞书文档",
                sourcePath: "doc-token",
                isEnabled: true
            ),
            KnowledgeConnectorInstanceConfig(
                id: "drive-main",
                connectorID: .googleDriveImport,
                displayName: "Google Drive",
                accountID: "me@example.com",
                isEnabled: false
            ),
        ]
    )

    let presentation = DateSidebarPresentation(
        dates: [],
        selectedItemID: "connector:feishu-main",
        knowledgeImportConfig: config,
        today: makeDate(year: 2026, month: 5, day: 23),
        calendar: gregorianCalendar
    )

    XCTAssertEqual(
        presentation.rootItems.map(\.id),
        ["diary-root", "other-source", "connector:feishu-main", "connector:drive-main"]
    )
    XCTAssertEqual(presentation.rootItems.map(\.title), ["My Diary", "Other Source", "飞书文档", "Google Drive"])
    XCTAssertEqual(presentation.rootItems.map(\.systemImage), ["book.closed", "tray.full", "doc.richtext", "externaldrive"])
    XCTAssertTrue(presentation.rootItems[2].isEnabled)
    XCTAssertFalse(presentation.rootItems[3].isEnabled)
}
```

- [ ] **Step 2: Run tests and verify RED**

Run:

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/DailyMarkdownViewTests
```

Expected: fails because `DateSidebarPresentation` does not accept `selectedItemID` or `knowledgeImportConfig`, and `rootItems` does not exist.

- [ ] **Step 3: Implement the presentation types**

In `DateSidebarView.swift`, add:

```swift
struct SidebarRootItem: Identifiable, Equatable {
    let id: String
    let title: String
    let systemImage: String
    let isSelected: Bool
    let isEnabled: Bool
    let showsAddButton: Bool
}
```

Change `DateSidebarPresentation` initializer to:

```swift
init(
    dates: [String],
    selectedItemID: String?,
    knowledgeImportConfig: KnowledgeImportConfig = .default,
    today: Date = Date(),
    calendar: Calendar = .current
) {
    rootItems = [
        SidebarRootItem(
            id: "diary-root",
            title: "My Diary",
            systemImage: "book.closed",
            isSelected: selectedItemID == "diary-root",
            isEnabled: true,
            showsAddButton: false
        ),
        SidebarRootItem(
            id: "other-source",
            title: "Other Source",
            systemImage: "tray.full",
            isSelected: selectedItemID == "other-source",
            isEnabled: true,
            showsAddButton: true
        ),
    ] + knowledgeImportConfig.connectorInstances.map { instance in
        SidebarRootItem(
            id: "connector:\(instance.id)",
            title: instance.displayName,
            systemImage: Self.systemImage(for: instance.connectorID),
            isSelected: selectedItemID == "connector:\(instance.id)",
            isEnabled: instance.isEnabled,
            showsAddButton: false
        )
    }

    // Keep existing month grouping, but prefix date item IDs with "diary:".
}
```

Add this helper:

```swift
private static func systemImage(for connectorID: KnowledgeConnectorID) -> String {
    switch connectorID {
    case .localFolderImport:
        return "folder"
    case .obsidianImport:
        return "square.stack.3d.up"
    case .feishuImport:
        return "doc.richtext"
    case .notionImport:
        return "doc.on.doc"
    case .googleDriveImport:
        return "externaldrive"
    case .obsidianExport, .openClawExport:
        return "arrow.up.doc"
    }
}
```

Update the existing date IDs in month sections:

```swift
DateSidebarItem(id: "diary:\(dayKey)", title: Self.formattedDay(dayKey))
```

For special items:

```swift
DateSidebarItem(id: "diary:\(dayKey)", title: Self.formattedDay(dayKey))
```

- [ ] **Step 4: Update existing sidebar tests to use the new initializer**

Change existing `DateSidebarPresentation(...)` test calls from:

```swift
DateSidebarPresentation(
    dates: ["2026-04-24", "2026-04-23", "2026-03-31", "demo-day"],
    selectedDate: nil,
    today: makeDate(year: 2026, month: 4, day: 24),
    calendar: gregorianCalendar
)
```

to:

```swift
DateSidebarPresentation(
    dates: ["2026-04-24", "2026-04-23", "2026-03-31", "demo-day"],
    selectedItemID: nil,
    knowledgeImportConfig: .default,
    today: makeDate(year: 2026, month: 4, day: 24),
    calendar: gregorianCalendar
)
```

Update expected date IDs in old tests from `["2026-04-24"]` to `["diary:2026-04-24"]`.

- [ ] **Step 5: Run tests and verify GREEN**

Run:

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/DailyMarkdownViewTests
```

Expected: tests pass.

- [ ] **Step 6: Commit**

```bash
git add KnowYou/UI/Sidebar/DateSidebarView.swift KnowYouTests/DailyMarkdownViewTests.swift
git commit -m "Add Other Source sidebar roots"
```

---

## Task 2: Typed Main Content Selection in AppState

**Files:**
- Modify: `KnowYou/App/AppState.swift`
- Modify: `KnowYouTests/MainWindowViewModelTests.swift`

- [ ] **Step 1: Write failing tests for selection routing**

Add tests near the existing `testAppStateCanToggleSyncMemoryPanelVisibility` test:

```swift
func testAppStateSelectsOtherSourceManagerWithoutChangingSelectedDiaryDate() {
    let suiteName = "MainWindowViewModelTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let appState = AppState(
        bootstrapServices: false,
        userDefaults: defaults,
        keychain: AppStateTestKeychainStore(),
        keychainService: "MainWindowViewModelTests"
    )
    appState.selectDate("2026-05-23")

    appState.selectOtherSourceManager(focusAddConnector: false)

    XCTAssertEqual(appState.mainContentSelection, .otherSourceManager(focusAddConnector: false))
    XCTAssertEqual(appState.selectedDate, "2026-05-23")
}

func testAppStateSelectsKnowledgeConnectorAndLoadsItsDocuments() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let vault = root.appendingPathComponent("Vault", isDirectory: true)
    let databaseURL = root.appendingPathComponent("events.sqlite")
    let contentURL = root.appendingPathComponent("content.md")
    let metadataURL = root.appendingPathComponent("metadata.json")
    try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let environment = try AppEnvironment(
        databasePath: databaseURL.path,
        vaultURL: vault,
        summarizer: nil
    )
    let suiteName = "MainWindowViewModelTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let appState = AppState(
        environment: environment,
        bootstrapServices: false,
        userDefaults: defaults,
        keychain: AppStateTestKeychainStore(),
        keychainService: "MainWindowViewModelTests"
    )
    let document = ImportedKnowledgeDocument(
        id: "doc-1",
        connectorInstanceID: "feishu-main",
        connectorID: .feishuImport,
        remoteID: "remote-1",
        title: "Project Plan",
        sourcePath: "doc-token",
        remoteURL: nil,
        mimeType: "text/markdown",
        contentHash: "hash",
        remoteUpdatedAt: nil,
        firstImportedAt: Date(timeIntervalSince1970: 1_778_000_000),
        lastSyncedAt: Date(timeIntervalSince1970: 1_778_000_100),
        deletedAt: nil,
        localContentPath: contentURL.path,
        localMetadataPath: metadataURL.path,
        normalizationVersion: 1,
        originKind: "feishu"
    )
    try "# Project Plan".write(toFile: document.localContentPath, atomically: true, encoding: .utf8)
    try fixture.environment.databaseWriter.upsertImportedKnowledgeDocument(document)

    appState.selectKnowledgeConnector(instanceID: "feishu-main")

    XCTAssertEqual(appState.mainContentSelection, .knowledgeConnector(instanceID: "feishu-main"))
    XCTAssertEqual(appState.selectedKnowledgeDocuments.map(\.title), ["Project Plan"])
    XCTAssertEqual(appState.selectedKnowledgeDocumentMarkdown, "# Project Plan")
}
```

- [ ] **Step 2: Run tests and verify RED**

Run:

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/MainWindowViewModelTests/testAppStateSelectsOtherSourceManagerWithoutChangingSelectedDiaryDate -only-testing:KnowYouTests/MainWindowViewModelTests/testAppStateSelectsKnowledgeConnectorAndLoadsItsDocuments
```

Expected: fails because `mainContentSelection`, `selectOtherSourceManager`, `selectKnowledgeConnector`, `selectedKnowledgeDocuments`, and `selectedKnowledgeDocumentMarkdown` do not exist.

- [ ] **Step 3: Add selection model and properties**

In `AppState.swift`, near `ReaderFocusZone` or the other app presentation enums, add:

```swift
enum MainContentSelection: Equatable {
    case diary(dayKey: String?)
    case otherSourceManager(focusAddConnector: Bool)
    case knowledgeConnector(instanceID: String)
    case knowledgeDocument(connectorInstanceID: String, documentID: String)
}
```

In `AppState`, add:

```swift
var mainContentSelection: MainContentSelection = .diary(dayKey: nil)
var selectedKnowledgeDocuments: [ImportedKnowledgeDocument] = []
var selectedKnowledgeDocument: ImportedKnowledgeDocument?
var selectedKnowledgeDocumentMarkdown: String?
```

- [ ] **Step 4: Update diary selection methods**

At the start of `selectDate(_:)`, set the typed selection:

```swift
mainContentSelection = .diary(dayKey: date)
```

When the app initializes with no selected date, keep `.diary(dayKey: nil)`.

- [ ] **Step 5: Add Other Source and connector selection methods**

Add methods in `AppState`:

```swift
func selectOtherSourceManager(focusAddConnector: Bool) {
    mainContentSelection = .otherSourceManager(focusAddConnector: focusAddConnector)
    readerFocus = .dateList
}

func selectKnowledgeConnector(instanceID: String) {
    mainContentSelection = .knowledgeConnector(instanceID: instanceID)
    readerFocus = .dateList
    reloadKnowledgeDocuments(connectorInstanceID: instanceID)
}

func selectKnowledgeDocument(connectorInstanceID: String, documentID: String) {
    mainContentSelection = .knowledgeDocument(
        connectorInstanceID: connectorInstanceID,
        documentID: documentID
    )
    reloadKnowledgeDocuments(connectorInstanceID: connectorInstanceID)
    selectedKnowledgeDocument = selectedKnowledgeDocuments.first { $0.id == documentID }
    selectedKnowledgeDocumentMarkdown = loadKnowledgeDocumentMarkdown(selectedKnowledgeDocument)
}
```

Add helpers:

```swift
private func reloadKnowledgeDocuments(connectorInstanceID: String) {
    guard let environment else {
        selectedKnowledgeDocuments = []
        selectedKnowledgeDocument = nil
        selectedKnowledgeDocumentMarkdown = nil
        return
    }

    selectedKnowledgeDocuments =
        (try? environment.databaseWriter.fetchImportedKnowledgeDocuments(
            connectorInstanceID: connectorInstanceID
        )) ?? []
    selectedKnowledgeDocument = selectedKnowledgeDocuments.first
    selectedKnowledgeDocumentMarkdown = loadKnowledgeDocumentMarkdown(selectedKnowledgeDocument)
}

private func loadKnowledgeDocumentMarkdown(_ document: ImportedKnowledgeDocument?) -> String? {
    guard let document else { return nil }
    return try? String(contentsOfFile: document.localContentPath, encoding: .utf8)
}
```

- [ ] **Step 6: Clear deleted connector selection**

In `deleteKnowledgeImportConnector(id:)` in `MainWindowView.swift` or after moving it into `AppState`, ensure AppState exposes a cleanup method. Preferred AppState method:

```swift
func didDeleteKnowledgeConnector(instanceID: String) {
    switch mainContentSelection {
    case .knowledgeConnector(let selectedID) where selectedID == instanceID,
         .knowledgeDocument(let selectedID, _) where selectedID == instanceID:
        selectOtherSourceManager(focusAddConnector: false)
    default:
        break
    }
}
```

Call it after saving the config in the delete handler.

- [ ] **Step 7: Run tests and verify GREEN**

Run:

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/MainWindowViewModelTests/testAppStateSelectsOtherSourceManagerWithoutChangingSelectedDiaryDate -only-testing:KnowYouTests/MainWindowViewModelTests/testAppStateSelectsKnowledgeConnectorAndLoadsItsDocuments
```

Expected: tests pass.

- [ ] **Step 8: Commit**

```bash
git add KnowYou/App/AppState.swift KnowYouTests/MainWindowViewModelTests.swift
git commit -m "Add typed main content selection"
```

---

## Task 3: Sidebar View Interaction Wiring

**Files:**
- Modify: `KnowYou/UI/Sidebar/DateSidebarView.swift`
- Modify: `KnowYou/UI/MainWindowView.swift`
- Modify: `KnowYouTests/DailyMarkdownViewTests.swift`

- [ ] **Step 1: Write failing test for sidebar item actions in presentation**

Add:

```swift
func testSidebarPresentationMarksOtherSourceAddAction() {
    let presentation = DateSidebarPresentation(
        dates: [],
        selectedItemID: "other-source",
        knowledgeImportConfig: .default,
        today: makeDate(year: 2026, month: 5, day: 23),
        calendar: gregorianCalendar
    )

    let otherSource = try XCTUnwrap(presentation.rootItems.first { $0.id == "other-source" })
    XCTAssertTrue(otherSource.showsAddButton)
    XCTAssertTrue(otherSource.isSelected)
}
```

- [ ] **Step 2: Run tests and verify RED or existing GREEN**

Run:

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/DailyMarkdownViewTests/testSidebarPresentationMarksOtherSourceAddAction
```

Expected: pass if Task 1 already implemented `showsAddButton`; if it fails, the failure should be about missing or incorrect presentation metadata.

- [ ] **Step 3: Update `DateSidebarView` public API**

Change its initializer properties:

```swift
let dates: [String]
let selectedItemID: String?
let knowledgeImportConfig: KnowledgeImportConfig
let isActive: Bool
let onSelectDiaryDate: (String) -> Void
let onSelectOtherSource: (_ focusAddConnector: Bool) -> Void
let onSelectKnowledgeConnector: (String) -> Void
```

Keep `onOpenSyncMemory` only if it is still needed by the bottom gear menu. The main `Other Source` row should not use the gear menu.

- [ ] **Step 4: Render root rows above date sections**

Inside the `List`, render:

```swift
ForEach(presentation.rootItems) { item in
    HStack(spacing: 8) {
        Label(item.title, systemImage: item.systemImage)
            .foregroundStyle(item.isEnabled ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
        Spacer()
        if item.showsAddButton {
            Button {
                onSelectOtherSource(true)
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .help("Add Other Source")
        }
    }
    .padding(.vertical, 4)
    .fontWeight(item.isSelected ? .semibold : .regular)
    .contentShape(Rectangle())
    .onTapGesture {
        selectRootItem(item)
    }
}
```

Add:

```swift
private func selectRootItem(_ item: SidebarRootItem) {
    if item.id == "diary-root" {
        if let selectedDate {
            onSelectDiaryDate(selectedDate)
        }
    } else if item.id == "other-source" {
        onSelectOtherSource(false)
    } else if item.id.hasPrefix("connector:") {
        onSelectKnowledgeConnector(String(item.id.dropFirst("connector:".count)))
    }
}
```

- [ ] **Step 5: Update date row selection**

Change `dateRow` to call the diary selection with the raw date:

```swift
private func dateRow(_ item: DateSidebarItem) -> some View {
    let dayKey = item.id.replacingOccurrences(of: "diary:", with: "")
    let isSelected = selectedItemID == item.id
    return Label(item.title, systemImage: "doc.plaintext")
        .padding(.vertical, 4)
        .fontWeight(isSelected ? .semibold : .regular)
        .foregroundStyle(isActive || isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
        .tag(item.id)
        .onTapGesture {
            onSelectDiaryDate(dayKey)
        }
}
```

- [ ] **Step 6: Wire MainWindowView**

Create a computed selected sidebar ID:

```swift
private var selectedSidebarItemID: String? {
    switch appState.mainContentSelection {
    case .diary(let dayKey):
        return dayKey.map { "diary:\($0)" } ?? "diary-root"
    case .otherSourceManager:
        return "other-source"
    case .knowledgeConnector(let instanceID):
        return "connector:\(instanceID)"
    case .knowledgeDocument(let instanceID, _):
        return "connector:\(instanceID)"
    }
}
```

Update `DateSidebarView` call:

```swift
DateSidebarView(
    dates: appState.availableDates,
    selectedDate: appState.selectedDate,
    selectedItemID: selectedSidebarItemID,
    knowledgeImportConfig: appState.knowledgeImportConfig,
    isActive: appState.readerFocus == .dateList,
    onSelectDiaryDate: appState.selectDate,
    onSelectOtherSource: appState.selectOtherSourceManager,
    onSelectKnowledgeConnector: appState.selectKnowledgeConnector,
    onOpenSyncMemory: openSyncMemoryPanel
)
```

- [ ] **Step 7: Run focused tests**

Run:

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/DailyMarkdownViewTests
```

Expected: tests pass.

- [ ] **Step 8: Commit**

```bash
git add KnowYou/UI/Sidebar/DateSidebarView.swift KnowYou/UI/MainWindowView.swift KnowYouTests/DailyMarkdownViewTests.swift
git commit -m "Wire Other Source sidebar interactions"
```

---

## Task 4: Reusable Other Source Management Page

**Files:**
- Modify: `KnowYou/UI/Settings/ConnectorsPanel.swift`
- Modify: `KnowYou/UI/MainWindowView.swift`
- Modify: `KnowYouTests/ConnectorsPanelTests.swift`

- [ ] **Step 1: Write failing presentation test for add mode**

Add:

```swift
func testConnectorsManagementPresentationCanStartInAddAPIFormMode() {
    let presentation = ConnectorsManagementPresentation(
        panelPresentation: ConnectorsPanelPresentation(
            syncMemoryConfig: .default,
            knowledgeImportConfig: .default,
            syncMemoryStatusMessage: nil,
            knowledgeImportStatusMessage: nil
        ),
        startsWithAddAPIForm: true
    )

    XCTAssertTrue(presentation.startsWithAddAPIForm)
    XCTAssertEqual(presentation.panelPresentation.importRows, [])
}
```

- [ ] **Step 2: Run test and verify RED**

Run:

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/ConnectorsPanelTests/testConnectorsManagementPresentationCanStartInAddAPIFormMode
```

Expected: fails because `ConnectorsManagementPresentation` does not exist.

- [ ] **Step 3: Extract management presentation and view**

In `ConnectorsPanel.swift`, add:

```swift
struct ConnectorsManagementPresentation: Equatable {
    var panelPresentation: ConnectorsPanelPresentation
    var startsWithAddAPIForm: Bool
}
```

Extract the current `ConnectorsPanel` body content into:

```swift
struct ConnectorsManagementView: View {
    let managementPresentation: ConnectorsManagementPresentation
    @Binding var isAutoImportEnabled: Bool
    @Binding var dailyImportTime: Date
    let onChooseObsidianExport: () -> Void
    let onChooseOpenClawExport: () -> Void
    let onOpenObsidianExport: () -> Void
    let onOpenOpenClawExport: () -> Void
    let onAddLocalFolderImport: () -> Void
    let onAddObsidianImport: () -> Void
    let onAddAPIImportConnector: (KnowledgeConnectorID, String, String?, String?, String) -> Void
    let onSetImportConnectorEnabled: (String, Bool) -> Void
    let onDeleteImportConnector: (String) -> Void
    let onExportNow: () -> Void
    let onImportNow: () -> Void

    @State private var isShowingAPIConnectorForm: Bool

    init(
        managementPresentation: ConnectorsManagementPresentation,
        isAutoImportEnabled: Binding<Bool>,
        dailyImportTime: Binding<Date>,
        onChooseObsidianExport: @escaping () -> Void,
        onChooseOpenClawExport: @escaping () -> Void,
        onOpenObsidianExport: @escaping () -> Void,
        onOpenOpenClawExport: @escaping () -> Void,
        onAddLocalFolderImport: @escaping () -> Void,
        onAddObsidianImport: @escaping () -> Void,
        onAddAPIImportConnector: @escaping (KnowledgeConnectorID, String, String?, String?, String) -> Void,
        onSetImportConnectorEnabled: @escaping (String, Bool) -> Void,
        onDeleteImportConnector: @escaping (String) -> Void,
        onExportNow: @escaping () -> Void,
        onImportNow: @escaping () -> Void
    ) {
        self.managementPresentation = managementPresentation
        self._isAutoImportEnabled = isAutoImportEnabled
        self._dailyImportTime = dailyImportTime
        self.onChooseObsidianExport = onChooseObsidianExport
        self.onChooseOpenClawExport = onChooseOpenClawExport
        self.onOpenObsidianExport = onOpenObsidianExport
        self.onOpenOpenClawExport = onOpenOpenClawExport
        self.onAddLocalFolderImport = onAddLocalFolderImport
        self.onAddObsidianImport = onAddObsidianImport
        self.onAddAPIImportConnector = onAddAPIImportConnector
        self.onSetImportConnectorEnabled = onSetImportConnectorEnabled
        self.onDeleteImportConnector = onDeleteImportConnector
        self.onExportNow = onExportNow
        self.onImportNow = onImportNow
        self._isShowingAPIConnectorForm = State(initialValue: managementPresentation.startsWithAddAPIForm)
    }
}
```

Move the section rendering helpers into `ConnectorsManagementView`.

- [ ] **Step 4: Keep ConnectorsPanel as sheet wrapper**

Make `ConnectorsPanel` render:

```swift
VStack(alignment: .leading, spacing: 18) {
    ConnectorsManagementView(
        managementPresentation: ConnectorsManagementPresentation(
            panelPresentation: presentation,
            startsWithAddAPIForm: false
        ),
        isAutoImportEnabled: $isAutoImportEnabled,
        dailyImportTime: $dailyImportTime,
        onChooseObsidianExport: onChooseObsidianExport,
        onChooseOpenClawExport: onChooseOpenClawExport,
        onOpenObsidianExport: onOpenObsidianExport,
        onOpenOpenClawExport: onOpenOpenClawExport,
        onAddLocalFolderImport: onAddLocalFolderImport,
        onAddObsidianImport: onAddObsidianImport,
        onAddAPIImportConnector: onAddAPIImportConnector,
        onSetImportConnectorEnabled: onSetImportConnectorEnabled,
        onDeleteImportConnector: onDeleteImportConnector,
        onExportNow: onExportNow,
        onImportNow: onImportNow
    )

    HStack {
        Spacer()
        Button("Close", action: onClose)
            .keyboardShortcut(.cancelAction)
    }
}
.padding(20)
.frame(width: 560)
```

- [ ] **Step 5: Render management page from MainWindowView**

Add a helper in `MainWindowView`:

```swift
private func connectorsManagementView(focusAddConnector: Bool) -> some View {
    ScrollView {
        ConnectorsManagementView(
            managementPresentation: ConnectorsManagementPresentation(
                panelPresentation: ConnectorsPanelPresentation(
                    syncMemoryConfig: appState.syncMemoryConfig,
                    knowledgeImportConfig: appState.knowledgeImportConfig,
                    syncMemoryStatusMessage: appState.syncMemoryStatusMessage,
                    knowledgeImportStatusMessage: appState.knowledgeImportStatusMessage
                ),
                startsWithAddAPIForm: focusAddConnector
            ),
            isAutoImportEnabled: knowledgeImportEnabledBinding,
            dailyImportTime: knowledgeImportTimeBinding,
            onChooseObsidianExport: { chooseSyncMemoryFolder(for: .obsidian) },
            onChooseOpenClawExport: { chooseSyncMemoryFolder(for: .openClaw) },
            onOpenObsidianExport: { openSyncMemoryFolder(at: appState.syncMemoryConfig.obsidian.resolvedPath) },
            onOpenOpenClawExport: { openSyncMemoryFolder(at: appState.syncMemoryConfig.openClaw.resolvedPath) },
            onAddLocalFolderImport: { chooseKnowledgeImportFolder(for: .localFolderImport) },
            onAddObsidianImport: { chooseKnowledgeImportFolder(for: .obsidianImport) },
            onAddAPIImportConnector: addAPIKnowledgeImportConnector,
            onSetImportConnectorEnabled: setKnowledgeImportConnectorEnabled,
            onDeleteImportConnector: deleteKnowledgeImportConnector,
            onExportNow: appState.syncMemoryNow,
            onImportNow: {
                Task { @MainActor in
                    await appState.importKnowledgeNow()
                }
            }
        )
        .padding(24)
        .frame(maxWidth: 720, alignment: .leading)
    }
}
```

Extract the repeated bindings into computed vars:

```swift
private var knowledgeImportEnabledBinding: Binding<Bool> {
    Binding(
        get: { appState.knowledgeImportConfig.isImportEnabled },
        set: { isEnabled in
            var config = appState.knowledgeImportConfig
            config.isImportEnabled = isEnabled
            appState.saveKnowledgeImportConfig(config)
        }
    )
}

private var knowledgeImportTimeBinding: Binding<Date> {
    Binding(
        get: {
            var components = DateComponents()
            components.hour = appState.knowledgeImportConfig.dailyImportHour
            components.minute = appState.knowledgeImportConfig.dailyImportMinute
            return Calendar.current.date(from: components) ?? Date()
        },
        set: { date in
            let components = Calendar.current.dateComponents([.hour, .minute], from: date)
            var config = appState.knowledgeImportConfig
            config.dailyImportHour = components.hour ?? 7
            config.dailyImportMinute = components.minute ?? 30
            appState.saveKnowledgeImportConfig(config)
        }
    )
}
```

- [ ] **Step 6: Run tests and build**

Run:

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/ConnectorsPanelTests
xcodebuild build -scheme KnowYou -destination 'platform=macOS'
```

Expected: tests and build pass.

- [ ] **Step 7: Commit**

```bash
git add KnowYou/UI/Settings/ConnectorsPanel.swift KnowYou/UI/MainWindowView.swift KnowYouTests/ConnectorsPanelTests.swift
git commit -m "Extract Other Source management view"
```

---

## Task 5: Knowledge Source Content Presentation and View

**Files:**
- Create: `KnowYou/UI/Knowledge/KnowledgeSourceContentView.swift`
- Create: `KnowYouTests/KnowledgeSourceContentViewTests.swift`
- Modify: `KnowYou.xcodeproj/project.pbxproj` if this project does not use synchronized file groups for new Swift files.

- [ ] **Step 1: Write failing presentation tests**

Create `KnowYouTests/KnowledgeSourceContentViewTests.swift`:

```swift
import XCTest
@testable import KnowYou

final class KnowledgeSourceContentViewTests: XCTestCase {
    func testPresentationShowsEmptyStateWhenConnectorHasNoDocuments() {
        let connector = KnowledgeConnectorInstanceConfig(
            id: "feishu-main",
            connectorID: .feishuImport,
            displayName: "飞书文档",
            sourcePath: "doc-token",
            isEnabled: true
        )

        let presentation = KnowledgeSourceContentPresentation(
            connector: connector,
            documents: [],
            selectedDocumentID: nil,
            selectedMarkdown: nil,
            statusMessage: nil
        )

        XCTAssertEqual(presentation.title, "飞书文档")
        XCTAssertEqual(presentation.state, .empty)
        XCTAssertEqual(presentation.emptyTitle, "No documents yet")
        XCTAssertTrue(presentation.showsSyncNow)
    }

    func testPresentationShowsSelectedDocumentMarkdown() {
        let connector = KnowledgeConnectorInstanceConfig(
            id: "feishu-main",
            connectorID: .feishuImport,
            displayName: "飞书文档",
            sourcePath: "doc-token",
            isEnabled: true
        )
        let document = ImportedKnowledgeDocument(
            id: "doc-1",
            connectorInstanceID: "feishu-main",
            connectorID: .feishuImport,
            remoteID: "remote-1",
            title: "Project Plan",
            sourcePath: nil,
            remoteURL: nil,
            mimeType: "text/markdown",
            contentHash: "hash",
            remoteUpdatedAt: nil,
            firstImportedAt: Date(timeIntervalSince1970: 1_778_000_000),
            lastSyncedAt: Date(timeIntervalSince1970: 1_778_000_100),
            deletedAt: nil,
            localContentPath: "/tmp/content.md",
            localMetadataPath: "/tmp/metadata.json",
            normalizationVersion: 1,
            originKind: "feishu"
        )

        let presentation = KnowledgeSourceContentPresentation(
            connector: connector,
            documents: [document],
            selectedDocumentID: "doc-1",
            selectedMarkdown: "# Project Plan",
            statusMessage: "Imported 1 document"
        )

        XCTAssertEqual(presentation.state, .documents)
        XCTAssertEqual(presentation.documentRows.map(\.title), ["Project Plan"])
        XCTAssertEqual(presentation.documentRows.first?.isSelected, true)
        XCTAssertEqual(presentation.markdown, "# Project Plan")
        XCTAssertEqual(presentation.statusMessage, "Imported 1 document")
    }

    func testPresentationShowsDisabledStateForDisabledConnector() {
        let connector = KnowledgeConnectorInstanceConfig(
            id: "drive-main",
            connectorID: .googleDriveImport,
            displayName: "Google Drive",
            accountID: "me@example.com",
            isEnabled: false
        )

        let presentation = KnowledgeSourceContentPresentation(
            connector: connector,
            documents: [],
            selectedDocumentID: nil,
            selectedMarkdown: nil,
            statusMessage: nil
        )

        XCTAssertEqual(presentation.state, .disabled)
        XCTAssertEqual(presentation.emptyTitle, "Connector disabled")
        XCTAssertFalse(presentation.showsSyncNow)
    }
}
```

- [ ] **Step 2: Run tests and verify RED**

Run:

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/KnowledgeSourceContentViewTests
```

Expected: fails because the new production types do not exist.

- [ ] **Step 3: Create presentation models**

Create `KnowledgeSourceContentView.swift`:

```swift
import SwiftUI

struct KnowledgeSourceContentPresentation: Equatable {
    enum State: Equatable {
        case disabled
        case empty
        case documents
    }

    struct DocumentRow: Identifiable, Equatable {
        let id: String
        let title: String
        let subtitle: String
        let isSelected: Bool
    }

    let title: String
    let state: State
    let emptyTitle: String
    let showsSyncNow: Bool
    let documentRows: [DocumentRow]
    let markdown: String?
    let statusMessage: String?

    init(
        connector: KnowledgeConnectorInstanceConfig,
        documents: [ImportedKnowledgeDocument],
        selectedDocumentID: String?,
        selectedMarkdown: String?,
        statusMessage: String?
    ) {
        title = connector.displayName
        self.statusMessage = statusMessage
        if !connector.isEnabled {
            state = .disabled
            emptyTitle = "Connector disabled"
            showsSyncNow = false
        } else if documents.isEmpty {
            state = .empty
            emptyTitle = "No documents yet"
            showsSyncNow = true
        } else {
            state = .documents
            emptyTitle = ""
            showsSyncNow = true
        }
        documentRows = documents.map { document in
            DocumentRow(
                id: document.id,
                title: document.title,
                subtitle: document.sourcePath ?? document.remoteURL ?? document.mimeType,
                isSelected: document.id == selectedDocumentID
            )
        }
        markdown = selectedMarkdown
    }
}
```

- [ ] **Step 4: Create SwiftUI view**

In the same file, add:

```swift
struct KnowledgeSourceContentView: View {
    let presentation: KnowledgeSourceContentPresentation
    let onSyncNow: () -> Void
    let onSelectDocument: (String) -> Void
    let onConfigure: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if let statusMessage = presentation.statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            switch presentation.state {
            case .disabled, .empty:
                emptyState
            case .documents:
                documentBrowser
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack {
            Text(presentation.title)
                .font(.title2.weight(.semibold))
            Spacer()
            if presentation.showsSyncNow {
                Button("Sync Now", action: onSyncNow)
            }
            Button("Configure", action: onConfigure)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(presentation.emptyTitle)
                .font(.headline)
            Text("Synced documents are stored locally in KnowYou. Source files are not modified.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var documentBrowser: some View {
        HStack(alignment: .top, spacing: 16) {
            List(presentation.documentRows) { row in
                VStack(alignment: .leading, spacing: 4) {
                    Text(row.title)
                        .fontWeight(row.isSelected ? .semibold : .regular)
                    Text(row.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    onSelectDocument(row.id)
                }
            }
            .frame(minWidth: 260, idealWidth: 320)

            ScrollView {
                Text(presentation.markdown ?? "")
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}
```

- [ ] **Step 5: Add file to Xcode project if needed**

Run:

```bash
xcodebuild build -scheme KnowYou -destination 'platform=macOS'
```

If build fails because the new Swift file is not in the target, add it to `KnowYou.xcodeproj/project.pbxproj` in the same target membership pattern used by files under `KnowYou/UI/Settings/`.

- [ ] **Step 6: Run tests and verify GREEN**

Run:

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/KnowledgeSourceContentViewTests
```

Expected: tests pass.

- [ ] **Step 7: Commit**

```bash
git add KnowYou/UI/Knowledge/KnowledgeSourceContentView.swift KnowYouTests/KnowledgeSourceContentViewTests.swift KnowYou.xcodeproj/project.pbxproj
git commit -m "Add knowledge source content view"
```

---

## Task 6: MainWindow Content Switching

**Files:**
- Modify: `KnowYou/UI/MainWindowView.swift`
- Modify: `KnowYou/App/AppState.swift`
- Modify: `KnowYouTests/MainWindowViewModelTests.swift`

- [ ] **Step 1: Write failing test for connector deletion routing**

Add:

```swift
func testDeletingSelectedKnowledgeConnectorReturnsToOtherSourceManager() {
    let suiteName = "MainWindowViewModelTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let appState = AppState(
        bootstrapServices: false,
        userDefaults: defaults,
        keychain: AppStateTestKeychainStore(),
        keychainService: "MainWindowViewModelTests"
    )
    appState.selectKnowledgeConnector(instanceID: "feishu-main")

    appState.didDeleteKnowledgeConnector(instanceID: "feishu-main")

    XCTAssertEqual(appState.mainContentSelection, .otherSourceManager(focusAddConnector: false))
}
```

- [ ] **Step 2: Run test and verify RED**

Run:

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/MainWindowViewModelTests/testDeletingSelectedKnowledgeConnectorReturnsToOtherSourceManager
```

Expected: fails if `didDeleteKnowledgeConnector` is not implemented or not wired.

- [ ] **Step 3: Switch MainWindow content area**

Replace the current fixed `DailyMarkdownView` content closure with:

```swift
Group {
    switch appState.mainContentSelection {
    case .diary:
        diaryReaderView
    case .otherSourceManager(let focusAddConnector):
        connectorsManagementView(focusAddConnector: focusAddConnector)
    case .knowledgeConnector(let instanceID):
        knowledgeSourceView(connectorInstanceID: instanceID)
    case .knowledgeDocument(let instanceID, _):
        knowledgeSourceView(connectorInstanceID: instanceID)
    }
}
```

Extract the existing `DailyMarkdownView` to:

```swift
private var diaryReaderView: some View {
    DailyMarkdownView(
        story: appState.selectedStory,
        selectedParagraphID: appState.selectedStoryParagraphID,
        dayKey: appState.selectedDate,
        refreshJob: selectedRefreshJob,
        refreshLogNotice: appState.refreshLogNotice(for: appState.selectedDate),
        isGenerating: appState.isGeneratingJournal(for: appState.selectedDate),
        isActive: appState.readerFocus == .storyParagraphs,
        onSelectParagraph: { paragraphID in
            appState.focusStoryParagraphs()
            appState.selectStoryParagraph(paragraphID)
            onStoryParagraphTap?(paragraphID)
        },
        onFocusStory: {
            appState.focusStoryParagraphs()
        },
        onRefresh: {
            Task { @MainActor in
                await appState.refreshSelectedDay()
            }
        },
        onTodayFullRefresh: {
            Task { @MainActor in
                await appState.refreshSelectedDayFullRecovery()
            }
        },
        canFullRefresh: appState.selectedDate != nil && appState.selectedDate != OnboardingDemoStory.demoDayKey,
        fullRefreshMenuTitle: appState.selectedDate == ISO8601DayKey.format(Date())
            ? "Full Refresh Today (Overwriting)"
            : "Full Refresh (Overwriting)"
    )
}
```

Add:

```swift
private func knowledgeSourceView(connectorInstanceID: String) -> some View {
    let connector = appState.knowledgeImportConfig.connectorInstances.first { $0.id == connectorInstanceID }
    return Group {
        if let connector {
            KnowledgeSourceContentView(
                presentation: KnowledgeSourceContentPresentation(
                    connector: connector,
                    documents: appState.selectedKnowledgeDocuments,
                    selectedDocumentID: appState.selectedKnowledgeDocument?.id,
                    selectedMarkdown: appState.selectedKnowledgeDocumentMarkdown,
                    statusMessage: appState.knowledgeImportStatusMessage
                ),
                onSyncNow: {
                    Task { @MainActor in
                        await appState.importKnowledgeNow()
                        appState.selectKnowledgeConnector(instanceID: connectorInstanceID)
                    }
                },
                onSelectDocument: { documentID in
                    appState.selectKnowledgeDocument(
                        connectorInstanceID: connectorInstanceID,
                        documentID: documentID
                    )
                },
                onConfigure: {
                    appState.selectOtherSourceManager(focusAddConnector: false)
                }
            )
        } else {
            Text("Connector not found")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
```

- [ ] **Step 4: Keep detail pane diary-specific**

For non-diary content, render a simple local-source explanation in the detail pane:

```swift
private var detailPane: some View {
    Group {
        switch appState.mainContentSelection {
        case .diary:
            StorySourceDetailView(
                selectedParagraph: appState.selectedStoryParagraph,
                selectedEvents: appState.selectedStorySourceEvents,
                allEvents: appState.selectedDayEvents
            )
        default:
            VStack(alignment: .leading, spacing: 8) {
                Text("Local Source")
                    .font(.headline)
                Text("Other Source documents are copied into KnowYou local storage. Source files are not modified.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}
```

- [ ] **Step 5: Wire deletion cleanup**

In `deleteKnowledgeImportConnector(id:)`, after saving config:

```swift
appState.didDeleteKnowledgeConnector(instanceID: id)
```

- [ ] **Step 6: Run focused tests and build**

Run:

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/MainWindowViewModelTests/testDeletingSelectedKnowledgeConnectorReturnsToOtherSourceManager
xcodebuild build -scheme KnowYou -destination 'platform=macOS'
```

Expected: tests and build pass.

- [ ] **Step 7: Commit**

```bash
git add KnowYou/UI/MainWindowView.swift KnowYou/App/AppState.swift KnowYouTests/MainWindowViewModelTests.swift
git commit -m "Switch main content for Other Source navigation"
```

---

## Task 7: Documentation Updates

**Files:**
- Modify: `docs/architecture.md`
- Modify: `docs/requirements-spec.md`

- [ ] **Step 1: Update architecture doc**

Add a section describing:

```markdown
### Other Source Root Navigation

The main sidebar now separates diary navigation from imported knowledge sources. `My Diary` owns daily generated diary entries. `Other Source` is a fixed management entry for adding, configuring, deleting, and syncing import connectors. Each configured connector instance appears as a root-level sidebar item and opens a local content browser backed by `knowledge_import_documents` and `KnowledgeSources`.

AppState uses `MainContentSelection` to avoid encoding non-diary pages as date strings.
```

- [ ] **Step 2: Update requirements spec**

Add requirements:

```markdown
### Other Source Navigation

- The sidebar must always show `My Diary` and `Other Source`.
- `Other Source` opens connector management, not a mixed document overview.
- Adding a connector must create a root-level sidebar entry for that connector.
- Clicking a connector root entry must open synced local content.
- The UI must explain that imported documents are copied locally and source files are not modified.
```

- [ ] **Step 3: Commit**

```bash
git add docs/architecture.md docs/requirements-spec.md
git commit -m "Document Other Source navigation architecture"
```

---

## Task 8: Verification and Manual Product Smoke Test

**Files:**
- No source changes unless verification finds issues.

- [ ] **Step 1: Run targeted test slice**

Run:

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' \
  -only-testing:KnowYouTests/DailyMarkdownViewTests \
  -only-testing:KnowYouTests/ConnectorsPanelTests \
  -only-testing:KnowYouTests/KnowledgeSourceContentViewTests \
  -only-testing:KnowYouTests/MainWindowViewModelTests/testAppStateSelectsOtherSourceManagerWithoutChangingSelectedDiaryDate \
  -only-testing:KnowYouTests/MainWindowViewModelTests/testAppStateSelectsKnowledgeConnectorAndLoadsItsDocuments \
  -only-testing:KnowYouTests/MainWindowViewModelTests/testDeletingSelectedKnowledgeConnectorReturnsToOtherSourceManager
```

Expected: all targeted tests pass.

- [ ] **Step 2: Run full test suite**

Run:

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS'
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 3: Run full build**

Run:

```bash
xcodebuild build -scheme KnowYou -destination 'platform=macOS'
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Remove stale app artifacts before smoke test**

Find built apps:

```bash
find /Users/wutianfu/Library/Developer/Xcode/DerivedData -path '*/Build/Products/Debug/KnowYou.app' -maxdepth 7 -print
```

Keep only the newest DerivedData app path from the current build session. Delete older `KnowYou.app` bundles:

```bash
LATEST_APP=$(find /Users/wutianfu/Library/Developer/Xcode/DerivedData -path '*/Build/Products/Debug/KnowYou.app' -maxdepth 7 -print0 | xargs -0 stat -f '%m %N' | sort -nr | head -1 | cut -d' ' -f2-)
find /Users/wutianfu/Library/Developer/Xcode/DerivedData -path '*/Build/Products/Debug/KnowYou.app' -maxdepth 7 -print | while read -r app; do
  if [ "$app" != "$LATEST_APP" ]; then
    rm -rf "$app"
  fi
done
```

- [ ] **Step 5: Launch freshly built app**

Run:

```bash
pkill -x KnowYou || true
LATEST_APP=$(find /Users/wutianfu/Library/Developer/Xcode/DerivedData -path '*/Build/Products/Debug/KnowYou.app' -maxdepth 7 -print0 | xargs -0 stat -f '%m %N' | sort -nr | head -1 | cut -d' ' -f2-)
open -n "$LATEST_APP"
```

If the app launches with only the menu bar, use:

```bash
osascript -e 'tell application "KnowYou" to activate' \
  -e 'tell application "System Events" to tell process "KnowYou" to keystroke "n" using command down'
```

- [ ] **Step 6: Smoke test user workflow**

Using Computer Use or manual UI inspection, verify:

1. Sidebar shows `My Diary` and `Other Source` without opening the gear menu.
2. `Other Source` has a visible `+` button.
3. Clicking `Other Source` opens the connector management page in the main content area.
4. Clicking `+` opens the management page with the add connector form visible.
5. Adding or preconfiguring a test connector makes it appear as a root-level sidebar item.
6. Clicking that connector opens a content page rather than the settings form.
7. Empty connector page shows local-storage copy and `Sync Now`.

- [ ] **Step 7: Check git diff and final status**

Run:

```bash
git diff --check
git status --short
git log --oneline -8
```

Expected: no whitespace errors; only intended commits present; no untracked build artifacts.
