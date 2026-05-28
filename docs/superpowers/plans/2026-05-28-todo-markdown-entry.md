# Todo Markdown Entry Implementation Plan

**目标：** 让统一 Todo 支持自由输入，并把 `Vault/Todo.md` 作为权威底层文件。

**架构：** 在现有 `TodoStore` 内增加 Markdown-backed 分支。`AppEnvironment` 注入 `vaultURL/Todo.md`，`AppState` 增加自由输入 action，`TodoInboxView` 增加输入框。SQLite 仅用于旧数据 seed。

## Task 1: Markdown Store

- [x] 给 `TodoStore` 增加可选 `documentURL`。
- [x] 实现 `Todo.md` 读写、排序、metadata comment、open/completed 分区。
- [x] 当 `Todo.md` 缺失时从 SQLite `todo_items` seed。
- [x] 增加 `TodoStoreTests` 覆盖 Markdown 持久化和 SQLite seed。

## Task 2: Manual Entry

- [x] 在 `AppState` 增加 `addTodo(title:)`。
- [x] 在 `TodoInboxView` 增加输入框、回车提交和加号按钮。
- [x] 在 `MainWindowView` 接入新增 action。
- [x] 增加 AppState 测试，验证自由输入写入 `Todo.md`。

## Task 3: Verification

- [x] 先运行目标测试并确认缺失 API 导致失败。
- [x] 实现后运行同一目标测试并确认通过。
- [ ] 运行完整 `xcodebuild test -scheme KnowYou -destination 'platform=macOS'`。
- [ ] 运行完整 `xcodebuild build -scheme KnowYou -destination 'platform=macOS'`。
- [ ] 用 fresh build 打开 app，并确认 `Todo.md` seed/刷新路径。
