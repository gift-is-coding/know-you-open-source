# Todo Workbench Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把统一 Todo 页实现为极简双栏工作台，并把低置信候选和推荐关闭从正式 Todo 中分离出来。

**Architecture:** `TodoReconciler` 和 `TodoCompletionSweep` 产出 UI 可展示的候选/关闭建议；`AppState` 保存最新待选与推荐关闭状态；`TodoInboxView` 渲染左侧正式 Todo 和右侧 Inbox。正式 Todo 继续写入 `Vault/Todo.md`，待选/推荐关闭 v1 不持久化。

**Tech Stack:** Swift 6、SwiftUI、XCTest、现有 `SummaryGenerating` stub 测试。

---

### Task 1: Presentation models and tests

- [x] 新增/更新测试，验证 Todo 页 presentation 能把 open/completed、待选、推荐关闭分开。
- [x] 新增测试，验证中低置信候选进入待选，不自动创建正式 Todo。
- [x] 新增测试，验证中置信完成进入推荐关闭，高置信完成才自动 completed。

### Task 2: Reconciler and completion confidence

- [x] 扩展 reconciliation prompt，要求过滤临时工具噪音并返回所有 create/merge/ignore 决策。
- [x] 扩展 completion sweep JSON，增加 `confidence` 字段。
- [x] 只自动应用高置信 completion，中置信 completion 进入推荐关闭。

### Task 3: AppState actions

- [x] 增加待选和推荐关闭状态。
- [x] 增加 `addTodoCandidate`、`dismissTodoCandidate`、`closeTodoRecommendation`、`keepTodoRecommendation` 操作。
- [x] Todo 打开/刷新/手动新增后保持状态同步。

### Task 4: SwiftUI implementation

- [x] 将 Todo 页改为左侧正式 Todo 列表、右侧窄 Inbox。
- [x] 去掉统计卡片和快捷键提示。
- [x] 保留自由输入，按钮文案保持 `Add`、`Merge`、`Dismiss`、`Close`、`Keep`。

### Task 5: Verification

- [x] 跑 Todo/Reconciler/AppState/View 目标测试。
- [x] 跑 `xcodebuild test -scheme KnowYou -destination 'platform=macOS'`。
- [x] 跑 `xcodebuild build -scheme KnowYou -destination 'platform=macOS'`。
- [x] 用 freshly built app 启动。
