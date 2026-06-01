# Todo、My Wiki 自动任务与 Home Job 状态实施计划

## 实施步骤

1. 增加 focused tests，覆盖 Home job rows、Todo 自动化 presentation、My Wiki digest 下一次更新时间，以及 AppState 初始调度。
2. 在 AppState 增加 `AutomationJobKind`、`AutomationJobStatus`、`AutomationJobSnapshot`，并用覆盖式字典保存每类最新状态。
3. 在 `startAutomation` 中继续保持 Diary 3 小时节奏，同时排出 Todo 与 My Wiki 的下一次更新时间。
4. 抽出 My Wiki digest runner，让 AppState 和 My Wiki 页面共享同一套 source catalog + ingest pipeline。
5. 给 Todo 页面增加 `Next update`、`Last update`、`Update Now`，手动按钮处理今天 diary story。
6. 给 My Wiki digest 增加 `Next update`，把触发说明改成自动 + 手动都存在。
7. 给 Home 增加 `Background jobs` 三行状态，并支持点击跳转到 Diary、Todo、My Wiki。
8. 更新文档并跑 focused tests、完整 tests、build、diff check，最后安装 `/Applications/KnowYou New User.app` 供用户测试。

## 验证重点

- Todo 没有 today story 时必须 blocked，而不是静默失败。
- LLM 不可用时 Todo 必须 degraded，不创建伪任务。
- My Wiki digest 失败时必须写 failed 状态，不把失败显示成完成。
- Home 每类任务只显示最新一条，下一次同类任务覆盖上一条完成状态。
