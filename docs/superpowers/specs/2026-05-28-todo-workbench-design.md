# Todo 极简工作台设计

## Summary

这次迭代把 Todo 页从 dashboard 改成 Obsidian/Markdown 风格的双栏工作台：左侧是正式 Todo 列表，右侧是窄的 Inbox。正式 Todo 只保留跨天仍要推进的大颗粒任务；日记生成的大部分候选先进入待选；模型认为可能已完成的事项进入推荐关闭。

## Key Behavior

- 左侧主列表展示 `Open` 和 `Completed`，不再显示统计卡片或快捷键提示。
- 右侧 Inbox 分为 `待选` 和 `推荐关闭` 两个紧凑列表；按钮文案保持简单：`Add`、`Merge`、`Dismiss`、`Close`、`Keep`。
- 高置信、明确、跨天仍要推进的候选才自动进入正式 Todo；中低置信候选进入待选。
- Codex、Xcode、branch、worktree、build、test 等开发过程性事项默认视为临时工具噪音，除非明确表现为跨天交付物。
- 自动完成分两层：高置信且有明确完成证据时自动关闭；中置信时只进入推荐关闭，由用户确认。

## Data Flow

- `TodoReconciler` 继续负责候选归集，但返回的非高置信 create/merge 决策要保留给 UI 作为待选项。
- `TodoCompletionSweep` 增加 `confidence`，高置信 completion 自动写入 `Todo.md`，中置信 completion 显示为推荐关闭。
- 待选和推荐关闭在 v1 作为 AppState 内的最新刷新结果，不写入 `Todo.md`；正式 Todo 和 completed 仍以 `Vault/Todo.md` 为源数据。

## Acceptance

- 打开 Todo 页时左侧是正式 Todo，右侧是窄 Inbox。
- 手动输入仍能直接写入正式 Todo。
- 日记刷新后，低/中置信候选不会污染正式 Todo，而是在 Inbox 待选中可处理。
- 用户可以从 Inbox 把候选 `Add` 到 Todo，或 `Dismiss` 从当前待选中移除。
- 推荐关闭中的事项可以 `Close` 写入 completed，也可以 `Keep` 保持 open 并从推荐列表移除。
