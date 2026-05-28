# Todo Markdown Entry Design

## 背景

统一 Todo v1 已经把每日待办从日记里抽出来，但用户反馈了两个关键体验问题：

- Todo 页不能自由输入，只能从日记候选转入。
- 统一 Todo 的底层应该是 Markdown 文档，而不是只存在 SQLite 里。

## 设计

统一 Todo 的权威文件改为 `Vault/Todo.md`。文件保持人可读的 Markdown task list：

- `## Open` 下保存 open todo
- `## Completed` 下保存 completed todo
- 每行 task 后追加隐藏的 `knowyou:todo` HTML comment，保存 id、来源日期、source event IDs、创建/完成时间、归集方式、完成方式等结构化元数据

SQLite `todo_items` 不再作为 v1.1 的用户侧权威数据源。为了保护已经写入的旧数据，`TodoStore` 在首次发现 `Todo.md` 不存在时，会从 SQLite `todo_items` seed 一次 Markdown 文件。

## 自动更新时机

Todo 会在这些时刻刷新/写入：

- App 启动初始化 Todo 状态
- 用户打开左侧 `Todo` 页面
- 每日日记生成或刷新成功后，运行自动归集和自动完成 sweep
- 用户在日记候选旁点击 `Add to Todo`
- 用户在 Todo 页自由输入新任务
- 用户手动把 open todo 标记为 completed

v1.1 不做持续文件监听；如果用户在外部编辑 `Todo.md`，下次打开 Todo 页面或触发 Todo 刷新时读取。

## 用户旅程

1. 用户打开左侧 `Todo`。
2. 在顶部输入框输入一个任务，按回车或点击加号。
3. App 立即把任务写入 `Vault/Todo.md` 的 `## Open`。
4. 左侧 open 数量和 Todo 页面同步刷新。
5. 用户点击任务左侧圆圈后，任务移到 `## Completed` 并保留在底部。

日记候选路径保持不变：高置信候选自动进入 `Todo.md`，低置信候选留在日记中，用户可点击 `Add to Todo`。

## 验收标准

- 自由输入任务会出现在 Todo 页面，并持久化到 `Vault/Todo.md`。
- 已有 SQLite todo 在 `Todo.md` 缺失时会迁移到 Markdown。
- 完成任务后 Markdown task row 变成 `- [x]` 并位于 completed 区域。
- 自动归集、手动转入、自动完成都写同一个 Markdown 文件。
- 没有可用 LLM 时，自动归集/完成继续 degraded，手动输入和手动完成不受影响。
