# Global Diary Prompt Editor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在主窗口右上角新增全局 diary prompt 编辑入口，支持查看系统默认 prompt、编辑并应用全局自定义 prompt、恢复默认，并明确只影响后续生成结果而不自动改写旧内容。

**Architecture:** 以 `SummarizerConfig` 为当前持久化边界，先把全局 prompt override 纳入同一配置模型，再让 `DailyMarkdownComposer` 提供 canonical 默认 prompt 构造与 override 合并入口，最后在 `MainWindowView` 增加独立 `Edit Prompt` 按钮和 sheet。UI 不直接拼 prompt 模板，只展示 composer 生成的默认 prompt，并通过 `AppState` 管理当前生效值。

**Tech Stack:** Swift, SwiftUI, XCTest, UserDefaults, 现有 `AppState` / `SummarizerConfig` / `DailyMarkdownComposer`

---

## 文件结构

- 修改 `KnowYou/Services/Summary/SummarizerConfig.swift`
  - 为全局 prompt override 增加持久化字段、读写逻辑和默认状态访问点。
- 修改 `KnowYou/Services/Composer/DailyMarkdownComposer.swift`
  - 抽出 canonical 默认 prompt 构造；提供接收 override 后返回最终 prompt 的入口。
- 新增 `KnowYou/UI/Reader/DiaryPromptEditorSheet.swift`
  - 承载默认 prompt 预览、自定义编辑、Apply / Restore Default 操作和“只影响后续生成”的说明。
- 修改 `KnowYou/UI/MainWindowView.swift`
  - 在右上角 toolbar 增加 `Edit Prompt` 按钮与新 sheet。
- 修改 `KnowYou/App/AppState.swift`
  - 持有当前 prompt draft / active override 所需状态，提供 apply / restore 接口。
- 修改 `KnowYouTests/SummarizerConfigTests.swift`
  - 覆盖 prompt override 持久化。
- 修改 `KnowYouTests/DailyMarkdownComposerTests.swift`
  - 覆盖默认 prompt 与 override prompt 行为。
- 修改 `KnowYouTests/MainWindowViewModelTests.swift`
  - 覆盖 app state 的 apply / restore 语义，特别是不自动重生成旧内容。

---

### Task 1: 为全局 Prompt Override 建立持久化配置

**Files:**
- Modify: `KnowYou/Services/Summary/SummarizerConfig.swift`
- Test: `KnowYouTests/SummarizerConfigTests.swift`

- [ ] **Step 1: 先写失败测试，锁定 prompt override 的默认值、保存、恢复默认**

```swift
func testLoadDefaultsToNoGlobalDiaryPromptOverride() {
    let config = SummarizerConfig.load(from: defaults, keychain: keychain, keychainService: "tests")
    XCTAssertNil(config.globalDiaryPromptOverride)
    XCTAssertFalse(config.hasCustomGlobalDiaryPrompt)
}

func testSaveAndLoadRoundTripsGlobalDiaryPromptOverride() {
    var config = SummarizerConfig.load(from: defaults, keychain: keychain, keychainService: "tests")
    config.globalDiaryPromptOverride = "Custom diary prompt"
    config.save(to: defaults, keychain: keychain, keychainService: "tests")

    let loaded = SummarizerConfig.load(from: defaults, keychain: keychain, keychainService: "tests")
    XCTAssertEqual(loaded.globalDiaryPromptOverride, "Custom diary prompt")
    XCTAssertTrue(loaded.hasCustomGlobalDiaryPrompt)
}

func testSaveAndLoadClearsGlobalDiaryPromptOverrideWhenRestoredToDefault() {
    var config = SummarizerConfig.load(from: defaults, keychain: keychain, keychainService: "tests")
    config.globalDiaryPromptOverride = "Custom diary prompt"
    config.save(to: defaults, keychain: keychain, keychainService: "tests")

    var restored = SummarizerConfig.load(from: defaults, keychain: keychain, keychainService: "tests")
    restored.globalDiaryPromptOverride = nil
    restored.save(to: defaults, keychain: keychain, keychainService: "tests")

    let loaded = SummarizerConfig.load(from: defaults, keychain: keychain, keychainService: "tests")
    XCTAssertNil(loaded.globalDiaryPromptOverride)
    XCTAssertFalse(loaded.hasCustomGlobalDiaryPrompt)
}
```

- [ ] **Step 2: 运行测试，确认因缺少字段和逻辑而失败**

Run:

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/SummarizerConfigTests
```

Expected: `SummarizerConfig` 缺少 `globalDiaryPromptOverride` / `hasCustomGlobalDiaryPrompt`，测试编译失败或断言失败。

- [ ] **Step 3: 最小实现配置模型和持久化**

```swift
struct SummarizerConfig {
    var defaultEngine: DiaryEngine
    var claudeCLIPath: String
    var codexCLIPath: String
    var geminiCLIPath: String
    var openclawCLIPath: String
    var apiBaseURL: String
    var apiModel: String
    var apiToken: String
    var globalDiaryPromptOverride: String?

    var hasCustomGlobalDiaryPrompt: Bool {
        guard let override = globalDiaryPromptOverride else { return false }
        return !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private enum Keys {
        static let globalDiaryPromptOverride = "globalDiaryPromptOverride"
    }

    func save(
        to defaults: UserDefaults = .standard,
        keychain: KeychainStoring = KeychainHelper.shared,
        keychainService: String = KeychainHelper.service
    ) {
        if let override = globalDiaryPromptOverride?.trimmingCharacters(in: .whitespacesAndNewlines), !override.isEmpty {
            defaults.set(override, forKey: Keys.globalDiaryPromptOverride)
        } else {
            defaults.removeObject(forKey: Keys.globalDiaryPromptOverride)
        }
    }

    static func load(
        from defaults: UserDefaults = .standard,
        keychain: KeychainStoring = KeychainHelper.shared,
        keychainService: String = KeychainHelper.service
    ) -> SummarizerConfig {
        SummarizerConfig(
            defaultEngine: DiaryEngine(rawValue: rawType) ?? .none,
            claudeCLIPath: defaults.string(forKey: Keys.claudeCLIPath) ?? SummarizerConfig.default.claudeCLIPath,
            codexCLIPath: defaults.string(forKey: Keys.codexCLIPath) ?? SummarizerConfig.default.codexCLIPath,
            geminiCLIPath: defaults.string(forKey: Keys.geminiCLIPath) ?? SummarizerConfig.default.geminiCLIPath,
            openclawCLIPath: defaults.string(forKey: Keys.openclawCLIPath) ?? SummarizerConfig.default.openclawCLIPath,
            apiBaseURL: defaults.string(forKey: Keys.apiBaseURL) ?? SummarizerConfig.default.apiBaseURL,
            apiModel: defaults.string(forKey: Keys.apiModel) ?? SummarizerConfig.default.apiModel,
            apiToken: keychain.load(forKey: Keys.apiToken, service: keychainService)
                ?? keychain.load(forKey: Keys.legacyOpenAIKey, service: keychainService)
                ?? "",
            globalDiaryPromptOverride: defaults.string(forKey: Keys.globalDiaryPromptOverride)
        )
    }
}
```

- [ ] **Step 4: 重跑测试，确认配置行为变绿**

Run:

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/SummarizerConfigTests
```

Expected: `SummarizerConfigTests` 全部通过。

- [ ] **Step 5: 提交**

```bash
git add KnowYou/Services/Summary/SummarizerConfig.swift KnowYouTests/SummarizerConfigTests.swift
git commit -m "feat: persist global diary prompt override"
```

---

### Task 2: 先用测试锁定默认 Prompt 与 Override Prompt 的生成边界

**Files:**
- Modify: `KnowYou/Services/Composer/DailyMarkdownComposer.swift`
- Test: `KnowYouTests/DailyMarkdownComposerTests.swift`

- [ ] **Step 1: 写失败测试，要求 composer 同时支持 canonical 默认 prompt 和 override prompt**

```swift
func testDefaultStoryPromptRemainsStructuredWhenNoOverrideExists() {
    let composer = DailyMarkdownComposer()
    let events = [
        EventRecord(
            id: UUID(),
            sourceType: .notification,
            sourceApp: "飞书",
            capturedAt: Date(timeIntervalSince1970: 1_776_000_000),
            dayKey: "2026-04-12",
            text: "讨论今天的迭代排期与待办",
            auditText: nil,
            privacyAction: .keep,
            contentHash: "global-prompt-default"
        )
    ]
    let prompt = composer.storyPrompt(
        dayKey: "2026-04-12",
        events: events,
        globalOverride: nil
    )

    XCTAssertTrue(prompt.contains("# 你今天做得很棒"), prompt)
    XCTAssertTrue(prompt.contains("# 今日总结"), prompt)
    XCTAssertTrue(prompt.contains("# 详情"), prompt)
    XCTAssertTrue(prompt.contains("# 待办事项"), prompt)
}

func testStoryPromptReturnsGlobalOverrideWhenProvided() {
    let composer = DailyMarkdownComposer()
    let override = "Use this global prompt for all future diary generations."
    let events = [
        EventRecord(
            id: UUID(),
            sourceType: .notification,
            sourceApp: "飞书",
            capturedAt: Date(timeIntervalSince1970: 1_776_000_000),
            dayKey: "2026-04-12",
            text: "讨论今天的迭代排期与待办",
            auditText: nil,
            privacyAction: .keep,
            contentHash: "global-prompt-override"
        )
    ]

    let prompt = composer.storyPrompt(
        dayKey: "2026-04-12",
        events: events,
        globalOverride: override
    )

    XCTAssertEqual(prompt, override)
}

func testDefaultStoryPromptPreviewUsesSameCanonicalPromptBuilder() {
    let composer = DailyMarkdownComposer()

    let preview = composer.defaultStoryPromptPreview(language: .chinese)

    XCTAssertTrue(preview.contains("# 你今天做得很棒"), preview)
    XCTAssertTrue(preview.contains("# 今日总结"), preview)
    XCTAssertTrue(preview.contains("# 详情"), preview)
    XCTAssertTrue(preview.contains("# 待办事项"), preview)
}
```

- [ ] **Step 2: 运行测试，确认接口尚不存在而失败**

Run:

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/DailyMarkdownComposerTests
```

Expected: `storyPrompt(..., globalOverride:)` / `defaultStoryPromptPreview(language:)` 尚未实现。

- [ ] **Step 3: 最小实现 canonical 默认 prompt 构造与 override 合并**

```swift
struct DailyMarkdownComposer {
    func storyPrompt(
        dayKey: String,
        events: [EventRecord],
        globalOverride: String? = nil
    ) -> String {
        if let override = globalOverride?.trimmingCharacters(in: .whitespacesAndNewlines), !override.isEmpty {
            return override
        }
        return makeDefaultStoryPrompt(dayKey: dayKey, events: events)
    }

    func defaultStoryPromptPreview(language: NarrativeLanguage) -> String {
        makeDefaultStoryPrompt(
            dayKey: "YYYY-MM-DD",
            events: previewEvents(for: language)
        )
    }

    private func makeDefaultStoryPrompt(dayKey: String, events: [EventRecord]) -> String {
        let language = dominantNarrativeLanguage(for: events)
        let journalHeadings = journalHeadings(for: language)
        let forbiddenHeading = language == .chinese ? "# 今日节奏" : "# Today's Rhythm"
        let eventLines = events.enumerated().map { _, event in
            """
            - id: \(event.id.uuidString)
              time: \(Self.timeFormatter.string(from: event.capturedAt))
              app: \(event.sourceApp)
              source: \(event.sourceType.rawValue)
              text: \(event.displayText)
            """
        }.joined(separator: "\n")

        return """
        You are turning one day of raw computer context into a first-person diary entry written by the person who lived that day.
        
        Return strict JSON only. Do not use markdown fences.

        Required JSON shape:
        {
          "sections": [
            { "id": "daily-journal", "paragraphs": [{ "text": "...", "sourceEventIDs": ["uuid"] }] }
          ]
        }

        Rules:
        - Keep the single section id exactly as given.
        - Write in first person (I / 我). Never describe the user in third person. Write as if the user is writing their own diary.
        - Base the content strictly on the source events. Do not invent, infer, or embellish anything not directly supported by the events.
        - Follow the actual chronology at the thread level, but you may merge related events into the same workstream when it reads more naturally.
        - Determine whether the day is mainly English or mainly Chinese from the source events.
        - Write all diary prose and all diary headings in that same dominant language.
        - If the day is mainly English, use English for all diary prose and headings.
        - If the day is mainly Chinese, use Chinese for all diary prose and headings.
        - Do not mix Chinese and English in the diary except for app names or product names that already appear in the source material.
        - The final combined markdown across paragraph texts must render exactly these first-level headings, in this order:
          1. \(journalHeadings.encouragement)
          2. \(journalHeadings.summary)
          3. \(journalHeadings.details)
          4. \(journalHeadings.todo)
        - Do not emit any other first-level heading. In particular, do not include \(forbiddenHeading).
        - The "\(journalHeadings.encouragement)" section must contain exactly one sentence.
        - The "\(journalHeadings.summary)" section should use markdown bullet points.
        - The "\(journalHeadings.details)" section should use markdown second-level headings (##) for the main workstreams or threads of the day.
        - The "\(journalHeadings.todo)" section should use markdown task list items like - [ ].
        - Only reference sourceEventIDs that appear below.
        - Put all narrative paragraphs inside the single daily-journal section.
        - Organize the day by major threads or workstreams, not by raw fragment order.
        - Prefer summarizing the main work, coordination, decisions, and next steps instead of listing every fragment.
        - Use natural transitions between blocks, but never introduce facts, emotions, or context that are not present in the source events.

        Day: \(dayKey)
        Source events:
        \(eventLines)
        """
    }
}
```

- [ ] **Step 4: 重跑测试，确认生成边界稳定**

Run:

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/DailyMarkdownComposerTests
```

Expected: `DailyMarkdownComposerTests` 通过，默认 prompt 行为未回退，自定义 override 可直接替代最终 prompt。

- [ ] **Step 5: 提交**

```bash
git add KnowYou/Services/Composer/DailyMarkdownComposer.swift KnowYouTests/DailyMarkdownComposerTests.swift
git commit -m "feat: add global diary prompt override path"
```

---

### Task 3: 在 AppState 和主窗口中接入 Prompt 编辑能力

**Files:**
- Create: `KnowYou/UI/Reader/DiaryPromptEditorSheet.swift`
- Modify: `KnowYou/App/AppState.swift`
- Modify: `KnowYou/UI/MainWindowView.swift`
- Test: `KnowYouTests/MainWindowViewModelTests.swift`

- [ ] **Step 1: 写失败测试，先锁定 Apply / Restore Default 的状态语义和“不自动重生成”**

```swift
func testApplyGlobalDiaryPromptPersistsOverrideWithoutStartingRefresh() {
    let appState = AppState(
        bootstrapServices: false,
        userDefaults: engineDefaults,
        keychain: engineKeychain,
        keychainService: "MainWindowViewModelTests"
    )

    appState.applyGlobalDiaryPrompt("Custom diary prompt")

    XCTAssertEqual(appState.globalDiaryPromptOverride, "Custom diary prompt")
    XCTAssertEqual(
        SummarizerConfig.load(
            from: engineDefaults,
            keychain: engineKeychain,
            keychainService: "MainWindowViewModelTests"
        ).globalDiaryPromptOverride,
        "Custom diary prompt"
    )
    XCTAssertTrue(appState.dayRefreshJobs.isEmpty)
}

func testRestoreDefaultDiaryPromptClearsOverrideWithoutTouchingExistingSelection() {
    let appState = AppState(
        bootstrapServices: false,
        userDefaults: engineDefaults,
        keychain: engineKeychain,
        keychainService: "MainWindowViewModelTests"
    )
    appState.selectDate("2026-04-12")
    appState.applyGlobalDiaryPrompt("Custom diary prompt")

    appState.restoreDefaultDiaryPrompt()

    XCTAssertNil(appState.globalDiaryPromptOverride)
    XCTAssertEqual(appState.selectedDate, "2026-04-12")
    XCTAssertTrue(appState.dayRefreshJobs.isEmpty)
}
```

- [ ] **Step 2: 运行测试，确认 AppState 接口尚不存在**

Run:

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/MainWindowViewModelTests
```

Expected: `AppState` 缺少 prompt override 状态与 apply / restore 接口，测试失败。

- [ ] **Step 3: 最小实现 AppState 状态和新 sheet UI**

```swift
@Observable
final class AppState {
    var globalDiaryPromptOverride: String?

    var hasCustomGlobalDiaryPrompt: Bool {
        guard let override = globalDiaryPromptOverride else { return false }
        return !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func applyGlobalDiaryPrompt(_ prompt: String) {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        globalDiaryPromptOverride = trimmed.isEmpty ? nil : prompt
        summarizerConfig.globalDiaryPromptOverride = globalDiaryPromptOverride
        persistSummarizerConfig()
        statusMessage = hasCustomGlobalDiaryPrompt
            ? "Global diary prompt updated for future generations"
            : "Global diary prompt reset to default"
    }

    func restoreDefaultDiaryPrompt() {
        globalDiaryPromptOverride = nil
        summarizerConfig.globalDiaryPromptOverride = nil
        persistSummarizerConfig()
        statusMessage = "Restored default diary prompt for future generations"
    }
}

struct DiaryPromptEditorSheet: View {
    @Binding var draftPrompt: String
    let defaultPrompt: String
    let hasCustomPrompt: Bool
    let onClose: () -> Void
    let onApply: () -> Void
    let onRestoreDefault: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("This changes future diary generation only. It does not automatically rewrite existing diary content.")
                .font(.callout)
                .foregroundStyle(.secondary)

            GroupBox("System Default Prompt") {
                ScrollView {
                    Text(defaultPrompt)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            GroupBox("Your Global Prompt") {
                TextEditor(text: $draftPrompt)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 220)
            }

            HStack {
                Button("Close", action: onClose)
                Spacer()
                Button("Restore Default", action: onRestoreDefault)
                    .disabled(!hasCustomPrompt && draftPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Apply", action: onApply)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 720, height: 620)
    }
}
```

- [ ] **Step 4: 把主窗口 toolbar 与 sheet 接上**

```swift
struct MainWindowView: View {
    @State private var isShowingPromptEditor = false
    @State private var diaryPromptDraft = SummarizerConfig.load().globalDiaryPromptOverride ?? ""

    var body: some View {
        NavigationSplitView { ... }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Edit Prompt") {
                    diaryPromptDraft = appState.globalDiaryPromptOverride ?? ""
                    isShowingPromptEditor = true
                }

                DiaryEngineSelectorButton(
                    title: currentEngineTitle,
                    state: currentEngineState,
                    action: openEnginePanel
                )
            }
        }
        .sheet(isPresented: $isShowingPromptEditor) {
            DiaryPromptEditorSheet(
                draftPrompt: $diaryPromptDraft,
                defaultPrompt: DailyMarkdownComposer().defaultStoryPromptPreview(language: .chinese),
                hasCustomPrompt: appState.hasCustomGlobalDiaryPrompt,
                onClose: { isShowingPromptEditor = false },
                onApply: {
                    appState.applyGlobalDiaryPrompt(diaryPromptDraft)
                    isShowingPromptEditor = false
                },
                onRestoreDefault: {
                    appState.restoreDefaultDiaryPrompt()
                    diaryPromptDraft = ""
                }
            )
        }
    }
}
```

- [ ] **Step 5: 重跑测试，确认状态和交互语义成立**

Run:

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/MainWindowViewModelTests
```

Expected: `MainWindowViewModelTests` 新增用例通过，`Apply` / `Restore Default` 不会触发自动刷新。

- [ ] **Step 6: 提交**

```bash
git add KnowYou/App/AppState.swift KnowYou/UI/MainWindowView.swift KnowYou/UI/Reader/DiaryPromptEditorSheet.swift KnowYouTests/MainWindowViewModelTests.swift
git commit -m "feat: add global diary prompt editor UI"
```

---

### Task 4: 把生效中的 Prompt Override 接入真实生成链路并完成全量验证

**Files:**
- Modify: `KnowYou/App/AppState.swift`
- Modify: `KnowYou/Services/Composer/DailyMarkdownComposer.swift`
- Modify: `docs/architecture.md`
- Modify: `docs/requirements-spec.md`
- Test: `KnowYouTests/DailyMarkdownComposerTests.swift`
- Test: `KnowYouTests/MainWindowViewModelTests.swift`

- [ ] **Step 1: 写失败测试，确认真实生成链路会读取当前 active override**

```swift
func testGenerateDailyNoteUsesGlobalDiaryPromptOverrideForFutureSummaries() async throws {
    let recordingSummarizer = RecordingSummarizer(response: """
    {"sections":[{"id":"daily-journal","paragraphs":[{"text":"# 今日总结\\n- 已生成","sourceEventIDs":["\(UUID().uuidString)"]}]}]}
    """)
    let environment = try makeAppEnvironment(summarizer: recordingSummarizer)
    let appState = AppState(bootstrapServices: false, environment: environment)
    appState.applyGlobalDiaryPrompt("Custom future diary prompt")

    _ = await appState.refreshSelectedDay()

    XCTAssertEqual(recordingSummarizer.lastPrompt, "Custom future diary prompt")
}
```

- [ ] **Step 2: 运行测试，确认实际生成路径还没有使用 override**

Run:

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/DailyMarkdownComposerTests -only-testing:KnowYouTests/MainWindowViewModelTests
```

Expected: 记录 summarizer prompt 的测试失败，因为当前生成路径仍只调用默认 `storyPrompt(dayKey:events:)`。

- [ ] **Step 3: 最小实现真实生成时读取当前 override，并同步文档**

```swift
private func generateStory(
    dayKey: String,
    events: [EventRecord],
    environment: AppEnvironment,
    onStageDetail: ((String?) -> Void)? = nil
) async -> DailyStory {
    if let summarizer = environment.summarizer {
        let prompt = environment.composer.storyPrompt(
            dayKey: dayKey,
            events: events,
            globalOverride: globalDiaryPromptOverride
        )
        if let raw = try? await summarizer.summarize(dayKey: dayKey, markdown: prompt),
           let parsed = environment.composer.parseStory(dayKey: dayKey, raw: raw) {
            return parsed
        }
    }
    return environment.composer.fallbackStory(dayKey: dayKey, events: events)
}
```

文档同步至少补上两点：

```md
- 用户可以从主窗口右上角编辑全局 diary prompt
- prompt 变更只影响后续生成，不会自动改写历史内容
```

- [ ] **Step 4: 跑目标测试与全量验证**

Run:

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS'
xcodebuild build -scheme KnowYou -destination 'platform=macOS'
```

Expected:

- 所有测试通过
- 构建通过
- 无新增编译错误

- [ ] **Step 5: 提交**

```bash
git add KnowYou/App/AppState.swift KnowYou/Services/Composer/DailyMarkdownComposer.swift KnowYouTests/DailyMarkdownComposerTests.swift KnowYouTests/MainWindowViewModelTests.swift docs/architecture.md docs/requirements-spec.md
git commit -m "feat: wire global diary prompt into generation"
```

---

## 自检

- 规格覆盖：
  - 右上角入口：Task 3
  - 查看默认 prompt：Task 2 + Task 3
  - 全局编辑 / Apply / Restore Default：Task 1 + Task 3
  - 影响后续生成：Task 4
  - 不自动改旧内容：Task 3 + Task 4 + 文档同步
- 占位符检查：
  - 无 `TODO` / `TBD`
  - 每个任务都有具体文件、测试和命令
- 类型一致性：
  - 全程统一使用 `globalDiaryPromptOverride`
  - AppState 接口统一使用 `applyGlobalDiaryPrompt(_:)` / `restoreDefaultDiaryPrompt()`
