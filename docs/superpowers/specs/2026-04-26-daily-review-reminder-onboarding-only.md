# Daily Review Reminder Onboarding-Only Permission Flow

## Goal

把晚间回顾提醒的权限体验收缩成最小版本：

- onboarding 里解释并申请通知权限
- 设置页保留 reminder 开关、状态和测试入口
- 不再在主界面右上角额外放一个 reminder CTA

## Product Rules

### Onboarding

- `permissions` 步骤必须同时展示：
  - `Full Disk Access`
  - `Notifications`
- 通知说明保持聚焦：
  - `Used for the 8:30 PM daily review reminder.`
- 通知权限不是 onboarding 的阻塞条件；Full Disk Access 仍是唯一硬阻塞项
- 用户在 onboarding 中点击 `Enable Notifications` 时，才触发系统通知权限请求

### Reminder behavior

- `Evening review reminder` 继续按本地时区 `8:30 PM` 工作
- 只有在 reminder 已开启且通知权限允许时，系统才会安排本地通知
- 如果用户在 onboarding 中拒绝通知权限，后续不再依赖主窗口 CTA 反复提示
- 后续补授权路径留在 Settings：状态展示 + `Open Notification Settings`

## UX Surface

### Keep

- onboarding `permissions` 卡片中的通知状态行与授权按钮
- settings 中的 reminder section、权限状态和 `Send Test Reminder Now`

### Remove

- onboarding 完成后主窗口右上角的 `Enable Daily Review Reminder` CTA
- CTA dismiss 状态持久化
- “手动去系统设置授权后自动开启 reminder 并隐藏 CTA”的附加状态同步

## Architecture Notes

- `AppState` 继续负责：
  - reminder config 持久化
  - 通知授权状态刷新
  - onboarding / settings 的授权请求
- `AppState` 不再持有 toolbar CTA 是否显示、CTA dismiss 状态或相关 UserDefaults key
- `MainWindowView` 不再承担 reminder 权限引导职责

## Verification

- onboarding permissions 内容仍覆盖通知用途说明
- onboarding 中请求通知权限成功后，reminder 可被启用
- 刷新通知授权状态只更新授权状态本身，不自动开启 reminder
- settings 中仍可测试正式本地通知链路
