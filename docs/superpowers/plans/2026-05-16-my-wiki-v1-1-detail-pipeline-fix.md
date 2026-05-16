# My Wiki v1.1 Detail Pipeline Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复 My Wiki v1 当前详情与 pipeline 展示问题，让 app 当前目录显示正式 LLM Wiki 结果，而不是 starter 占位页面；同时支持用户先看部分处理结果，并在左侧显示紧凑 source 处理进度。

**Architecture:** Swift 读取层负责过滤旧 starter 页面、提炼可读 summary、解析 source/related 目标；SwiftUI 只负责展示和触发导航；正式内容仍由 `ThirdParty/llm_wiki` headless pipeline 生成。

**Tech Stack:** Swift 6、SwiftUI、XCTest、LLM Wiki TypeScript headless pipeline、Codex CLI provider。

---

### Task 1: 读取层 summary 与 starter 过滤

**Files:**
- Modify: `KnowYou/Services/MyWiki/MyWikiMarkdownStore.swift`
- Modify: `KnowYouTests/MyWikiMarkdownStoreTests.swift`

- [x] **Step 1: 写失败测试**

新增测试：

```swift
func testLoadDashboardUsesDescriptionFrontmatterAsSummary() throws
func testLoadDashboardUsesSummarySectionBeforeBodyFallback() throws
func testLoadDashboardFallsBackToFirstBodyParagraph() throws
func testLoadDashboardSkipsStarterExtractorPages() throws
```

断言：

- `description: "A real semantic summary."` 时 entry.summary 等于该 description。
- body 有 `## Summary` 时只取 Summary section，不包含 `## Recent Mentions`。
- 无 description/summary section 时，跳过 `# Title` 并取第一段正文。
- `generated_by: KnowYou My Wiki starter extractor` 的页面不出现在 snapshot。

- [x] **Step 2: 运行测试确认失败**

Run:

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/MyWikiMarkdownStoreTests
```

Expected: 新测试失败，因为当前 summary 只截取 body，且 starter 页面仍会加载。

- [x] **Step 3: 实现最小代码**

在 `MyWikiMarkdownStore.loadEntry` 中：

```swift
summary: Self.summary(from: parsed.body, frontmatter: parsed.frontmatter)
```

新增/替换 helper：

```swift
private static func summary(from body: String, frontmatter: [String: String]) -> String
private static func section(named name: String, from body: String) -> String?
private static func firstBodyParagraph(from body: String) -> String
```

在 `shouldLoad` 里如果 `generated_by` 包含 `starter extractor`，直接返回 false。

- [x] **Step 4: 运行测试确认通过**

Run 同 Step 2。

### Task 2: Source / Related resolver

**Files:**
- Create: `KnowYou/Services/MyWiki/MyWikiNavigationResolver.swift`
- Create: `KnowYouTests/MyWikiNavigationResolverTests.swift`
- Modify: `KnowYou.xcodeproj/project.pbxproj`

- [x] **Step 1: 写失败测试**

新增测试：

```swift
func testResolveSourcePrefersWikiSourceSummaryForMarkdown()
func testResolveSourceFallsBackToRawSources()
func testResolveRelatedEntryFindsEntryByID()
func testResolveRelatedEntryFindsEntryByTitleSlug()
```

- [x] **Step 2: 运行测试确认失败**

Run:

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/MyWikiNavigationResolverTests
```

Expected: 编译失败，因为 resolver 还不存在。

- [x] **Step 3: 实现 resolver**

实现：

```swift
struct MyWikiNavigationResolver {
    func resolveSourceURL(_ sourceName: String, projectRoot: URL) -> URL?
    func resolveRelatedEntry(_ reference: String, snapshot: MyWikiDashboardSnapshot) -> MyWikiEntry?
}
```

规则：

- `wiki/sources/foo.md` 或 `raw/sources/foo.md` 这类路径直接按 project root 拼接并检查存在。
- `foo.md` 优先 `wiki/sources/foo.md`，再 `raw/sources/foo.md`。
- related 支持 `[[slug]]`、`[[slug|label]]`、`slug.md`、`wiki/projects/slug.md`、裸 slug。

- [x] **Step 4: 运行测试确认通过**

Run 同 Step 2。

### Task 3: SwiftUI 详情交互

**Files:**
- Modify: `KnowYou/UI/MyWiki/MyWikiPanel.swift`
- Modify: `KnowYou/UI/MyWiki/MyWikiDetailView.swift`
- Modify: `KnowYouTests/KnowledgeOntologyPanelTests.swift` 或相关 My Wiki UI presentation tests

- [x] **Step 1: 写失败测试**

增加轻量 presentation/policy 测试，覆盖：

```swift
func testDetailPresentationDoesNotShowMarkdownPageByDefault()
func testIndexRowUsesFullWidthHitTargetPolicy()
```

- [x] **Step 2: 运行测试确认失败**

Run:

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/KnowledgeOntologyPanelTests
```

- [x] **Step 3: 实现 UI**

- `MyWikiIndexRow` 增加整行命中区域。
- `MyWikiDetailView` 删除默认 `Markdown Page` card。
- `sourceList` 改为 Button 列表，通过 `onOpenSource(sourceName)` 回调。
- `Related` chips 改为 Button，通过 `onOpenRelated(reference)` 回调。
- `MyWikiPanel` 用 `MyWikiNavigationResolver` 实现两个回调。

- [x] **Step 4: 运行测试确认通过**

Run 同 Step 2，并补跑 MyWiki 相关 targeted tests。

### Task 4: 当前 app 项目目录跑正式 pipeline

**Files:**
- No repo file changes.
- Runtime project: `~/Library/Application Support/KnowYou/KnowledgeOntology/KnowYouContext`

- [x] **Step 1: 确认当前 app 项目目录状态**

Run:

```bash
cat "$HOME/Library/Application Support/KnowYou/KnowledgeOntology/KnowYouContext/.llm-wiki/last-ingest-status.json"
find "$HOME/Library/Application Support/KnowYou/KnowledgeOntology/KnowYouContext/wiki/people" -maxdepth 1 -name '*.md' | wc -l
```

- [x] **Step 2: 运行正式 LLM Wiki ingest**

Run:

```bash
npm run knowyou:ingest -- --project "$HOME/Library/Application Support/KnowYou/KnowledgeOntology/KnowYouContext" --provider codex-cli --model gpt-5.5
```

Expected: status succeeded；如果失败，记录失败，不写 starter fallback。

- [x] **Step 3: 抽样检查**

检查：

```bash
cat "$HOME/Library/Application Support/KnowYou/KnowledgeOntology/KnowYouContext/.llm-wiki/last-ingest-status.json"
find "$HOME/Library/Application Support/KnowYou/KnowledgeOntology/KnowYouContext/wiki/people" -maxdepth 1 -name '*.md' | wc -l
rg -n "appears as a real person|starter extractor" "$HOME/Library/Application Support/KnowYou/KnowledgeOntology/KnowYouContext/wiki/people" || true
```

### Task 5: 紧凑 ingest 进度

**Files:**
- Create: `KnowYou/Services/MyWiki/MyWikiIngestProgressStore.swift`
- Create: `KnowYouTests/MyWikiIngestProgressStoreTests.swift`
- Modify: `KnowYou/UI/MyWiki/MyWikiPanel.swift`
- Modify: `KnowYou.xcodeproj/project.pbxproj`

- [x] **Step 1: 写失败测试**

新增测试：

```swift
func testLoadProgressCountsRawSources()
func testStoppedPreviewFailureDisplaysPreviewGenerated()
func testSucceededProgressUsesAllSourcesWhenProcessedCountMissing()
```

断言：

- `.llm-wiki/last-ingest-status.json` 中 `sourcesProcessed: 23`，`raw/sources` 有 36 个 markdown 时，进度为 `23/36 sources`。
- 当状态为 `failed` 但 message 包含 `Stopped for preview` 时，用户可见标题是 `Preview generated`，而不是吓人的 `Failed`。
- `succeeded` 且没有 `sourcesProcessed` 时，默认处理数等于 source 总数。

- [x] **Step 2: 运行测试确认失败**

Run:

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/MyWikiIngestProgressStoreTests
```

- [x] **Step 3: 实现最小代码**

实现 `MyWikiIngestProgressStore`：

- 读取 `projectRoot/.llm-wiki/last-ingest-status.json`。
- 统计 `projectRoot/raw/sources/*.md`。
- 输出 `state`、`title`、`detail`、`fraction`。

在 `MyWikiPanel` 搜索框下方显示一条轻量进度条：

- `Processing sources`
- `Preview generated`
- `Updated`
- `Needs attention`

注意：不要把单个 entity 详情里的 `Sources (5)` 当成全局进度。前者是证据数量，后者是 pipeline source 队列状态。

- [x] **Step 4: 运行测试确认通过**

Run 同 Step 2。

### Task 6: Source 管理入口与轻量导入

**Files:**
- Create: `KnowYou/Services/MyWiki/MyWikiSourceLibrary.swift`
- Create: `KnowYou/UI/MyWiki/MyWikiSourceLibraryView.swift`
- Create: `KnowYouTests/MyWikiSourceLibraryTests.swift`
- Modify: `KnowYou/UI/MyWiki/MyWikiPanel.swift`
- Modify: `KnowYou/UI/MyWiki/MyWikiDetailView.swift`
- Modify: `KnowYouTests/KnowledgeOntologyPanelTests.swift`
- Modify: `KnowYou.xcodeproj/project.pbxproj`
- Modify: `docs/superpowers/specs/2026-05-16-my-wiki-v1-1-detail-pipeline-fix.md`
- Modify: `docs/superpowers/plans/2026-05-16-my-wiki-v1-1-detail-pipeline-fix.md`

- [x] **Step 1: 记录产品设计**

把 source 指定设计写入规格：

- `Choose Folder`：指定日记/素材文件夹。
- `Drag files here`：手动拖入文件。
- Source 状态：`Pending`、`Processing`、`Indexed`、`Failed`、`Needs review`。
- 全局进度来自 source 队列；entity `Sources` 来自 evidence。

- [x] **Step 2: 写失败测试**

新增测试：

```swift
func testImportFilesCopiesSupportedFilesIntoRawSources()
func testImportFolderImportsSupportedTopLevelFiles()
func testImportFilesDoesNotOverwriteExistingSource()
func testLoadSourcesMarksFilesWithGeneratedSummaryAsIndexed()
```

- [x] **Step 3: 实现轻量 Source Library**

实现：

- `Source Library` sheet。
- `Choose Folder` 导入所选目录第一层 `.md`、`.markdown`、`.txt`。
- `Import Files` 支持多选导入。
- 拖拽导入同类文件。
- 导入复制到 `raw/sources`，同名文件自动加后缀，不覆盖。
- 列表显示 `Pending` / `Indexed`，有 source summary 时可直接打开。

- [x] **Step 4: 运行测试确认通过**

Run:

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/MyWikiSourceLibraryTests -only-testing:KnowYouTests/KnowledgeOntologyPanelTests/testDetailMoreMenuIncludesSourceManagementAction
```

Expected: 通过。

### Task 7: 验证与打开 app

**Files:**
- Modify: `KnowYou/KnowYouApp.swift`
- Modify: `KnowYou.xcodeproj/project.pbxproj`
- Delete: `KnowYou/Services/MyWiki/MyWikiStarterExtractor.swift`
- Delete: `KnowYouTests/MyWikiStarterExtractorTests.swift`
- Modify: `docs/architecture.md`
- Modify: `docs/requirements-spec.md`

- [x] **Step 0: 移除旧 starter 生成路径**

删除旧 `MyWikiStarterExtractor` 和对应测试 target 引用。读取层仍保留对历史 `generated_by: KnowYou My Wiki starter extractor` 页面过滤的测试，确保旧数据不再污染正式 My Wiki。

- [x] **Step 1: 运行 targeted tests**

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/MyWikiMarkdownStoreTests -only-testing:KnowYouTests/MyWikiNavigationResolverTests -only-testing:KnowYouTests/KnowledgeOntologyPanelTests
```

另补：

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/MyWikiIngestProgressStoreTests
```

- [x] **Step 2: build**

```bash
xcodebuild build -scheme KnowYou -destination 'platform=macOS' -derivedDataPath /tmp/know-you-my-wiki-redesign-derived
```

- [x] **Step 3: 打开 freshly built app**

```bash
pkill -x KnowYou || true
open -n /tmp/know-you-my-wiki-redesign-derived/Build/Products/Debug/KnowYou.app
```

- [x] **Step 4: GUI/窗口验证**

确认：

- My Wiki 左侧入口存在。
- 点击条目空白区域能选中。
- `Adam` 不再显示 starter 占位 summary。
- 详情页没有 `Markdown Page` card。
- Source 和 Related 是可点击控件。

当前桌面处于 macOS 锁屏状态，Computer Use 无法取得 app accessibility tree；本轮完成的可验证证据是 `scripts/run-dev-app.sh` 构建并启动 fresh app，`CGWindowListCopyWindowInfo` 返回 1 个 onscreen `KnowYou` 主窗口。UI 行为由 targeted Swift 测试覆盖，解锁后仍建议人工点一遍 My Wiki。

## Self Review

- Spec 覆盖：本计划覆盖点击区域、summary、starter 过滤、Source/Related 导航、当前 app pipeline 五个问题。
- Placeholder scan：没有 TBD/TODO。
- 类型一致性：新增 resolver 与现有 `MyWikiEntry`、`MyWikiDashboardSnapshot` 对齐。
