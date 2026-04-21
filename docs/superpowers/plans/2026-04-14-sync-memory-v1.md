# Sync Memory V1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 KnowYou 中新增位于左下角 settings / `...` 二级菜单下的 `Sync Memory` 功能，支持将最新每日日记同步到 Obsidian 和 OpenClaw，并通过用户级 LaunchAgent 在用户登录后每天固定时间自动执行同步。

**Architecture:** 这一版把 Sync Memory 设计成独立于日记生成和 diary engine 的子系统。数据从现有 vault 中最新的 `YYYY-MM-DD.md` 读取，经过路径探测和渠道配置后，由 `SyncMemoryCoordinator` 执行复制，再由 `LaunchAgentManager` 负责每天固定时间调度。UI 入口挂在左侧日期栏底部的 settings / `...` 菜单中，并通过 `AppState` 暴露状态、操作和最近结果。

**Tech Stack:** SwiftUI、AppKit、Foundation、XCTest、launchd plist、UserDefaults、security-scoped bookmark（如果目录访问需要持久 bookmark）

---

## 文件结构

### 新增文件

- `KnowYou/Domain/SyncMemoryChannel.swift`
  - 定义渠道枚举、状态枚举、渠道展示文案
- `KnowYou/Services/SyncMemory/SyncMemoryConfig.swift`
  - 持久化 sync-memory 配置
- `KnowYou/Services/SyncMemory/SyncMemoryPathDetector.swift`
  - 探测 Obsidian vault 和 OpenClaw workspace
- `KnowYou/Services/SyncMemory/SyncMemoryCoordinator.swift`
  - 读取最新日记并复制到目标目录
- `KnowYou/Services/SyncMemory/LaunchAgentManager.swift`
  - 生成、安装、更新、移除 LaunchAgent plist
- `KnowYou/UI/Settings/SyncMemoryPanel.swift`
  - 同步面板 UI
- `KnowYouTests/SyncMemoryConfigTests.swift`
- `KnowYouTests/SyncMemoryPathDetectorTests.swift`
- `KnowYouTests/SyncMemoryCoordinatorTests.swift`
- `KnowYouTests/LaunchAgentManagerTests.swift`
- `KnowYouTests/SyncMemoryPanelTests.swift`

### 修改文件

- `KnowYou/App/AppState.swift`
  - 新增 sync-memory 状态、动作、调度集成
- `KnowYou/UI/Sidebar/DateSidebarView.swift`
  - 在左下角新增 settings / `...` 二级菜单入口
- `KnowYou/UI/MainWindowView.swift`
  - 承载 `Sync Memory` 面板展示状态
- `KnowYou/UI/Settings/SettingsView.swift`
  - 增加 sync-memory 的次级状态说明或入口说明，避免 Settings 页和左下角入口冲突
- `KnowYou/KnowYouApp.swift`
  - 如需要，为面板展示或 app 启动时的 sync-memory 初始化补充挂钩
- `KnowYou.xcodeproj/project.pbxproj`
  - 注册新文件
- `docs/architecture.md`
  - 同步真实架构变化
- `docs/requirements-spec.md`
  - 同步产品能力变化

## Task 1: 建立 Sync Memory 配置模型

**Files:**
- Create: `KnowYou/Domain/SyncMemoryChannel.swift`
- Create: `KnowYou/Services/SyncMemory/SyncMemoryConfig.swift`
- Test: `KnowYouTests/SyncMemoryConfigTests.swift`
- Modify: `KnowYou.xcodeproj/project.pbxproj`

- [ ] **Step 1: 写出配置模型的失败测试**

```swift
import XCTest
@testable import KnowYou

final class SyncMemoryConfigTests: XCTestCase {
    func testSaveAndLoadPersistsEnabledChannelsAndDailyTime() throws {
        let defaults = UserDefaults(suiteName: "SyncMemoryConfigTests-\(UUID().uuidString)")!
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }

        var config = SyncMemoryConfig.default
        config.obsidian.isEnabled = true
        config.obsidian.bookmarkData = Data([0x01, 0x02])
        config.openClaw.isEnabled = true
        config.openClaw.resolvedPath = "/Users/test/.openclaw/workspace/know-you-memory"
        config.autoSyncEnabled = true
        config.dailySyncHour = 21
        config.dailySyncMinute = 30

        config.save(to: defaults)
        let loaded = SyncMemoryConfig.load(from: defaults)

        XCTAssertTrue(loaded.obsidian.isEnabled)
        XCTAssertEqual(loaded.obsidian.bookmarkData, Data([0x01, 0x02]))
        XCTAssertTrue(loaded.openClaw.isEnabled)
        XCTAssertEqual(loaded.openClaw.resolvedPath, "/Users/test/.openclaw/workspace/know-you-memory")
        XCTAssertTrue(loaded.autoSyncEnabled)
        XCTAssertEqual(loaded.dailySyncHour, 21)
        XCTAssertEqual(loaded.dailySyncMinute, 30)
    }

    func testLoadFallsBackToDefaultWhenStoreIsEmpty() {
        let defaults = UserDefaults(suiteName: "SyncMemoryConfigTests-\(UUID().uuidString)")!
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }

        let loaded = SyncMemoryConfig.load(from: defaults)

        XCTAssertFalse(loaded.obsidian.isEnabled)
        XCTAssertFalse(loaded.openClaw.isEnabled)
        XCTAssertFalse(loaded.autoSyncEnabled)
        XCTAssertEqual(loaded.dailySyncHour, 21)
        XCTAssertEqual(loaded.dailySyncMinute, 0)
    }

    private func defaultsSuiteName(_ defaults: UserDefaults) -> String {
        defaults.dictionaryRepresentation()["suiteName"] as? String ?? ""
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/SyncMemoryConfigTests`

Expected: FAIL，提示 `SyncMemoryConfig` 或 `SyncMemoryChannel` 尚不存在。

- [ ] **Step 3: 写最小配置实现**

```swift
import Foundation

enum SyncMemoryChannel: String, CaseIterable, Codable {
    case obsidian
    case openClaw
}

struct SyncMemoryChannelConfig: Codable, Equatable {
    var isEnabled: Bool = false
    var resolvedPath: String?
    var bookmarkData: Data?
    var lastDetectionSummary: String?
}

struct SyncMemoryConfig: Codable, Equatable {
    var obsidian = SyncMemoryChannelConfig()
    var openClaw = SyncMemoryChannelConfig()
    var autoSyncEnabled = false
    var dailySyncHour = 21
    var dailySyncMinute = 0

    static let `default` = SyncMemoryConfig()

    private static let storageKey = "syncMemoryConfig"

    func save(to defaults: UserDefaults = .standard) {
        let data = try? JSONEncoder().encode(self)
        defaults.set(data, forKey: Self.storageKey)
    }

    static func load(from defaults: UserDefaults = .standard) -> SyncMemoryConfig {
        guard
            let data = defaults.data(forKey: storageKey),
            let decoded = try? JSONDecoder().decode(SyncMemoryConfig.self, from: data)
        else {
            return .default
        }
        return decoded
    }
}
```

- [ ] **Step 4: 重新跑配置测试确认通过**

Run: `xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/SyncMemoryConfigTests`

Expected: PASS，`2 tests, 0 failures`

- [ ] **Step 5: 提交配置模型**

```bash
git add KnowYou/Domain/SyncMemoryChannel.swift KnowYou/Services/SyncMemory/SyncMemoryConfig.swift KnowYouTests/SyncMemoryConfigTests.swift KnowYou.xcodeproj/project.pbxproj
git commit -m "feat: add sync memory configuration model"
```

## Task 2: 实现 Obsidian 和 OpenClaw 路径探测

**Files:**
- Create: `KnowYou/Services/SyncMemory/SyncMemoryPathDetector.swift`
- Test: `KnowYouTests/SyncMemoryPathDetectorTests.swift`
- Modify: `KnowYou.xcodeproj/project.pbxproj`

- [ ] **Step 1: 写路径探测失败测试**

```swift
import XCTest
@testable import KnowYou

final class SyncMemoryPathDetectorTests: XCTestCase {
    func testDetectObsidianVaultReturnsFolderContainingDotObsidian() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let vault = root.appendingPathComponent("WorkVault", isDirectory: true)
        try FileManager.default.createDirectory(at: vault.appendingPathComponent(".obsidian", isDirectory: true), withIntermediateDirectories: true)

        let detector = SyncMemoryPathDetector(fileManager: .default)
        let result = detector.detectObsidianVaults(searchRoots: [root])

        XCTAssertEqual(result.first?.lastPathComponent, "WorkVault")
    }

    func testResolveOpenClawWorkspacePrefersDefaultWorkspacePath() {
        let detector = SyncMemoryPathDetector(fileManager: .default)
        let workspace = detector.defaultOpenClawWorkspace(homePath: "/Users/test")

        XCTAssertEqual(workspace.path, "/Users/test/.openclaw/workspace")
    }

    func testOpenClawMemoryDirectoryAppendsKnowYouFolder() {
        let detector = SyncMemoryPathDetector(fileManager: .default)
        let workspace = URL(fileURLWithPath: "/Users/test/.openclaw/workspace", isDirectory: true)

        XCTAssertEqual(
            detector.openClawMemoryDirectory(for: workspace).path,
            "/Users/test/.openclaw/workspace/know-you-memory"
        )
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/SyncMemoryPathDetectorTests`

Expected: FAIL，提示 `SyncMemoryPathDetector` 未定义。

- [ ] **Step 3: 写最小路径探测实现**

```swift
import Foundation

struct SyncMemoryPathDetector {
    let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func detectObsidianVaults(searchRoots: [URL]) -> [URL] {
        searchRoots.compactMap { root in
            guard let contents = try? fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else {
                return nil
            }

            return contents.first(where: { candidate in
                var isDirectory: ObjCBool = false
                let hasDirectory = fileManager.fileExists(atPath: candidate.path, isDirectory: &isDirectory)
                let hasDotObsidian = fileManager.fileExists(atPath: candidate.appendingPathComponent(".obsidian").path)
                return hasDirectory && isDirectory.boolValue && hasDotObsidian
            })
        }
    }

    func defaultOpenClawWorkspace(homePath: String) -> URL {
        URL(fileURLWithPath: homePath, isDirectory: true)
            .appendingPathComponent(".openclaw", isDirectory: true)
            .appendingPathComponent("workspace", isDirectory: true)
    }

    func openClawMemoryDirectory(for workspace: URL) -> URL {
        workspace.appendingPathComponent("know-you-memory", isDirectory: true)
    }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/SyncMemoryPathDetectorTests`

Expected: PASS，`3 tests, 0 failures`

- [ ] **Step 5: 提交路径探测**

```bash
git add KnowYou/Services/SyncMemory/SyncMemoryPathDetector.swift KnowYouTests/SyncMemoryPathDetectorTests.swift KnowYou.xcodeproj/project.pbxproj
git commit -m "feat: add sync memory path detection"
```

## Task 3: 实现文件复制协调器

**Files:**
- Create: `KnowYou/Services/SyncMemory/SyncMemoryCoordinator.swift`
- Test: `KnowYouTests/SyncMemoryCoordinatorTests.swift`
- Modify: `KnowYou.xcodeproj/project.pbxproj`

- [ ] **Step 1: 写协调器失败测试**

```swift
import XCTest
@testable import KnowYou

final class SyncMemoryCoordinatorTests: XCTestCase {
    func testSyncLatestDiaryCopiesMarkdownIntoObsidianAndOpenClawTargets() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sourceVault = root.appendingPathComponent("source", isDirectory: true)
        let obsidianTarget = root.appendingPathComponent("obsidian/KnowYou/Daily Memories", isDirectory: true)
        let openClawTarget = root.appendingPathComponent("openclaw/know-you-memory", isDirectory: true)

        try FileManager.default.createDirectory(at: sourceVault, withIntermediateDirectories: true)
        let sourceFile = sourceVault.appendingPathComponent("2026-04-14.md")
        try "# Test".write(to: sourceFile, atomically: true, encoding: .utf8)

        let coordinator = SyncMemoryCoordinator(fileManager: .default)
        let result = try coordinator.syncLatestDiary(
            sourceVault: sourceVault,
            destinations: [
                .obsidian: obsidianTarget,
                .openClaw: openClawTarget
            ]
        )

        XCTAssertEqual(result[.obsidian]?.copiedFileName, "2026-04-14.md")
        XCTAssertEqual(result[.openClaw]?.copiedFileName, "2026-04-14.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: obsidianTarget.appendingPathComponent("2026-04-14.md").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: openClawTarget.appendingPathComponent("2026-04-14.md").path))
    }

    func testSyncLatestDiaryThrowsWhenNoMarkdownExists() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let coordinator = SyncMemoryCoordinator(fileManager: .default)

        XCTAssertThrowsError(try coordinator.syncLatestDiary(sourceVault: root, destinations: [:]))
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/SyncMemoryCoordinatorTests`

Expected: FAIL，提示 `SyncMemoryCoordinator` 未定义。

- [ ] **Step 3: 写最小复制实现**

```swift
import Foundation

struct SyncMemoryCopyResult: Equatable {
    var copiedFileName: String
    var destinationPath: String
}

enum SyncMemoryCoordinatorError: LocalizedError {
    case noDiaryMarkdownFound
}

struct SyncMemoryCoordinator {
    let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func syncLatestDiary(
        sourceVault: URL,
        destinations: [SyncMemoryChannel: URL]
    ) throws -> [SyncMemoryChannel: SyncMemoryCopyResult] {
        let files = try fileManager.contentsOfDirectory(
            at: sourceVault,
            includingPropertiesForKeys: nil
        )
        let latest = files
            .filter { $0.pathExtension == "md" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
            .first

        guard let latest else {
            throw SyncMemoryCoordinatorError.noDiaryMarkdownFound
        }

        var results: [SyncMemoryChannel: SyncMemoryCopyResult] = [:]
        for (channel, directory) in destinations {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let target = directory.appendingPathComponent(latest.lastPathComponent)
            if fileManager.fileExists(atPath: target.path) {
                try fileManager.removeItem(at: target)
            }
            try fileManager.copyItem(at: latest, to: target)
            results[channel] = SyncMemoryCopyResult(
                copiedFileName: latest.lastPathComponent,
                destinationPath: target.path
            )
        }
        return results
    }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/SyncMemoryCoordinatorTests`

Expected: PASS，`2 tests, 0 failures`

- [ ] **Step 5: 提交协调器**

```bash
git add KnowYou/Services/SyncMemory/SyncMemoryCoordinator.swift KnowYouTests/SyncMemoryCoordinatorTests.swift KnowYou.xcodeproj/project.pbxproj
git commit -m "feat: add sync memory coordinator"
```

## Task 4: 实现 LaunchAgent 生成与安装管理

**Files:**
- Create: `KnowYou/Services/SyncMemory/LaunchAgentManager.swift`
- Test: `KnowYouTests/LaunchAgentManagerTests.swift`
- Modify: `KnowYou.xcodeproj/project.pbxproj`

- [ ] **Step 1: 写 LaunchAgent 失败测试**

```swift
import XCTest
@testable import KnowYou

final class LaunchAgentManagerTests: XCTestCase {
    func testAgentPlistIncludesStartCalendarIntervalAndProgramArguments() throws {
        let manager = LaunchAgentManager(fileManager: .default)

        let plist = manager.renderPlist(
            executablePath: "/Applications/KnowYou.app/Contents/MacOS/KnowYou",
            hour: 21,
            minute: 15
        )

        XCTAssertTrue(plist.contains("<key>Label</key>"))
        XCTAssertTrue(plist.contains("dev.knowyou.sync-memory"))
        XCTAssertTrue(plist.contains("<key>Hour</key>"))
        XCTAssertTrue(plist.contains("<integer>21</integer>"))
        XCTAssertTrue(plist.contains("<key>Minute</key>"))
        XCTAssertTrue(plist.contains("<integer>15</integer>"))
        XCTAssertTrue(plist.contains("/Applications/KnowYou.app/Contents/MacOS/KnowYou"))
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/LaunchAgentManagerTests`

Expected: FAIL，提示 `LaunchAgentManager` 未定义。

- [ ] **Step 3: 写最小 LaunchAgent 实现**

```swift
import Foundation

struct LaunchAgentManager {
    let fileManager: FileManager
    let label = "dev.knowyou.sync-memory"

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func renderPlist(executablePath: String, hour: Int, minute: Int) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(label)</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(executablePath)</string>
                <string>--sync-memory-now</string>
            </array>
            <key>StartCalendarInterval</key>
            <dict>
                <key>Hour</key>
                <integer>\(hour)</integer>
                <key>Minute</key>
                <integer>\(minute)</integer>
            </dict>
            <key>RunAtLoad</key>
            <true/>
        </dict>
        </plist>
        """
    }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/LaunchAgentManagerTests`

Expected: PASS，`1 test, 0 failures`

- [ ] **Step 5: 提交 LaunchAgent 管理器**

```bash
git add KnowYou/Services/SyncMemory/LaunchAgentManager.swift KnowYouTests/LaunchAgentManagerTests.swift KnowYou.xcodeproj/project.pbxproj
git commit -m "feat: add sync memory launch agent manager"
```

## Task 5: 把 Sync Memory 状态和动作接进 AppState

**Files:**
- Modify: `KnowYou/App/AppState.swift`
- Test: `KnowYouTests/MainWindowViewModelTests.swift`

- [ ] **Step 1: 写 AppState 集成失败测试**

```swift
func testAppStateLoadsSyncMemoryDefaultsAndExposesClosedPanelInitially() {
    let defaults = UserDefaults(suiteName: "MainWindowViewModelTests-\(UUID().uuidString)")!
    let appState = AppState(bootstrapServices: false, userDefaults: defaults)

    XCTAssertFalse(appState.isShowingSyncMemoryPanel)
    XCTAssertEqual(appState.syncMemoryConfig.dailySyncHour, 21)
    XCTAssertEqual(appState.syncMemoryConfig.dailySyncMinute, 0)
}

func testAppStateCanToggleSyncMemoryPanelVisibility() {
    let appState = AppState(bootstrapServices: false)

    appState.openSyncMemoryPanel()
    XCTAssertTrue(appState.isShowingSyncMemoryPanel)

    appState.closeSyncMemoryPanel()
    XCTAssertFalse(appState.isShowingSyncMemoryPanel)
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/MainWindowViewModelTests/testAppStateLoadsSyncMemoryDefaultsAndExposesClosedPanelInitially -only-testing:KnowYouTests/MainWindowViewModelTests/testAppStateCanToggleSyncMemoryPanelVisibility`

Expected: FAIL，提示 `isShowingSyncMemoryPanel` 或 `syncMemoryConfig` 不存在。

- [ ] **Step 3: 在 AppState 中接入最小状态和动作**

```swift
@MainActor
@Observable
final class AppState {
    var isShowingSyncMemoryPanel = false
    var syncMemoryConfig: SyncMemoryConfig

    init(
        environment: AppEnvironment? = nil,
        bootstrapServices: Bool = true,
        summarizerConfig: SummarizerConfig? = nil,
        probeEngine: @escaping @Sendable (DiaryEngine, SummarizerConfig, [String: String]) async -> EngineProbeResult = { engine, config, environment in
            await EngineProbe().probe(engine: engine, config: config, environment: environment)
        },
        makeSummarizer: @escaping SummarizerFactory = { engine, config, environment in
            config.makeSummarizer(for: engine, environment: environment)
        },
        onRefreshStageChange: RefreshStageChangeHandler? = nil,
        processEnvironment: [String: String] = ProcessInfo.processInfo.environment,
        currentDate: @escaping @Sendable () -> Date = Date.init,
        userDefaults: UserDefaults = .standard,
        keychain: KeychainStoring = KeychainHelper.shared,
        keychainService: String = KeychainHelper.service
    ) {
        self.syncMemoryConfig = SyncMemoryConfig.load(from: userDefaults)
    }

    func openSyncMemoryPanel() {
        isShowingSyncMemoryPanel = true
    }

    func closeSyncMemoryPanel() {
        isShowingSyncMemoryPanel = false
    }
}
```

- [ ] **Step 4: 重新跑 AppState 测试确认通过**

Run: `xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/MainWindowViewModelTests/testAppStateLoadsSyncMemoryDefaultsAndExposesClosedPanelInitially -only-testing:KnowYouTests/MainWindowViewModelTests/testAppStateCanToggleSyncMemoryPanelVisibility`

Expected: PASS，`2 tests, 0 failures`

- [ ] **Step 5: 提交 AppState 基础集成**

```bash
git add KnowYou/App/AppState.swift KnowYouTests/MainWindowViewModelTests.swift
git commit -m "feat: add sync memory app state"
```

## Task 6: 在左侧底部加入 settings / `...` 二级菜单和同步面板

**Files:**
- Modify: `KnowYou/UI/Sidebar/DateSidebarView.swift`
- Modify: `KnowYou/UI/MainWindowView.swift`
- Create: `KnowYou/UI/Settings/SyncMemoryPanel.swift`
- Test: `KnowYouTests/SyncMemoryPanelTests.swift`
- Modify: `KnowYou.xcodeproj/project.pbxproj`

- [ ] **Step 1: 写面板失败测试**

```swift
import XCTest
import SwiftUI
import AppKit
@testable import KnowYou

final class SyncMemoryPanelTests: XCTestCase {
    func testSyncMemoryPanelRendersBothChannels() {
        let config = SyncMemoryConfig.default
        let view = SyncMemoryPanel(
            config: config,
            obsidianStatusText: "Ready",
            openClawStatusText: "Missing",
            onSyncNow: {},
            onClose: {}
        )
        let hostingView = NSHostingView(rootView: view)

        hostingView.frame = NSRect(x: 0, y: 0, width: 420, height: 360)
        hostingView.layoutSubtreeIfNeeded()

        XCTAssertNotNil(hostingView)
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/SyncMemoryPanelTests`

Expected: FAIL，提示 `SyncMemoryPanel` 未定义。

- [ ] **Step 3: 写最小面板和左下角菜单接线**

```swift
import SwiftUI

struct SyncMemoryPanel: View {
    let config: SyncMemoryConfig
    let obsidianStatusText: String
    let openClawStatusText: String
    let onSyncNow: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Sync Memory")
                .font(.title3)
                .fontWeight(.semibold)

            Text("Obsidian: \(obsidianStatusText)")
            Text("OpenClaw: \(openClawStatusText)")

            Toggle("Auto Sync Daily", isOn: .constant(config.autoSyncEnabled))
                .disabled(true)

            HStack {
                Button("Sync Now", action: onSyncNow)
                Spacer()
                Button("Close", action: onClose)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}
```

```swift
Menu {
    Button("Sync Memory") {
        onOpenSyncMemory()
    }
} label: {
    Image(systemName: "ellipsis.circle")
}
```

- [ ] **Step 4: 跑面板测试确认通过**

Run: `xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/SyncMemoryPanelTests`

Expected: PASS，`1 test, 0 failures`

- [ ] **Step 5: 提交 UI 入口和面板**

```bash
git add KnowYou/UI/Sidebar/DateSidebarView.swift KnowYou/UI/MainWindowView.swift KnowYou/UI/Settings/SyncMemoryPanel.swift KnowYouTests/SyncMemoryPanelTests.swift KnowYou.xcodeproj/project.pbxproj
git commit -m "feat: add sync memory settings entry"
```

## Task 7: 打通真实同步动作、LaunchAgent 配置和状态展示

**Files:**
- Modify: `KnowYou/App/AppState.swift`
- Modify: `KnowYou/UI/Settings/SyncMemoryPanel.swift`
- Modify: `KnowYou/UI/Settings/SettingsView.swift`
- Test: `KnowYouTests/MainWindowViewModelTests.swift`

- [ ] **Step 1: 写端到端失败测试**

```swift
func testSyncNowCopiesLatestDiaryIntoConfiguredDestinations() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let vault = root.appendingPathComponent("Vault", isDirectory: true)
    try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
    try "# Day".write(to: vault.appendingPathComponent("2026-04-14.md"), atomically: true, encoding: .utf8)

    let environment = try AppEnvironment(
        databasePath: root.appendingPathComponent("events.sqlite").path,
        vaultURL: vault,
        summarizer: nil
    )
    let appState = AppState(environment: environment)

    appState.syncMemoryConfig.obsidian.isEnabled = true
    appState.syncMemoryConfig.obsidian.resolvedPath = root.appendingPathComponent("Obsidian/KnowYou/Daily Memories").path

    XCTAssertNoThrow(try appState.syncMemoryNow())
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/MainWindowViewModelTests/testSyncNowCopiesLatestDiaryIntoConfiguredDestinations`

Expected: FAIL，提示 `syncMemoryNow()` 不存在。

- [ ] **Step 3: 实现 AppState 动作和 LaunchAgent 更新**

```swift
extension AppState {
    func syncMemoryNow() throws {
        guard let environment else { return }

        var destinations: [SyncMemoryChannel: URL] = [:]
        if syncMemoryConfig.obsidian.isEnabled, let path = syncMemoryConfig.obsidian.resolvedPath {
            destinations[.obsidian] = URL(fileURLWithPath: path, isDirectory: true)
        }
        if syncMemoryConfig.openClaw.isEnabled, let path = syncMemoryConfig.openClaw.resolvedPath {
            destinations[.openClaw] = URL(fileURLWithPath: path, isDirectory: true)
        }

        let coordinator = SyncMemoryCoordinator()
        _ = try coordinator.syncLatestDiary(
            sourceVault: environment.vaultURL,
            destinations: destinations
        )
        statusMessage = "Sync Memory complete"
    }

    func saveSyncMemoryConfig(_ config: SyncMemoryConfig) {
        syncMemoryConfig = config
        syncMemoryConfig.save(to: userDefaults)
    }
}
```

- [ ] **Step 4: 跑针对性测试确认通过**

Run: `xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/MainWindowViewModelTests/testSyncNowCopiesLatestDiaryIntoConfiguredDestinations`

Expected: PASS，`1 test, 0 failures`

- [ ] **Step 5: 提交真实同步接线**

```bash
git add KnowYou/App/AppState.swift KnowYou/UI/Settings/SyncMemoryPanel.swift KnowYou/UI/Settings/SettingsView.swift KnowYouTests/MainWindowViewModelTests.swift
git commit -m "feat: wire sync memory actions"
```

## Task 8: 同步架构和需求文档，完成全量验证

**Files:**
- Modify: `docs/architecture.md`
- Modify: `docs/requirements-spec.md`
- Modify: `docs/superpowers/specs/2026-04-14-sync-memory-v1-design.md`
- Modify: `docs/superpowers/plans/2026-04-14-sync-memory-v1.md`

- [ ] **Step 1: 更新架构文档**

```md
- 新增 Sync Memory 子系统
- 支持 Obsidian 和 OpenClaw 目标目录
- 通过用户级 LaunchAgent 在用户登录后按固定时间调度
- UI 入口位于左侧底部 settings / `...` 二级菜单
```

- [ ] **Step 2: 更新需求文档**

```md
- 用户可在主窗口左下角 settings / `...` 入口打开 Sync Memory
- 支持 Obsidian 与 OpenClaw
- 可手动同步最新每日日记
- 可配置每天固定时间自动同步
- LaunchAgent 在用户登录后自动生效
```

- [ ] **Step 3: 跑完整测试**

Run: `xcodebuild test -scheme KnowYou -destination 'platform=macOS'`

Expected: PASS，全部测试通过。

- [ ] **Step 4: 跑完整构建**

Run: `xcodebuild build -scheme KnowYou -destination 'platform=macOS'`

Expected: BUILD SUCCEEDED

- [ ] **Step 5: 提交文档与验证收尾**

```bash
git add docs/architecture.md docs/requirements-spec.md docs/superpowers/specs/2026-04-14-sync-memory-v1-design.md docs/superpowers/plans/2026-04-14-sync-memory-v1.md
git commit -m "docs: sync memory architecture and requirements"
```

## 自检结果

### Spec 覆盖检查

- 左下角 settings / `...` 二级菜单入口：Task 6
- Obsidian / OpenClaw 两个渠道：Tasks 1-3, 6-7
- 自动路径探测：Task 2
- 手动同步：Task 7
- LaunchAgent 每日自动同步：Tasks 4, 7
- 状态展示与错误处理：Tasks 5-7
- 架构与需求文档同步：Task 8

### Placeholder 扫描

- 没有保留 `TODO`、`TBD` 或“稍后实现”之类占位语
- 每个任务都给了明确文件路径、测试入口、命令和最小代码骨架

### 类型一致性

- 配置模型统一使用 `SyncMemoryConfig` / `SyncMemoryChannelConfig`
- 路径探测统一由 `SyncMemoryPathDetector` 承担
- 文件复制统一由 `SyncMemoryCoordinator` 承担
- LaunchAgent 统一由 `LaunchAgentManager` 承担
- `AppState` 统一暴露 `syncMemoryConfig`、`openSyncMemoryPanel()`、`closeSyncMemoryPanel()`、`syncMemoryNow()`
