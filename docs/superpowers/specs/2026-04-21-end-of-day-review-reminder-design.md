# End-of-Day Review Reminder Design

## Goal

在 Know You 中新增一个温和的晚间回顾提醒能力：

- 目标不是催促刷新，而是在一天快结束时把用户带回“看看今天发生了什么”
- 提醒只基于“今天已经有可读 diary”
- 提醒通过 macOS 本地通知承载，而不是只靠 app 进程内 `Timer`

## Product Rules

### Trigger

- 只针对“今天”评估
- 必须存在可读 `DailyStory` 才发送提醒
- 如果提醒已经成功发出过一次，当天不再发第二次

### Timing

- 每天固定在用户本地时区 `20:30`
- 如果 `20:30` 前 story 已 ready，则在 `20:30` 发送
- 如果 `20:30` 时 story 不 ready，则先触发一次当天 refresh
- refresh 成功后，提醒延后 `10 分钟`
- 如果 refresh 后 story 仍不 ready，则当天放弃，不再继续重试

### Tone

- 提醒文案必须温和，不做效率工具式“打卡催办”
- V1 使用内置模板池，避免每次都一样
- V1 不做用户自定义提醒时间或文案

## UX Surface

### Settings

设置页新增轻量提醒区块：

- 开关：`Evening review reminder`
- 权限状态：`Allowed` / `Not allowed` / `System blocked`
- 说明文案：
  - `Know You will gently remind you at 8:30 PM in your local time when today’s diary is ready.`
  - `If today’s diary is not ready yet, Know You will refresh it first and remind you 10 minutes later.`

### Notification copy

V1 使用固定标题加正文模板池：

- 标题：`Evening Review`
- 正文候选：
  - `看看今天发生了什么吧`
  - `今天也辛苦了，回来回顾一下这一天吧`
  - `一天快结束了，来看看今天留下了什么`
  - `如果你有点累了，今天的记录已经帮你整理好了`

## Architecture Notes

- 新增独立的 `EndOfDayReminderPlanner`，只负责纯规则判断
- 新增独立的 `EndOfDayReminderService`，负责通知权限与本地通知调度
- `AppState` 负责持久化 reminder config / per-day review state，并在“生成成功 / 启动恢复 / 权限状态刷新”这些节点触发重评估
- 当 `20:30` 时 story 尚未 ready，`AppState` 会先触发一次当天 refresh，之后按 `+10 分钟` 安排提醒

## Verification

- planner 必须覆盖：固定 `20:30` 调度、晚于 `20:30` 的补发、无 story 时触发 refresh、refresh 后 `+10 分钟` 调度、已提醒 suppression
- service 必须覆盖：权限状态映射、同一天 request id 稳定、调度与取消
- `AppState` 必须覆盖：今日生成成功会触发调度、`20:30` 缺 story 时会先 refresh、重启不会对同一天重复排队提醒
