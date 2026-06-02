# 顶层 Todo 编辑与恢复设计

## 目标

为 KnowYou 顶层 Todo 入口增加两个小能力：

- 用户可以修改统一 Todo 列表中的任务内容。
- 用户点击完成后，可以再次点击已完成项的 checkbox，把任务放回 Open。
- 用户可以从顶层 Todo 列表中删除任务。

本设计只作用于侧边栏 Todo 入口对应的统一任务列表，也就是 `Vault/Todo.md` 中 `# Todo` 下的任务。每日日记里的 `# To-do` 候选段落仍只作为候选来源，本次不编辑 diary note 原文。

## 行为

- Open 和 Completed 两个 section 中的任务都可以行内编辑标题。
- 双击任务标题或该 row 的文字区域进入编辑；Enter 保存，Esc/Cancel 取消。
- 编辑态保留保存/取消按钮作为备用入口，但键盘必须可完成主要流程。
- 保存时去掉首尾空白；空标题拒绝保存。
- 如果编辑后的归一化标题和另一条顶层 Todo 冲突，拒绝保存并显示错误，不自动合并。
- Open item 点击 checkbox 后变成 Completed。
- Completed item 点击 checkbox 后恢复 Open，并清空 `completedAt`、`completionKind`、`completionEvidenceEventIDs`。
- 恢复后的 item 重新进入 Open section，保持原始 `createdAt` 和来源 metadata。
- 每个 Open/Completed item 都提供点击删除入口；删除后从 UI、`todoItems` 和 `Vault/Todo.md`/DB 中移除。

## 存储

- `TodoStore` 是 UI 和业务层唯一入口。
- Markdown-backed 模式更新 `Vault/Todo.md` 的 task line 和 `knowyou:todo` metadata。
- Database fallback 更新 `todo_items` 表。
- 删除不影响 diary note 的 `# To-do` 候选原文，只移除顶层 Todo item。
- 不新增数据库字段，不需要 migration。

## 发布

- 本次作为 1.2.1 patch fix。
- 基于 `origin/main` 的 1.2.0 发布基线。
- 本地测试、build、启动验证、commit 后停下给用户验收；用户确认后再 push/publish。
