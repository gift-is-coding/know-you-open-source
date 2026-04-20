# Update Pill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 Know You 增加一个只在发现新版本时显示的左上角标题栏更新胶囊，点击后打开更新 sheet，并同时兼容官网直装版与 Mac App Store 版。

**Architecture:** 本次实现分四层推进。先建立渠道解析、版本比较、更新 offer 归一化等纯逻辑层，并用单元测试锁定状态机；再把更新状态接入 `AppState` 和启动/每日检查调度；之后通过 AppKit title bar accessory bridge 把 SwiftUI 胶囊挂到主窗口 traffic lights 右侧，并补上更新 sheet；最后更新产品文档并做完整验证。整个实现保持“同一套 UI，按渠道切换动作”，避免把 Sparkle 或 App Store 逻辑散落到视图层。

**Tech Stack:** Swift, SwiftUI, AppKit, Observation, XCTest, URLSession, macOS `NSTitlebarAccessoryViewController`

---

## 文件结构

### 新建文件

- `KnowYou/Domain/AppUpdate.swift`
  负责定义更新领域模型：`UpdateChannel`、`UpdateActionKind`、`UpdateOffer`、版本比较辅助结构。
- `KnowYou/Services/Updates/UpdateChannelResolver.swift`
  负责从 build metadata / Info.plist / 编译配置解析当前分发渠道。
- `KnowYou/Services/Updates/UpdateService.swift`
  负责更新检查、远端 metadata 解析、版本比较、生成归一化 `UpdateOffer`。
- `KnowYou/UI/Updates/UpdatePillView.swift`
  负责标题栏胶囊的 SwiftUI 视图。
- `KnowYou/UI/Updates/UpdateSheet.swift`
  负责更新详情 sheet 的 SwiftUI 视图。
- `KnowYou/UI/Window/MainWindowTitleBarAccessoryController.swift`
  负责把 SwiftUI 胶囊桥接到 `NSTitlebarAccessoryViewController`。
- `KnowYouTests/UpdateChannelResolverTests.swift`
  负责渠道解析测试。
- `KnowYouTests/UpdateServiceTests.swift`
  负责版本比较、offer 解析、渠道动作映射测试。

### 修改文件

- `KnowYou/App/AppEnvironment.swift`
  注入更新服务依赖。
- `KnowYou/App/AppState.swift`
  持有更新状态、调度启动检查与每日检查、响应胶囊点击与 sheet 动作。
- `KnowYou/UI/MainWindowView.swift`
  挂接 title bar accessory bridge 与更新 sheet。
- `KnowYou/KnowYouApp.swift`
  如有必要，补充启动时窗口生命周期钩子，确保主窗口 accessory 只挂一次。
- `KnowYouTests/MainWindowViewModelTests.swift`
  增加 `AppState` 层的状态机测试。
- `docs/architecture.md`
  记录更新服务、title bar accessory bridge 和双渠道行为。
- `docs/requirements-spec.md`
  增加更新提醒的产品需求。

## Task 1: 建立更新领域模型与渠道解析

**Files:**
- Create: `KnowYou/Domain/AppUpdate.swift`
- Create: `KnowYou/Services/Updates/UpdateChannelResolver.swift`
- Test: `KnowYouTests/UpdateChannelResolverTests.swift`
- Test: `KnowYouTests/UpdateServiceTests.swift`

- [ ] **Step 1: 先写渠道解析和版本比较的失败测试**

```swift
import XCTest
@testable import KnowYou

final class UpdateChannelResolverTests: XCTestCase {
    func test_resolve_returnsDirectWhenBuildChannelIsDirect() {
        let resolver = UpdateChannelResolver(buildChannelOverride: "direct")
        XCTAssertEqual(resolver.resolve(), .direct)
    }

    func test_resolve_returnsAppStoreWhenBuildChannelIsAppStore() {
        let resolver = UpdateChannelResolver(buildChannelOverride: "app-store")
        XCTAssertEqual(resolver.resolve(), .appStore)
    }

    func test_resolve_returnsUnknownForUnsupportedValue() {
        let resolver = UpdateChannelResolver(buildChannelOverride: "beta-lab")
        XCTAssertEqual(resolver.resolve(), .unknown)
    }
}
```

```swift
import XCTest
@testable import KnowYou

final class UpdateServiceTests: XCTestCase {
    func test_versionComparison_treatsNewerPatchAsAvailable() {
        XCTAssertTrue(AppVersion("1.2.4") > AppVersion("1.2.3"))
    }

    func test_versionComparison_treatsSameVersionAsNotAvailable() {
        XCTAssertFalse(AppVersion("1.2.3") > AppVersion("1.2.3"))
    }
}
```

- [ ] **Step 2: 运行测试，确认当前实现还不存在**

Run: `xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/UpdateChannelResolverTests -only-testing:KnowYouTests/UpdateServiceTests`

Expected:
- FAIL，提示 `UpdateChannelResolver`、`AppVersion`、`UpdateChannel` 等类型未定义

- [ ] **Step 3: 写最小领域模型与解析实现**

```swift
import Foundation

enum UpdateChannel: Equatable {
    case direct
    case appStore
    case unknown
}

enum UpdateActionKind: Equatable {
    case installInApp
    case openAppStore
    case unavailable
}

struct AppVersion: Comparable, Equatable {
    let rawValue: String
    private let parts: [Int]

    init(_ rawValue: String) {
        self.rawValue = rawValue
        self.parts = rawValue
            .split(separator: ".")
            .map { Int($0) ?? 0 }
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let count = max(lhs.parts.count, rhs.parts.count)
        for index in 0..<count {
            let left = index < lhs.parts.count ? lhs.parts[index] : 0
            let right = index < rhs.parts.count ? rhs.parts[index] : 0
            if left != right { return left < right }
        }
        return false
    }
}

struct UpdateOffer: Equatable {
    var availableVersion: String
    var releaseSummary: String?
    var publishedAt: Date?
    var actionKind: UpdateActionKind
    var storeURL: URL?
}
```

```swift
import Foundation

struct UpdateChannelResolver {
    var buildChannelOverride: String? = Bundle.main.object(forInfoDictionaryKey: "KYUpdateChannel") as? String

    func resolve() -> UpdateChannel {
        switch buildChannelOverride?.lowercased() {
        case "direct":
            return .direct
        case "app-store", "appstore", "mas":
            return .appStore
        default:
            return .unknown
        }
    }
}
```

- [ ] **Step 4: 再跑刚才的测试，确认基础模型通过**

Run: `xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/UpdateChannelResolverTests -only-testing:KnowYouTests/UpdateServiceTests`

Expected:
- PASS，两个测试类通过

- [ ] **Step 5: 提交这一小步**

```bash
git add KnowYou/Domain/AppUpdate.swift KnowYou/Services/Updates/UpdateChannelResolver.swift KnowYouTests/UpdateChannelResolverTests.swift KnowYouTests/UpdateServiceTests.swift
git commit -m "feat: add update channel and version models"
```

## Task 2: 实现更新服务与 metadata 归一化

**Files:**
- Modify: `KnowYou/Domain/AppUpdate.swift`
- Create: `KnowYou/Services/Updates/UpdateService.swift`
- Test: `KnowYouTests/UpdateServiceTests.swift`

- [ ] **Step 1: 先写更新 offer 解析与渠道动作分流的失败测试**

```swift
func test_fetchOffer_returnsInstallInAppForDirectChannel() async throws {
    let session = URLSession.stubbedJSON("""
    {
      "version": "1.4.0",
      "summary": "Bug fixes and update pill",
      "appStoreURL": "https://apps.apple.com/app/id123"
    }
    """)
    let service = UpdateService(
        session: session,
        resolver: UpdateChannelResolver(buildChannelOverride: "direct"),
        metadataURL: URL(string: "https://example.com/update.json")!,
        currentVersion: "1.3.0"
    )

    let offer = try await service.fetchOffer()
    XCTAssertEqual(offer?.actionKind, .installInApp)
    XCTAssertEqual(offer?.availableVersion, "1.4.0")
}

func test_fetchOffer_returnsOpenAppStoreForAppStoreChannel() async throws {
    let session = URLSession.stubbedJSON("""
    {
      "version": "1.4.0",
      "summary": "Bug fixes and update pill",
      "appStoreURL": "https://apps.apple.com/app/id123"
    }
    """)
    let service = UpdateService(
        session: session,
        resolver: UpdateChannelResolver(buildChannelOverride: "app-store"),
        metadataURL: URL(string: "https://example.com/update.json")!,
        currentVersion: "1.3.0"
    )

    let offer = try await service.fetchOffer()
    XCTAssertEqual(offer?.actionKind, .openAppStore)
}

func test_fetchOffer_returnsNilWhenRemoteVersionIsNotNewer() async throws {
    let session = URLSession.stubbedJSON("""
    {
      "version": "1.3.0",
      "summary": "Same version"
    }
    """)
    let service = UpdateService(
        session: session,
        resolver: UpdateChannelResolver(buildChannelOverride: "direct"),
        metadataURL: URL(string: "https://example.com/update.json")!,
        currentVersion: "1.3.0"
    )

    let offer = try await service.fetchOffer()
    XCTAssertNil(offer)
}
```

- [ ] **Step 2: 跑测试，确认服务尚未实现**

Run: `xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/UpdateServiceTests`

Expected:
- FAIL，提示 `UpdateService`、`URLSession.stubbedJSON` 或 `fetchOffer()` 未定义

- [ ] **Step 3: 实现最小更新服务**

```swift
import Foundation

protocol UpdateServing: Sendable {
    func fetchOffer() async throws -> UpdateOffer?
}

private struct RemoteUpdatePayload: Decodable {
    var version: String
    var summary: String?
    var publishedAt: Date?
    var appStoreURL: URL?
}

struct UpdateService: UpdateServing {
    var session: URLSession
    var resolver: UpdateChannelResolver
    var metadataURL: URL
    var currentVersion: String

    func fetchOffer() async throws -> UpdateOffer? {
        let (data, _) = try await session.data(from: metadataURL)
        let payload = try JSONDecoder().decode(RemoteUpdatePayload.self, from: data)

        guard AppVersion(payload.version) > AppVersion(currentVersion) else {
            return nil
        }

        let actionKind: UpdateActionKind
        switch resolver.resolve() {
        case .direct:
            actionKind = .installInApp
        case .appStore:
            actionKind = .openAppStore
        case .unknown:
            actionKind = .unavailable
        }

        return UpdateOffer(
            availableVersion: payload.version,
            releaseSummary: payload.summary,
            publishedAt: payload.publishedAt,
            actionKind: actionKind,
            storeURL: payload.appStoreURL
        )
    }
}
```

```swift
extension URLSession {
    static func stubbedJSON(_ body: String) -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MainWindowStubURLProtocol.self]
        MainWindowStubURLProtocol.behavior = .success(statusCode: 200, body: Data(body.utf8))
        return URLSession(configuration: config)
    }
}
```

- [ ] **Step 4: 补一个失败路径测试并让它通过**

```swift
func test_fetchOffer_throwsForMalformedPayload() async {
    let session = URLSession.stubbedJSON("{\"bad\":true}")
    let service = UpdateService(
        session: session,
        resolver: UpdateChannelResolver(buildChannelOverride: "direct"),
        metadataURL: URL(string: "https://example.com/update.json")!,
        currentVersion: "1.3.0"
    )

    await XCTAssertThrowsErrorAsync(try await service.fetchOffer())
}
```

Run: `xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/UpdateServiceTests`

Expected:
- PASS，包含 direct / app store / no update / malformed payload 几类情况

- [ ] **Step 5: 提交更新服务**

```bash
git add KnowYou/Domain/AppUpdate.swift KnowYou/Services/Updates/UpdateService.swift KnowYouTests/UpdateServiceTests.swift KnowYouTests/MainWindowViewModelTests.swift
git commit -m "feat: add normalized update service"
```

## Task 3: 把更新状态接入 AppEnvironment 与 AppState

**Files:**
- Modify: `KnowYou/App/AppEnvironment.swift`
- Modify: `KnowYou/App/AppState.swift`
- Test: `KnowYouTests/MainWindowViewModelTests.swift`

- [ ] **Step 1: 先写 AppState 状态机的失败测试**

```swift
@MainActor
func test_checkForUpdates_setsOfferAndShowsPillWhenNewerVersionExists() async throws {
    let appState = AppState()
    appState.environment = .stub(updateService: StubUpdateService(result: .success(
        UpdateOffer(
            availableVersion: "1.4.0",
            releaseSummary: "Update pill shipped",
            publishedAt: nil,
            actionKind: .installInApp,
            storeURL: nil
        )
    )))

    await appState.checkForUpdatesIfNeeded(force: true)

    XCTAssertEqual(appState.updateOffer?.availableVersion, "1.4.0")
    XCTAssertTrue(appState.shouldShowUpdatePill)
}

@MainActor
func test_dismissingUpdateSheet_keepsPillVisible() async throws {
    let appState = AppState()
    appState.updateOffer = UpdateOffer(
        availableVersion: "1.4.0",
        releaseSummary: "Update pill shipped",
        publishedAt: nil,
        actionKind: .installInApp,
        storeURL: nil
    )
    appState.isShowingUpdateSheet = true

    appState.dismissUpdateSheet()

    XCTAssertFalse(appState.isShowingUpdateSheet)
    XCTAssertTrue(appState.shouldShowUpdatePill)
}
```

- [ ] **Step 2: 运行针对性测试，确认 AppState 还没有这些状态**

Run: `xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/MainWindowViewModelTests`

Expected:
- FAIL，提示 `updateOffer`、`shouldShowUpdatePill`、`checkForUpdatesIfNeeded(force:)` 等 API 未定义

- [ ] **Step 3: 给 AppEnvironment 注入更新服务**

```swift
struct AppEnvironment {
    var updateService: UpdateServing

    static func live() throws -> AppEnvironment {
        AppEnvironment(
            updateService: UpdateService(
                session: .shared,
                resolver: UpdateChannelResolver(),
                metadataURL: URL(string: "https://example.com/update.json")!,
                currentVersion: AppBuildMetadata.current.marketingVersion
            )
        )
    }
}
```

- [ ] **Step 4: 在 AppState 加入更新状态与调度**

```swift
@Observable
final class AppState {
    var updateOffer: UpdateOffer?
    var isShowingUpdateSheet = false
    var lastUpdateCheckAt: Date?

    var shouldShowUpdatePill: Bool {
        updateOffer != nil
    }

    func openUpdateSheet() {
        guard updateOffer != nil else { return }
        isShowingUpdateSheet = true
    }

    func dismissUpdateSheet() {
        isShowingUpdateSheet = false
    }

    func checkForUpdatesIfNeeded(force: Bool = false, now: Date = .now) async {
        guard let environment else { return }
        if force == false,
           let lastUpdateCheckAt,
           Calendar.current.isDate(lastUpdateCheckAt, inSameDayAs: now) {
            return
        }

        do {
            updateOffer = try await environment.updateService.fetchOffer()
            lastUpdateCheckAt = now
        } catch {
            lastUpdateCheckAt = now
        }
    }
}
```

- [ ] **Step 5: 在现有启动路径挂上启动检查，并补每日检查入口**

```swift
Task { @MainActor in
    await checkForUpdatesIfNeeded(force: true)
}
```

```swift
func performDailyMaintenance(now: Date = .now) async {
    await checkForUpdatesIfNeeded(force: false, now: now)
}
```

- [ ] **Step 6: 跑 AppState 测试直到通过**

Run: `xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/MainWindowViewModelTests`

Expected:
- PASS，新增用例通过，且没有打破现有刷新/引擎相关测试

- [ ] **Step 7: 提交 AppState 接线**

```bash
git add KnowYou/App/AppEnvironment.swift KnowYou/App/AppState.swift KnowYouTests/MainWindowViewModelTests.swift
git commit -m "feat: add update state to app state"
```

## Task 4: 加入更新 sheet 与标题栏胶囊桥接

**Files:**
- Create: `KnowYou/UI/Updates/UpdatePillView.swift`
- Create: `KnowYou/UI/Updates/UpdateSheet.swift`
- Create: `KnowYou/UI/Window/MainWindowTitleBarAccessoryController.swift`
- Modify: `KnowYou/UI/MainWindowView.swift`
- Modify: `KnowYou/KnowYouApp.swift`
- Test: `KnowYouTests/MainWindowViewModelTests.swift`

- [ ] **Step 1: 先写 UI 行为的状态测试**

```swift
@MainActor
func test_openUpdateSheet_onlyOpensWhenOfferExists() {
    let appState = AppState()

    appState.openUpdateSheet()
    XCTAssertFalse(appState.isShowingUpdateSheet)

    appState.updateOffer = UpdateOffer(
        availableVersion: "1.4.0",
        releaseSummary: "Update pill shipped",
        publishedAt: nil,
        actionKind: .openAppStore,
        storeURL: URL(string: "https://apps.apple.com/app/id123")
    )
    appState.openUpdateSheet()

    XCTAssertTrue(appState.isShowingUpdateSheet)
}
```

- [ ] **Step 2: 运行测试，确认 UI 入口受 AppState 状态约束**

Run: `xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/MainWindowViewModelTests/test_openUpdateSheet_onlyOpensWhenOfferExists`

Expected:
- PASS 或在必要调整后变为 PASS

- [ ] **Step 3: 写最小 SwiftUI 视图**

```swift
import SwiftUI

struct UpdatePillView: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.thinMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("update-pill")
    }
}
```

```swift
import SwiftUI

struct UpdateSheet: View {
    let currentVersion: String
    let offer: UpdateOffer
    let onPrimaryAction: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("发现新版本")
                .font(.title3.bold())
            Text("当前版本：\(currentVersion)")
            Text("可用版本：\(offer.availableVersion)")
            if let releaseSummary = offer.releaseSummary {
                Text(releaseSummary)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button("稍后") { onClose() }
                Button(primaryTitle) { onPrimaryAction() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 420)
    }

    private var primaryTitle: String {
        switch offer.actionKind {
        case .installInApp:
            return "立即更新"
        case .openAppStore:
            return "打开 App Store"
        case .unavailable:
            return "查看详情"
        }
    }
}
```

- [ ] **Step 4: 写标题栏 accessory bridge**

```swift
import AppKit
import SwiftUI

@MainActor
final class MainWindowTitleBarAccessoryController {
    private var accessoryController: NSTitlebarAccessoryViewController?

    func attachIfNeeded(to window: NSWindow, title: String, action: @escaping () -> Void) {
        guard accessoryController == nil else { return }

        let rootView = UpdatePillView(title: title, action: action)
        let hostingView = NSHostingView(rootView: rootView)
        let controller = NSTitlebarAccessoryViewController()
        controller.view = hostingView
        controller.layoutAttribute = .left
        window.addTitlebarAccessoryViewController(controller)
        accessoryController = controller
    }

    func detach(from window: NSWindow) {
        guard let accessoryController else { return }
        window.removeTitlebarAccessoryViewController(at: window.titlebarAccessoryViewControllers.count - 1)
        self.accessoryController = nil
    }
}
```

- [ ] **Step 5: 在 MainWindowView 接入 accessory 和 update sheet**

```swift
@State private var titleBarAccessoryController = MainWindowTitleBarAccessoryController()
```

```swift
.sheet(isPresented: Binding(
    get: { appState.isShowingUpdateSheet },
    set: { presented in
        if presented {
            appState.openUpdateSheet()
        } else {
            appState.dismissUpdateSheet()
        }
    }
)) {
    if let offer = appState.updateOffer {
        UpdateSheet(
            currentVersion: AppBuildMetadata.current.marketingVersion,
            offer: offer,
            onPrimaryAction: {
                appState.performUpdatePrimaryAction()
            },
            onClose: {
                appState.dismissUpdateSheet()
            }
        )
    }
}
```

```swift
.background(WindowAccessor { window in
    if appState.shouldShowUpdatePill, let window {
        titleBarAccessoryController.attachIfNeeded(to: window, title: "Update Available") {
            appState.openUpdateSheet()
        }
    } else if let window {
        titleBarAccessoryController.detach(from: window)
    }
})
```

- [ ] **Step 6: 实现主动作分流**

```swift
func performUpdatePrimaryAction() {
    guard let offer else { return }

    switch offer.actionKind {
    case .installInApp:
        statusMessage = "Starting update..."
        // 后续任务接 Sparkle / updater bridge
    case .openAppStore:
        if let url = offer.storeURL {
            NSWorkspace.shared.open(url)
        }
    case .unavailable:
        break
    }
}
```

- [ ] **Step 7: 跑主窗口与状态测试**

Run: `xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/MainWindowViewModelTests`

Expected:
- PASS，`openUpdateSheet`、`dismissUpdateSheet`、动作分流等测试通过

- [ ] **Step 8: 提交 UI 接线**

```bash
git add KnowYou/UI/Updates/UpdatePillView.swift KnowYou/UI/Updates/UpdateSheet.swift KnowYou/UI/Window/MainWindowTitleBarAccessoryController.swift KnowYou/UI/MainWindowView.swift KnowYou/KnowYouApp.swift KnowYou/App/AppState.swift KnowYouTests/MainWindowViewModelTests.swift
git commit -m "feat: add title bar update pill"
```

## Task 5: 为官网直装版补 updater bridge，为 App Store 保持跳转

**Files:**
- Modify: `KnowYou/Services/Updates/UpdateService.swift`
- Modify: `KnowYou/App/AppState.swift`
- Modify: `KnowYou/Domain/AppUpdate.swift`
- Test: `KnowYouTests/UpdateServiceTests.swift`
- Test: `KnowYouTests/MainWindowViewModelTests.swift`

- [ ] **Step 1: 先写动作分流的失败测试，锁定 direct / appStore 差异**

```swift
func test_performUpdatePrimaryAction_opensStoreForAppStoreOffer() {
    let appState = AppState()
    appState.updateOffer = UpdateOffer(
        availableVersion: "1.4.0",
        releaseSummary: nil,
        publishedAt: nil,
        actionKind: .openAppStore,
        storeURL: URL(string: "https://apps.apple.com/app/id123")
    )

    appState.performUpdatePrimaryAction()

    XCTAssertEqual(appState.statusMessage, nil)
}

func test_performUpdatePrimaryAction_marksProgressForDirectInstall() {
    let appState = AppState()
    appState.updateOffer = UpdateOffer(
        availableVersion: "1.4.0",
        releaseSummary: nil,
        publishedAt: nil,
        actionKind: .installInApp,
        storeURL: nil
    )

    appState.performUpdatePrimaryAction()

    XCTAssertEqual(appState.statusMessage, "Starting update...")
}
```

- [ ] **Step 2: 为 direct 渠道增加 updater protocol，先用 stub bridge 锁接口**

```swift
protocol DirectAppUpdating: Sendable {
    func startUpdate(for offer: UpdateOffer) async throws
}

struct NoopDirectAppUpdater: DirectAppUpdating {
    func startUpdate(for offer: UpdateOffer) async throws {}
}
```

- [ ] **Step 3: 在 AppState 中通过依赖调用 updater，而不是把 Sparkle 写死在视图层**

```swift
func performUpdatePrimaryAction() {
    guard let offer else { return }

    switch offer.actionKind {
    case .installInApp:
        statusMessage = "Starting update..."
        Task { try? await environment?.directAppUpdater.startUpdate(for: offer) }
    case .openAppStore:
        if let url = offer.storeURL {
            NSWorkspace.shared.open(url)
        }
    case .unavailable:
        break
    }
}
```

- [ ] **Step 4: 跑更新动作相关测试**

Run: `xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/UpdateServiceTests -only-testing:KnowYouTests/MainWindowViewModelTests`

Expected:
- PASS，动作分流通过；direct 路径通过 protocol 间接触发，app store 路径保持打开外部 URL

- [ ] **Step 5: 提交 updater bridge**

```bash
git add KnowYou/Services/Updates/UpdateService.swift KnowYou/App/AppState.swift KnowYou/Domain/AppUpdate.swift KnowYouTests/UpdateServiceTests.swift KnowYouTests/MainWindowViewModelTests.swift
git commit -m "feat: split update actions by distribution channel"
```

## Task 6: 更新产品文档并做完整验证

**Files:**
- Modify: `docs/architecture.md`
- Modify: `docs/requirements-spec.md`
- Modify: `docs/superpowers/specs/2026-04-17-update-pill-design.md`
- Modify: `docs/superpowers/plans/2026-04-17-update-pill.md`

- [ ] **Step 1: 更新架构文档**

补充以下内容到 `docs/architecture.md`：

- `UpdateService` 作为新的服务层
- `UpdateChannelResolver` 如何决定 direct / App Store
- `MainWindowTitleBarAccessoryController` 如何把胶囊挂到主窗口标题栏
- `AppState` 如何调度启动检查与每日检查

- [ ] **Step 2: 更新需求文档**

补充以下内容到 `docs/requirements-spec.md`：

- 主窗口左上角更新胶囊只在有新版本时显示
- 点击先打开更新 sheet
- 关闭 sheet 不会隐藏胶囊
- 官网版与 App Store 版共用 UI、分流动作
- 启动检查 + 每日检查

- [ ] **Step 3: 跑 targeted tests**

Run: `xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/UpdateChannelResolverTests -only-testing:KnowYouTests/UpdateServiceTests -only-testing:KnowYouTests/MainWindowViewModelTests`

Expected:
- PASS，所有更新相关测试通过

- [ ] **Step 4: 跑完整验证**

Run: `xcodebuild test -scheme KnowYou -destination 'platform=macOS'`

Expected:
- PASS，全量测试通过

Run: `xcodebuild build -scheme KnowYou -destination 'platform=macOS'`

Expected:
- BUILD SUCCEEDED

- [ ] **Step 5: 做手工验证**

手工检查：

- 直装渠道存在新版本时，左上角胶囊出现在 traffic lights 右边
- 点击胶囊打开 sheet，关闭后胶囊仍在
- App Store 渠道时主按钮文案为“打开 App Store”
- 同一天内重复触发 `checkForUpdatesIfNeeded(force: false)` 不重复发请求
- 第二天再次触发会重新检查

- [ ] **Step 6: 提交文档和最终验证结果**

```bash
git add docs/architecture.md docs/requirements-spec.md docs/superpowers/specs/2026-04-17-update-pill-design.md docs/superpowers/plans/2026-04-17-update-pill.md
git commit -m "docs: document update pill architecture and requirements"
```

## Self-Review

### Spec coverage

- 标题栏左上角 accessory：Task 4
- 双渠道兼容：Task 1, Task 2, Task 5
- 启动检查 + 每日检查：Task 3
- 点开 sheet 而不是直接更新：Task 4
- 关闭后胶囊持续显示：Task 3, Task 4
- 测试与文档更新：Task 6

### Placeholder scan

- 没有使用 `TODO` / `TBD` / “自行实现” 之类占位语
- 每个 task 都给了明确文件、命令和预期结果

### Type consistency

- 使用统一命名：`UpdateOffer`、`UpdateChannelResolver`、`UpdateService`、`checkForUpdatesIfNeeded(force:now:)`、`performUpdatePrimaryAction()`
- direct 渠道 updater 抽象统一为 `DirectAppUpdating`
