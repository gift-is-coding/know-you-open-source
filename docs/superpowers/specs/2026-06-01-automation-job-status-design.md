# Todo、My Wiki 自动任务与 Home Job 状态设计

## 背景

Todo 过去没有独立的定时入口，只在 Diary 生成或刷新后顺带从当天 story 中抽取候选，再交给 LLM reconcile。没有新的 diary、没有候选、或 LLM 不可用时，Todo 页面会显示 degraded，但用户看不出下一次什么时候会再试。My Wiki digest 也只暴露手动 `Update Now`，缺少自动触发解释和下一次更新时间。

## 目标

- Home 统一显示 `Diary`、`Todo`、`My Wiki` 三类后台任务的最新状态，每类只保留一条快照，不堆积历史。
- Diary 保持 3 小时自动更新节奏。
- Todo 在 Diary 准备好后跟随运行，页面显示 `Next update` 与 `Update Now`。
- My Wiki 每天一次，在 Diary 和 Todo 就绪后运行，页面显示 `Last update` 与 `Next update`。
- Onboarding / 最近三天补生成流程中，Diary 完成后补 Todo，全部完成后补 My Wiki。
- LLM 不可用时，Todo 只显示 degraded 状态，不伪造任务。

## 用户体验

Home 的 `Background jobs` 是用户理解后台工作的主入口。每行显示任务名、状态、说明、进度条、上次和下次时间，点击行跳转到对应栏目。Todo 页面给出下一次更新时间和手动触发按钮。My Wiki digest 条说明它会在 Diary 和 Todo 准备好后每日更新，同时保留手动按钮。

## 状态模型

`AutomationJobSnapshot` 按 `AutomationJobKind` 覆盖保存：

- `diary`
- `todo`
- `wiki`

每条状态包含 `scheduled`、`running`、`completed`、`degraded`、`failed`、`blocked`，以及 `detail`、`progress`、`lastRunAt`、`nextRunAt`。

## 调度规则

- Diary：每 3 小时一次。
- Todo：下一次默认排在 Diary 之后 10 分钟；手动 `Update Now` 立即处理今天 story。
- My Wiki：下一次默认排在 Diary 之后 30 分钟；完成后下一次排到 24 小时后。
- 依赖不满足时，Todo 显示 `Generate today’s diary first.`。
