# Sidebar Feedback Entry Design

## Goal

在主界面左侧边栏底部，保留当前原有的底部菜单结构，只新增一个与原设置入口平级的 `Feedback` 按钮：

- 原有 `Settings` / `Sync Memory` 入口保持原路径和交互
- 新增 `Feedback`：点击后弹出二级菜单

二级菜单直接承接现有三种反馈/联系入口：

- X / Twitter
- Email
- Discord

## Why

当前联系方式被埋在 `Settings -> About & Community` 内，路径偏深。把反馈入口提升到侧边栏底部，可以让用户更快找到联系渠道，同时不打乱现有设置与同步入口的布局。

## UX Requirements

### Sidebar actions

- 侧边栏底部继续保持紧凑的菜单按钮布局
- 原有设置入口不重构、不挪位
- 在其旁边新增一个 `Feedback` 图标按钮

### Feedback submenu

- `Feedback` 点击后展示系统菜单样式的二级项
- 二级项共 3 个，分别打开：
  - `AppSupportMetadata.twitterURL`
  - `AppSupportMetadata.emailURL`
  - `AppSupportMetadata.discordURL`
- 二级项可带各自图标，但整体仍以轻量入口为主

### Settings page

- `SettingsView` 的 `About & Community` 保持原有联系方式区块
- 这次不借题发挥做设置页清理或迁移

## Implementation Notes

- 复用 `AppSupportMetadata` 作为联系方式来源，避免侧边栏重复硬编码链接
- 保持 `DateSidebarView` 的现有底部 `Menu` 结构，只增加一个相邻菜单按钮
- onboarding 本次只做触发条件核查与回归测试，不顺带重构启动链

## Verification

- 新增或更新测试，覆盖 onboarding 完成后的真实启动路径不会重新进入 onboarding
- 构建并运行目标测试切片
- 启动应用，在左侧边栏确认：
  - 原有设置入口仍在原位置
  - `Feedback` 为新增的平级按钮
  - 三个反馈渠道都能显示
  - 重新关闭并打开应用时，不应再次进入 onboarding
