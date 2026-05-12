# My Wiki 重新设计实施计划

> **给 agent 工程师：** 必须使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans，按任务逐步执行本计划。步骤使用 checkbox（`- [ ]`）语法跟踪。

**目标：** 把当前 `知识本体` 入口改造成 KnowYou 侧边栏里的 `My Wiki` 功能区，后端继承 llm_wiki pipeline，前端改成总结、核心脉络和搜索优先的轻量 UI。

**架构：** KnowYou 保持 macOS SwiftUI 主应用。`ThirdParty/llm_wiki` 继续承担 ingest、cache、page merge、search、embedding、vector store 等后端 pipeline；KnowYou 侧增加 My Wiki 适配层，负责导出日记、写入 My Wiki schema、读取生成后的 markdown/wiki 页面并展示给用户。

**技术栈：** SwiftUI、Swift Concurrency、XCTest、llm_wiki TypeScript/Rust/Tauri pipeline、Markdown files、LanceDB vector store。

---

## 文件结构

### 需要重命名或新增的 KnowYou 文件

- 修改：`KnowYou/UI/Sidebar/DateSidebarView.swift`
  - 把侧边栏按钮从 `知识本体` 改成 `My Wiki`。

- 修改：`KnowYou/UI/MainWindowView.swift`
  - 主窗口模式从 knowledge ontology 语义迁移到 My Wiki 语义。
  - 第一阶段可以保留旧 enum case 的内部名称，但 UI 文案必须切到 `My Wiki`。

- 新增：`KnowYou/UI/MyWiki/MyWikiPanel.swift`
  - My Wiki 首页，包含搜索框、总结区、核心脉络区、最近同步状态。

- 新增：`KnowYou/UI/MyWiki/MyWikiModels.swift`
  - SwiftUI 展示模型：`MyWikiDashboardSnapshot`、`MyWikiSummary`、`MyWikiEntry`、`MyWikiCategory`、`MyWikiSearchResult`。

- 新增：`KnowYou/UI/MyWiki/MyWikiDetailView.swift`
  - 人物、项目、主题、偏好、待办、总结条目的详情页。

- 新增：`KnowYou/Services/MyWiki/MyWikiProjectExporter.swift`
  - 从现有 `KnowledgeOntologyProjectExporter` 迁移而来，负责创建 My Wiki 目录结构、导出日记、写入 My Wiki schema。

- 新增：`KnowYou/Services/MyWiki/MyWikiMarkdownStore.swift`
  - 读取 `wiki/people`、`wiki/projects`、`wiki/themes`、`wiki/preferences`、`wiki/open-loops`、`wiki/summaries`，转换成展示模型。

- 新增：`KnowYou/Services/MyWiki/MyWikiPipelineBridge.swift`
  - 封装对 llm_wiki pipeline 的调用。第一版可以启动 helper/dev source；后续可改为本地 CLI 或 Tauri command bridge。

- 新增：`KnowYou/Services/MyWiki/MyWikiAgentContextProvider.swift`
  - 给 Codex/Claude/Cowork 准备最小必要上下文。

### 需要保留但降级的旧文件

- 修改：`KnowYou/UI/KnowledgeOntology/KnowledgeOntologyPanel.swift`
  - 第一阶段变成兼容 wrapper，内部转调 `MyWikiPanel`，避免大范围破坏测试。

- 修改：`KnowYou/Services/KnowledgeOntology/KnowledgeOntologyProjectExporter.swift`
  - 第一阶段保留兼容类型，内部转调 `MyWikiProjectExporter`。

- 修改：`KnowYou/Services/KnowledgeOntology/KnowledgeOntologyLauncher.swift`
  - 第一阶段保留 launcher，但 UI 不再宣传打开 llm_wiki 原 workspace。

### 需要新增或更新的测试

- 新增：`KnowYouTests/MyWikiProjectExporterTests.swift`
- 新增：`KnowYouTests/MyWikiMarkdownStoreTests.swift`
- 新增：`KnowYouTests/MyWikiAgentContextProviderTests.swift`
- 修改：`KnowYouTests/KnowledgeOntologyPanelTests.swift`
- 修改：`KnowYouTests/KnowledgeOntologyProjectExporterTests.swift`

### 文档

- 修改：`docs/architecture.md`
- 修改：`docs/requirements-spec.md`
- 保留：`docs/superpowers/specs/2026-05-12-my-wiki-redesign.md`

---

## 任务 1: 入口命名从知识本体改为 My Wiki

**文件：**
- 修改：`KnowYou/UI/Sidebar/DateSidebarView.swift`
- 修改：`KnowYou/UI/MainWindowView.swift`
- 修改：`KnowYouTests/KnowledgeOntologyPanelTests.swift`

- [ ] **步骤 1: 写失败测试，确认 UI 不再出现知识本体文案**

在 `KnowYouTests/KnowledgeOntologyPanelTests.swift` 增加：

```swift
func testRecentExportSummaryUsesMyWikiLanguage() {
    let names = (1...28).map { "knowyou-diary-2026-05-\(String(format: "%02d", $0)).md" }

    let presentation = KnowledgeOntologyRecentExportPresentation(exportedFileNames: names)

    XCTAssertEqual(presentation.visibleFileNames.count, 8)
    XCTAssertEqual(presentation.hiddenCount, 20)
    XCTAssertEqual(presentation.summaryText, "还有 20 个文件已同步，可在 My Wiki 的原始资料中查看。")
}
```

- [ ] **步骤 2: 运行测试并确认失败**

运行：

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/KnowledgeOntologyPanelTests/testRecentExportSummaryUsesMyWikiLanguage
```

预期： 失败，当前实现仍返回 `llm_wiki` 或 `知识本体` 文案。

- [ ] **步骤 3: 修改用户可见文案**

在 `KnowledgeOntologyPanel.swift` 中先做最小改动：

```swift
var summaryText: String? {
    guard hiddenCount > 0 else { return nil }
    return "还有 \(hiddenCount) 个文件已同步，可在 My Wiki 的原始资料中查看。"
}
```

在 `DateSidebarView.swift` 中把入口 label 改成：

```swift
Label("My Wiki", systemImage: "point.3.connected.trianglepath.dotted")
```

在 `KnowledgeOntologyPanel.swift` 的 header 中把标题和说明改成：

```swift
Label("My Wiki", systemImage: "point.3.connected.trianglepath.dotted")
Text("整理你的日记，沉淀最近的人、项目、主题、偏好、待办和总结。")
```

- [ ] **步骤 4: 运行测试确认通过**

运行：

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/KnowledgeOntologyPanelTests
```

预期： 通过。

- [ ] **步骤 5: 提交本任务**

```bash
git add KnowYou/UI/Sidebar/DateSidebarView.swift KnowYou/UI/KnowledgeOntology/KnowledgeOntologyPanel.swift KnowYouTests/KnowledgeOntologyPanelTests.swift
git commit -m "feat: rename knowledge entry to My Wiki"
```

提交后停止，不要 push。

---

## 任务 2: 新建 My Wiki 导出器并保留旧导出器兼容层

**文件：**
- 新增：`KnowYou/Services/MyWiki/MyWikiProjectExporter.swift`
- 修改：`KnowYou/Services/KnowledgeOntology/KnowledgeOntologyProjectExporter.swift`
- 新增：`KnowYouTests/MyWikiProjectExporterTests.swift`
- 修改：`KnowYouTests/KnowledgeOntologyProjectExporterTests.swift`
- 修改：`KnowYou.xcodeproj/project.pbxproj`

- [ ] **步骤 1: 写失败测试，确认 My Wiki 目录和 schema**

创建 `KnowYouTests/MyWikiProjectExporterTests.swift`：

```swift
import XCTest
@testable import KnowYou

final class MyWikiProjectExporterTests: XCTestCase {
    func testEnsureProjectCreatesMyWikiStructureAndReadableSchema() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        try MyWikiProjectExporter().ensureProject(at: root)

        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appending(path: "raw/sources").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appending(path: "wiki/people").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appending(path: "wiki/projects").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appending(path: "wiki/themes").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appending(path: "wiki/preferences").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appending(path: "wiki/open-loops").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appending(path: "wiki/summaries").path))

        let schema = try String(contentsOf: root.appending(path: "schema.md"), encoding: .utf8)
        XCTAssertTrue(schema.contains("# My Wiki Schema"))
        XCTAssertTrue(schema.contains("人物"))
        XCTAssertTrue(schema.contains("项目"))
        XCTAssertTrue(schema.contains("主题"))
        XCTAssertTrue(schema.contains("偏好"))
        XCTAssertTrue(schema.contains("待办"))
        XCTAssertFalse(schema.contains("知识本体"))
    }
}
```

- [ ] **步骤 2: 运行测试并确认失败**

运行：

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/MyWikiProjectExporterTests
```

预期： 失败，`MyWikiProjectExporter` 尚不存在。

- [ ] **步骤 3: 实现 MyWikiProjectExporter**

创建 `KnowYou/Services/MyWiki/MyWikiProjectExporter.swift`，从旧 exporter 迁移核心逻辑，目录改为：

```swift
let directories = [
    "raw/sources",
    "raw/assets",
    "wiki/people",
    "wiki/projects",
    "wiki/themes",
    "wiki/preferences",
    "wiki/open-loops",
    "wiki/summaries",
    "wiki/sources",
    ".obsidian"
]
```

`schemaMarkdown` 必须包含：

```markdown
# My Wiki Schema

## 用户可见分类

| UI 名称 | 内部 type | Directory | 说明 |
| --- | --- | --- | --- |
| 人物 | person | wiki/people/ | 家人、朋友、同事、合作方 |
| 项目 | project | wiki/projects/ | 正在推进或长期出现的项目 |
| 主题 | theme | wiki/themes/ | 反复出现的关注点 |
| 偏好 | preference | wiki/preferences/ | 用户稳定表达的选择倾向 |
| 待办 | open_loop | wiki/open-loops/ | 承诺、未完成事项、需要回访的问题 |
| 总结 | summary | wiki/summaries/ | 周期性或主题性综合文字 |

## 抽取规则

- 前端不使用 entity/concept 术语。
- 内部可以把人物、项目视为 entity，把主题、偏好、待办视为 concept。
- 每个页面必须保留 sources，指向相关日记日期。
- 不确定的信息写入待办或问题，不写成事实。
- 敏感信息只保留必要摘要。
```

- [ ] **步骤 4: 让旧 KnowledgeOntologyProjectExporter 转调新 exporter**

在 `KnowledgeOntologyProjectExporter.syncDiaries` 中调用：

```swift
let result = try MyWikiProjectExporter(fileManager: fileManager).syncDiaries(
    sourceVault: sourceVault,
    projectRoot: projectRoot
)
return KnowledgeOntologySyncResult(
    projectRoot: result.projectRoot,
    exportedFileNames: result.exportedFileNames
)
```

旧类型先保留，避免一次性改动所有 UI。

- [ ] **步骤 5: 更新 Xcode project 文件**

把 `MyWikiProjectExporter.swift` 和 `MyWikiProjectExporterTests.swift` 加入 `KnowYou.xcodeproj/project.pbxproj` 对应 target。

- [ ] **步骤 6: 运行测试确认通过**

运行：

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/MyWikiProjectExporterTests -only-testing:KnowYouTests/KnowledgeOntologyProjectExporterTests
```

预期： 通过。

- [ ] **步骤 7: 提交本任务**

```bash
git add KnowYou/Services/MyWiki/MyWikiProjectExporter.swift KnowYou/Services/KnowledgeOntology/KnowledgeOntologyProjectExporter.swift KnowYouTests/MyWikiProjectExporterTests.swift KnowYouTests/KnowledgeOntologyProjectExporterTests.swift KnowYou.xcodeproj/project.pbxproj
git commit -m "feat: add My Wiki project exporter"
```

提交后停止，不要 push。

---

## 任务 3: 新建 My Wiki markdown 读取层

**文件：**
- 新增：`KnowYou/UI/MyWiki/MyWikiModels.swift`
- 新增：`KnowYou/Services/MyWiki/MyWikiMarkdownStore.swift`
- 新增：`KnowYouTests/MyWikiMarkdownStoreTests.swift`
- 修改：`KnowYou.xcodeproj/project.pbxproj`

- [ ] **步骤 1: 写失败测试，读取 people/projects/themes/summaries**

创建 `KnowYouTests/MyWikiMarkdownStoreTests.swift`：

```swift
import XCTest
@testable import KnowYou

final class MyWikiMarkdownStoreTests: XCTestCase {
    func testLoadsDashboardSnapshotFromMarkdownFolders() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: root.appending(path: "wiki/people"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appending(path: "wiki/projects"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appending(path: "wiki/themes"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appending(path: "wiki/summaries"), withIntermediateDirectories: true)

        try """
        ---
        type: person
        title: Alex
        sources: ["knowyou-diary-2026-05-12.md"]
        ---

        # Alex

        最近一起讨论 My Wiki 的产品轻量化。
        """.write(to: root.appending(path: "wiki/people/alex.md"), atomically: true, encoding: .utf8)

        try """
        ---
        type: project
        title: KnowYou
        sources: ["knowyou-diary-2026-05-12.md"]
        ---

        # KnowYou

        从日记工具升级为个人 My Wiki。
        """.write(to: root.appending(path: "wiki/projects/knowyou.md"), atomically: true, encoding: .utf8)

        let snapshot = try MyWikiMarkdownStore(fileManager: .default).loadDashboard(projectRoot: root)

        XCTAssertEqual(snapshot.people.map(\\.title), ["Alex"])
        XCTAssertEqual(snapshot.projects.map(\\.title), ["KnowYou"])
        XCTAssertTrue(snapshot.people[0].summary.contains("产品轻量化"))
        XCTAssertEqual(snapshot.people[0].sourceNames, ["knowyou-diary-2026-05-12.md"])
    }
}
```

- [ ] **步骤 2: 运行测试确认失败**

运行：

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/MyWikiMarkdownStoreTests
```

预期： 失败，models/store 尚不存在。

- [ ] **步骤 3: 创建展示模型**

在 `MyWikiModels.swift` 定义：

```swift
struct MyWikiDashboardSnapshot: Equatable {
    var summaries: [MyWikiEntry]
    var people: [MyWikiEntry]
    var projects: [MyWikiEntry]
    var themes: [MyWikiEntry]
    var preferences: [MyWikiEntry]
    var openLoops: [MyWikiEntry]
}

struct MyWikiEntry: Identifiable, Equatable {
    let id: String
    let title: String
    let category: MyWikiCategory
    let summary: String
    let sourceNames: [String]
}

enum MyWikiCategory: String, CaseIterable, Equatable {
    case summary
    case person
    case project
    case theme
    case preference
    case openLoop
}
```

- [ ] **步骤 4: 实现 MyWikiMarkdownStore**

`MyWikiMarkdownStore.loadDashboard(projectRoot:)` 从固定目录读取 markdown：

```swift
let folders: [(MyWikiCategory, String)] = [
    (.summary, "wiki/summaries"),
    (.person, "wiki/people"),
    (.project, "wiki/projects"),
    (.theme, "wiki/themes"),
    (.preference, "wiki/preferences"),
    (.openLoop, "wiki/open-loops")
]
```

解析规则：

- `title:` 从 frontmatter 读取；没有则用文件名转标题。
- `sources:` 从 frontmatter 读取字符串数组；解析失败时返回空数组。
- `summary` 使用正文去掉一级标题后的前 240 个字符。
- 每个列表按标题升序。

- [ ] **步骤 5: 运行测试确认通过**

运行：

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/MyWikiMarkdownStoreTests
```

预期： 通过。

- [ ] **步骤 6: 提交本任务**

```bash
git add KnowYou/UI/MyWiki/MyWikiModels.swift KnowYou/Services/MyWiki/MyWikiMarkdownStore.swift KnowYouTests/MyWikiMarkdownStoreTests.swift KnowYou.xcodeproj/project.pbxproj
git commit -m "feat: load My Wiki markdown dashboard"
```

提交后停止，不要 push。

---

## 任务 4: 实现轻量 My Wiki 首页 UI

**文件：**
- 新增：`KnowYou/UI/MyWiki/MyWikiPanel.swift`
- 新增：`KnowYou/UI/MyWiki/MyWikiDetailView.swift`
- 修改：`KnowYou/UI/KnowledgeOntology/KnowledgeOntologyPanel.swift`
- 修改：`KnowYou/UI/MainWindowView.swift`
- 修改：`KnowYou.xcodeproj/project.pbxproj`

- [ ] **步骤 1: 写快照级 presentation 测试**

在 `KnowYouTests/KnowledgeOntologyPanelTests.swift` 增加纯模型测试：

```swift
func testMyWikiCategoryLabelsAreUserFacing() {
    XCTAssertEqual(MyWikiCategory.person.displayTitle, "人物")
    XCTAssertEqual(MyWikiCategory.project.displayTitle, "项目")
    XCTAssertEqual(MyWikiCategory.theme.displayTitle, "主题")
    XCTAssertEqual(MyWikiCategory.preference.displayTitle, "偏好")
    XCTAssertEqual(MyWikiCategory.openLoop.displayTitle, "待办")
    XCTAssertEqual(MyWikiCategory.summary.displayTitle, "总结")
}
```

- [ ] **步骤 2: 运行测试确认失败**

运行：

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/KnowledgeOntologyPanelTests/testMyWikiCategoryLabelsAreUserFacing
```

预期： 失败，`displayTitle` 尚不存在。

- [ ] **步骤 3: 给 MyWikiCategory 增加 displayTitle**

在 `MyWikiModels.swift` 增加：

```swift
extension MyWikiCategory {
    var displayTitle: String {
        switch self {
        case .summary: return "总结"
        case .person: return "人物"
        case .project: return "项目"
        case .theme: return "主题"
        case .preference: return "偏好"
        case .openLoop: return "待办"
        }
    }
}
```

- [ ] **步骤 4: 创建 MyWikiPanel**

`MyWikiPanel` 首屏结构：

```swift
VStack(alignment: .leading, spacing: 20) {
    Text("My Wiki")
    TextField("问问你的 My Wiki...", text: $query)
    MyWikiSummarySection(entries: snapshot.summaries)
    MyWikiCategorySection(title: "人物", entries: snapshot.people)
    MyWikiCategorySection(title: "项目", entries: snapshot.projects)
    MyWikiCategorySection(title: "主题", entries: snapshot.themes)
    MyWikiCategorySection(title: "偏好", entries: snapshot.preferences)
    MyWikiCategorySection(title: "待办", entries: snapshot.openLoops)
}
```

视觉要求：

- 黑色背景。
- 不出现 `知识本体`、`ontology`、`entity`、`concept`。
- 不出现 graph/review/lint/deep research 作为主按钮。
- 同步动作可以保留，但文案为 `整理日记`。

- [ ] **步骤 5: 让旧 KnowledgeOntologyPanel 转调 MyWikiPanel**

保留旧 struct 名称，body 改成：

```swift
MyWikiPanel(
    sourceVault: sourceVault,
    projectRoot: projectRoot,
    developmentSourceURL: developmentSourceURL,
    bundledHelperAppURL: bundledHelperAppURL
)
```

这样现有 `MainWindowView` 暂时不用一次性全改。

- [ ] **步骤 6: 运行测试**

运行：

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/KnowledgeOntologyPanelTests
```

预期： 通过。

- [ ] **步骤 7: 提交本任务**

```bash
git add KnowYou/UI/MyWiki/MyWikiPanel.swift KnowYou/UI/MyWiki/MyWikiDetailView.swift KnowYou/UI/KnowledgeOntology/KnowledgeOntologyPanel.swift KnowYou/UI/MainWindowView.swift KnowYou/UI/MyWiki/MyWikiModels.swift KnowYouTests/KnowledgeOntologyPanelTests.swift KnowYou.xcodeproj/project.pbxproj
git commit -m "feat: add lightweight My Wiki dashboard"
```

提交后停止，不要 push。

---

## 任务 5: 接入 llm_wiki pipeline bridge

**文件：**
- 新增：`KnowYou/Services/MyWiki/MyWikiPipelineBridge.swift`
- 新增：`KnowYouTests/MyWikiPipelineBridgeTests.swift`
- 修改：`KnowYou/UI/MyWiki/MyWikiPanel.swift`
- 修改：`KnowYou.xcodeproj/project.pbxproj`

- [ ] **步骤 1: 写失败测试，确认 bridge 选择 helper/dev source**

创建 `KnowYouTests/MyWikiPipelineBridgeTests.swift`：

```swift
import XCTest
@testable import KnowYou

final class MyWikiPipelineBridgeTests: XCTestCase {
    func testResolvePipelineUsesDevelopmentSourceWhenHelperMissing() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        let dev = root.appending(path: "ThirdParty/llm_wiki", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dev, withIntermediateDirectories: true)

        let target = MyWikiPipelineBridge.resolveTarget(
            bundledHelperAppURL: nil,
            developmentSourceURL: dev
        )

        XCTAssertEqual(target.statusDescription, "Using development llm_wiki pipeline: \(dev.path)")
    }
}
```

- [ ] **步骤 2: 运行测试确认失败**

运行：

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/MyWikiPipelineBridgeTests
```

预期： 失败，bridge 尚不存在。

- [ ] **步骤 3: 实现 MyWikiPipelineBridge**

第一版只封装目标选择和 launch，不重新实现 ingest：

```swift
enum MyWikiPipelineTarget: Equatable {
    case bundledHelper(URL)
    case developmentSource(URL)
    case missing
}

struct MyWikiPipelineBridge {
    static func resolveTarget(bundledHelperAppURL: URL?, developmentSourceURL: URL) -> MyWikiPipelineTarget
    func runIngest(target: MyWikiPipelineTarget, projectRoot: URL) throws
    func openAdvancedWorkspace(target: MyWikiPipelineTarget, projectRoot: URL) throws
}
```

`runIngest` 第一版可以调用现有 helper/dev source 的启动能力，并把状态回传给 UI；如果没有 helper，返回明确错误：

```swift
throw MyWikiPipelineBridgeError.missingPipeline
```

- [ ] **步骤 4: MyWikiPanel 使用 bridge**

把按钮改成：

- `整理日记`：先 `MyWikiProjectExporter.syncDiaries`，再尝试 `MyWikiPipelineBridge.runIngest`。
- `打开高级工作台`：放在次要位置，用于调试或高级使用。

- [ ] **步骤 5: 运行测试确认通过**

运行：

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/MyWikiPipelineBridgeTests
```

预期： 通过。

- [ ] **步骤 6: 提交本任务**

```bash
git add KnowYou/Services/MyWiki/MyWikiPipelineBridge.swift KnowYou/UI/MyWiki/MyWikiPanel.swift KnowYouTests/MyWikiPipelineBridgeTests.swift KnowYou.xcodeproj/project.pbxproj
git commit -m "feat: bridge My Wiki to llm_wiki pipeline"
```

提交后停止，不要 push。

---

## 任务 6: 增加 agent context provider

**文件：**
- 新增：`KnowYou/Services/MyWiki/MyWikiAgentContextProvider.swift`
- 新增：`KnowYouTests/MyWikiAgentContextProviderTests.swift`
- 修改：`KnowYou.xcodeproj/project.pbxproj`

- [ ] **步骤 1: 写失败测试，生成最小必要 agent brief**

创建 `KnowYouTests/MyWikiAgentContextProviderTests.swift`：

```swift
import XCTest
@testable import KnowYou

final class MyWikiAgentContextProviderTests: XCTestCase {
    func testBuildsAgentBriefFromProjectsThemesAndPreferences() {
        let snapshot = MyWikiDashboardSnapshot(
            summaries: [],
            people: [],
            projects: [
                MyWikiEntry(id: "knowyou", title: "KnowYou", category: .project, summary: "从日记工具升级为 My Wiki。", sourceNames: ["knowyou-diary-2026-05-12.md"])
            ],
            themes: [
                MyWikiEntry(id: "lightweight-ui", title: "轻量 UI", category: .theme, summary: "用户不希望看到复杂图谱。", sourceNames: ["knowyou-diary-2026-05-12.md"])
            ],
            preferences: [
                MyWikiEntry(id: "plain-language", title: "普通语言", category: .preference, summary: "前端不要暴露 entity/concept。", sourceNames: ["knowyou-diary-2026-05-12.md"])
            ],
            openLoops: []
        )

        let brief = MyWikiAgentContextProvider().brief(from: snapshot, maxItemsPerCategory: 2)

        XCTAssertTrue(brief.contains("KnowYou"))
        XCTAssertTrue(brief.contains("轻量 UI"))
        XCTAssertTrue(brief.contains("普通语言"))
        XCTAssertTrue(brief.contains("来源：knowyou-diary-2026-05-12.md"))
        XCTAssertFalse(brief.contains("entity"))
        XCTAssertFalse(brief.contains("concept"))
    }
}
```

- [ ] **步骤 2: 运行测试确认失败**

运行：

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/MyWikiAgentContextProviderTests
```

预期： 失败，provider 尚不存在。

- [ ] **步骤 3: 实现 provider**

`brief(from:maxItemsPerCategory:)` 输出中文 markdown：

```markdown
# My Wiki Agent Brief

## 项目
- KnowYou：从日记工具升级为 My Wiki。
  来源：knowyou-diary-2026-05-12.md

## 主题
- 轻量 UI：用户不希望看到复杂图谱。
  来源：knowyou-diary-2026-05-12.md

## 偏好
- 普通语言：前端不要暴露 entity/concept。
  来源：knowyou-diary-2026-05-12.md
```

规则：

- 只输出非空分类。
- 每类最多 `maxItemsPerCategory` 条。
- 没有来源时写 `来源：My Wiki`。

- [ ] **步骤 4: 运行测试确认通过**

运行：

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/MyWikiAgentContextProviderTests
```

预期： 通过。

- [ ] **步骤 5: 提交本任务**

```bash
git add KnowYou/Services/MyWiki/MyWikiAgentContextProvider.swift KnowYouTests/MyWikiAgentContextProviderTests.swift KnowYou.xcodeproj/project.pbxproj
git commit -m "feat: add My Wiki agent brief provider"
```

提交后停止，不要 push。

---

## 任务 7: 文档同步与旧术语清理

**文件：**
- 修改：`docs/architecture.md`
- 修改：`docs/requirements-spec.md`
- 修改：`docs/superpowers/specs/2026-05-12-my-wiki-redesign.md`

- [ ] **步骤 1: 搜索旧术语**

运行：

```bash
rg -n "知识本体|KnowledgeOntology|ontology|entity|concept|graph|review|lint|deep research" docs KnowYou KnowYouTests
```

预期： 只允许内部实现、兼容层、历史 spec 中出现旧术语；用户可见文案不应出现。

- [ ] **步骤 2: 更新 architecture**

在 `docs/architecture.md` 中新增或替换章节：

```markdown
## My Wiki 子系统

My Wiki 是 KnowYou 左侧栏中的功能入口，不是独立产品名。它把已生成的日记 Markdown 同步到 llm_wiki 兼容项目，并继承 llm_wiki 的 ingest、cache、page merge、search 和 vector store pipeline。

普通用户看到的是总结、人物、项目、主题、偏好、待办和搜索。图谱、review、lint、deep research 不作为主界面能力，只保留在底层或高级工作台中。
```

- [ ] **步骤 3: 更新 requirements**

在 `docs/requirements-spec.md` 中把 `知识本体需求` 改为 `My Wiki 需求`：

```markdown
## My Wiki 需求

- 主窗口左侧栏必须提供 `My Wiki` 入口。
- `My Wiki` 是 KnowYou 的功能入口，不是独立产品名。
- 用户进入后必须先看到搜索、总结和核心脉络。
- 核心脉络必须使用人物、项目、主题、偏好、待办、反复出现的问题等用户语言。
- 第一版不得把 graph、review、lint、deep research 作为普通用户主按钮。
- 后端必须尽量继承 llm_wiki 的 ingest/cache/search/page merge/vector store。
- 第一版只能导出 KnowYou 已生成的每日 Markdown，不得直接导出未经额外授权的 SQLite 原始事件。
```

- [ ] **步骤 4: 运行文档检查**

运行：

```bash
rg -n "知识本体" docs/architecture.md docs/requirements-spec.md KnowYou/UI
```

预期： 无输出，或只在历史说明中明确标记为旧称。

- [ ] **步骤 5: 提交本任务**

```bash
git add docs/architecture.md docs/requirements-spec.md docs/superpowers/specs/2026-05-12-my-wiki-redesign.md
git commit -m "docs: define My Wiki product direction"
```

提交后停止，不要 push。

---

## 任务 8: 完整验证与 GUI 检查

**文件：**
- 除非验证发现 bug，否则不修改源码。

- [ ] **步骤 1: 运行 定向测试**

运行：

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/MyWikiProjectExporterTests -only-testing:KnowYouTests/MyWikiMarkdownStoreTests -only-testing:KnowYouTests/MyWikiAgentContextProviderTests -only-testing:KnowYouTests/MyWikiPipelineBridgeTests
```

预期： 通过。

- [ ] **步骤 2: 运行 全量测试**

运行：

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS'
```

预期： 通过。

- [ ] **步骤 3: 构建 app**

运行：

```bash
xcodebuild build -scheme KnowYou -destination 'platform=macOS'
```

预期： `** BUILD SUCCEEDED **`。

- [ ] **步骤 4: 打开 刚构建的 app**

使用当前 session 的 DerivedData Debug app，关闭旧进程后打开：

```bash
pkill -x KnowYou 2>/dev/null || true
open -n "$HOME/Library/Developer/Xcode/DerivedData/KnowYou-fatlnhtsvlrhqvakbxuwgjysmxkn/Build/Products/Debug/KnowYou.app"
```

- [ ] **步骤 5: GUI 检查**

用 Computer Use 检查：

- 左侧栏存在 `My Wiki`。
- 点击后页面标题为 `My Wiki`。
- 首屏包含搜索框、总结、人物、项目、主题、偏好、待办。
- 首屏不出现 `知识本体`、`entity`、`concept`、`graph`、`review`、`lint`、`deep research`。

- [ ] **步骤 6: 最终状态检查**

运行：

```bash
git status --short --branch
```

预期： 当前分支比远端 ahead，本地干净。

停止并请用户测试，不要 push。

---

## 自查

- 覆盖了 spec 中的命名边界：KnowYou 是产品名，`My Wiki` 是侧边栏入口和功能区。
- 覆盖了后端继承方向：ingest/cache/search/page merge/vector store 继续来自 llm_wiki。
- 覆盖了前端变轻方向：首页是搜索、总结、核心脉络，不是复杂 graph workspace。
- 覆盖了 agent 调用方向：新增 My Wiki agent brief provider。
- 覆盖了隐私边界：第一版只导出已生成日记 Markdown。
- 没有要求实现网络 API，避免第一版范围过大。
- 每个任务都有测试、运行命令、预期结果和本地提交步骤。
- 所有提交步骤都明确 `不要 push`，符合项目 push 策略。
