# 8:30 PM Background Review Reminder

## Goal

把晚间提醒升级成真正的后台能力：

- 不依赖用户当天是否打开过 app
- 每天本地时区 `8:30 PM` 由后台任务运行一次
- 根据“今天的 diary 是否存在”发送两种不同通知

## Product Rules

### Reminder timing

- 系统必须在用户本地时区每天 `8:30 PM` 运行 reminder 后台任务
- reminder 后台任务必须由用户级 `LaunchAgent` 驱动，而不是依赖前台 `AppState` 轮询或重评估
- reminder 后台任务只负责“判断并发送通知”，不得在后台静默生成 diary

### Reminder content

- 如果今天的 diary 已存在：
  - 发送 `review` 类型通知
  - 文案固定为：`Come review today's diary.`
- 如果今天的 diary 不存在：
  - 发送 `generate` 类型通知
  - 文案固定为：`Come generate today's diary.`
- 同一天最多只允许成功发送一次晚间提醒

### Notification routing

- `review` 通知被点击后：
  - 必须唤起 KnowYou
  - 必须优先复用现有主窗口
  - 必须直接打开今天的 diary 内容
- `generate` 通知被点击后：
  - 必须唤起 KnowYou
  - 必须优先复用现有主窗口
  - 必须定位到今天
  - 必须立即开始生成今天的 diary

### Permissions

- onboarding 里的 Notifications 权限入口保留
- 通知说明文案继续明确它用于 `8:30 PM daily review reminder`
- reminder 未获系统通知权限时，后台 runner 不得崩溃，也不得发送通知

## Architecture Notes

- `KnowYouApp` 需要支持新的 headless launch mode：`--end-of-day-reminder-now`
- `LaunchAgentManager` 需要能为不同任务生成不同参数的 `LaunchAgent`
- `EndOfDayReminderRunner` 负责后台判断“today has diary?”并调 `EndOfDayReminderService`
- `EndOfDayReminderService` 的 payload 需要同时携带：
  - `dayKey`
  - `action`
- `AppState` 负责通知点击后的前台行为，而不是后台提醒决策本身

## Verification

- LaunchAgent 注册为每天本地时区 `20:30`
- 后台 runner 在有 story 时发送 `review` 通知
- 后台 runner 在无 story 时发送 `generate` 通知
- 两类通知都带 `dayKey + action`
- 点击 `review` 会打开今天 diary
- 点击 `generate` 会打开今天并立即开始生成
- 同一天不会重复发送多条提醒
