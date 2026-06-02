# 顶层 Todo 编辑与恢复 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 顶层 Todo 列表支持修改、删除任务内容，并支持 completed item 再次点击恢复 open。

**Architecture:** 以 `TodoStore` 为统一业务入口，分别落到 markdown-backed `Vault/Todo.md` 和 database fallback。`AppState` 暴露 edit/toggle action，`TodoInboxView` 只负责行内编辑交互和回调。

**Tech Stack:** Swift, SwiftUI, GRDB, XCTest.

---

### Task 1: 顶层 Todo 存储行为

**Files:**
- Modify: `KnowYou/Services/Storage/DatabaseWriter.swift`
- Modify: `KnowYou/Services/Todo/TodoStore.swift`
- Test: `KnowYouTests/DatabaseWriterTests.swift`
- Test: `KnowYouTests/TodoStoreTests.swift`

- [x] 写失败测试：database todo 可改名，restore 后 status 回到 open 且 completion metadata 清空。
- [x] 写失败测试：markdown-backed `Vault/Todo.md` todo 可改名并持久化，restore 后回到 `## Open`。
- [x] 写失败测试：database 和 markdown-backed todo 删除后只移除匹配 item。
- [x] 实现 `updateTodoTitle(id:title:)`，空标题和 duplicate normalized title 报错。
- [x] 实现 `reopenTodo(id:)`，清空完成字段。
- [x] 实现 `deleteTodo(id:)`，删除匹配顶层 Todo item。
- [x] 跑 targeted tests。

### Task 2: AppState 与 UI 行内编辑

**Files:**
- Modify: `KnowYou/App/AppState.swift`
- Modify: `KnowYou/UI/MainWindowView.swift`
- Modify: `KnowYou/UI/Todo/TodoInboxView.swift`
- Test: `KnowYouTests/MainWindowViewModelTests.swift`

- [x] 写失败测试：`AppState` edit/toggle/delete 只更新顶层 `todoItems`。
- [x] 增加 `updateTodoItemTitle(id:title:)` 和 `toggleTodoItemCompletion(id:)`。
- [x] 增加 `deleteTodoItem(id:)`。
- [x] 将 `TodoInboxView` row 改为支持双击文字区域行内编辑。
- [x] 编辑态支持 Enter 保存、Esc 撤销，按钮仅作为备用入口。
- [x] checkbox 对 open/completed 都可点击，通过 toggle 回调完成或恢复。
- [x] row 提供点击删除入口，通过 delete 回调移除顶层 Todo。
- [x] 跑 targeted tests。

### Task 3: 1.2.1 发布准备与验证

**Files:**
- Modify: `KnowYou.xcodeproj/project.pbxproj`

- [ ] 将所有 `MARKETING_VERSION = 1.2.0;` 改成 `1.2.1`。
- [ ] 运行 full test、build、`git diff --check`。
- [ ] 启动 fresh build 手动验证顶层 Todo：新增、编辑、完成、恢复、检查 `Vault/Todo.md`。
- [ ] 本地 commit 后停下，等待用户验收再 push/publish。
