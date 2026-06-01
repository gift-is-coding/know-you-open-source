# Todo、My Wiki 自动任务与 Home Job 状态实施计划

## 实施步骤

1. 增加 focused tests，覆盖 Home job rows、Todo 自动化 presentation、My Wiki digest 下一次更新时间，以及 AppState 初始调度。
2. 在 AppState 增加 `AutomationJobKind`、`AutomationJobStatus`、`AutomationJobSnapshot`，并用覆盖式字典保存每类最新状态。
3. 在 `startAutomation` 中继续保持 Diary 3 小时节奏，同时排出 Todo 与 My Wiki 的下一次更新时间。
4. 抽出 My Wiki digest runner，让 AppState 和 My Wiki 页面共享同一套 source catalog + ingest pipeline。
5. 给 Todo 页面增加 `Next update`、`Last update`、`Update Now`，手动按钮处理今天 diary story；点击后显示 `Updating...` 并禁用重复点击。
6. 修复 Todo 在 CLI engine 下复用 diary schema 的问题：为 CLI summarizer 增加自定义 JSON schema 调用，让 Todo reconcile 使用 `decisions` schema，completion sweep 使用 `completed` schema。
7. 给 My Wiki digest 增加 `Next update`，把触发说明改成自动 + 手动都存在。
8. 给 Home 增加 compact 更新区，只在 running/degraded/failed/blocked 时显示到 hero 右下角；scheduled/completed 不占空间。
9. 给 Diary Engine toolbar presentation 增加外侧红色感叹号，并在启动时自动 retest 当前默认 yellow engine。
10. 更新文档并跑 focused tests、完整 tests、build、diff check，最后安装 `/Applications/KnowYou New User.app` 供用户测试。

## 验证重点

- Todo 没有 today story 时必须 blocked，而不是静默失败。
- LLM 不可用时 Todo 必须 degraded，不创建伪任务。
- CLI engine 下 Todo LLM 调用必须使用 Todo 专用 schema；不能把候选归集交给 diary story schema。
- My Wiki digest 失败时必须写 failed 状态，不把失败显示成完成。
- Home 每类任务只显示最新 active/attention 状态；任务完成后从 Home 隐藏。
- 当前默认 engine 处于 yellow 时，必须后台自动 retest；gray/none 只提示用户处理，不自动调用缺失配置。
