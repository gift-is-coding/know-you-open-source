# Daily Review Reminder Permission Entry

## Goal

把晚间回顾提醒的通知权限入口收进更自然的产品路径里：

- onboarding 阶段先解释通知用途
- onboarding 完成后，在主界面右上角继续给出一个明确但可关闭的启用入口
- 不等到晚上 `8:30 PM` 才第一次索要系统通知权限

## Product Rules

### Onboarding

- `permissions` 步骤必须同时解释两类权限：
  - `Full Disk Access`
  - `Notifications`
- 通知说明只需要一句小字：
  - `Used for the 8:30 PM daily review reminder.`
- 通知权限不是 onboarding 的阻塞项；Full Disk Access 仍是唯一硬阻塞条件

### Post-onboarding entry

- 当 onboarding 已完成、通知权限还不是 `authorized`、且用户未主动关闭入口时，主窗口右上角必须显示 CTA
- CTA 默认文案为：
  - `Enable Daily Review Reminder`
- CTA 必须支持关闭；关闭后本地持久化，不再主动展示

### CTA behavior

- 当通知权限状态是 `notDetermined` 时，点击 CTA 必须触发系统通知授权请求
- 当通知权限状态是 `denied` 时，点击 CTA 必须跳转到 macOS Notification Settings
- 当通知权限状态变为 `authorized` 时：
  - CTA 必须自动消失
  - `Evening review reminder` 必须自动启用

## UX Surface

### Onboarding permissions card

- 在现有权限卡片中新增 `Notifications` 状态行
- 当状态未授权时，显示：
  - `Enable Notifications` 或 `Open Notification Settings`
- 当状态已授权时，显示已开启状态

### Main window toolbar

- 在主窗口右上角的 toolbar 区域新增 dismissible CTA
- CTA 应与现有顶部控件保持同级，不遮挡主要阅读内容
- 关闭 CTA 只影响这个提示入口，不影响 Settings 中的 reminder 配置入口

## Architecture Notes

- `AppState` 负责：
  - 暴露 CTA 是否显示
  - 持久化 CTA dismiss 状态
  - 请求通知授权或引导打开系统设置
  - 在授权成功后自动启用晚间提醒
- onboarding 页面和主窗口 toolbar 都复用同一套通知授权状态与请求逻辑

## Verification

- onboarding permissions 内容必须覆盖通知用途说明
- 通知权限未授权时，toolbar CTA 必须在 onboarding 完成后显示
- CTA dismiss 状态必须可跨重启恢复
- 请求通知权限成功后，CTA 必须消失且 evening reminder 自动开启
