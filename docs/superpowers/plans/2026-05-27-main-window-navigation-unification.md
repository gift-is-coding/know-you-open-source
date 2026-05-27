# Main Window Navigation Unification Implementation Plan

**Goal:** 让 `My Wiki`、`Other Source`、`My Diary` 成为同一套 sidebar root row，并保持右上角 engine selector 固定在全局 toolbar。

**Architecture:** 把 `My Wiki` 纳入 `DateSidebarPresentation` 的 root items；保留 `MainWindowMode` 作为内容区切换状态，但主窗口始终渲染同一个 `NavigationSplitView`。`DiaryEngineSelectorButton` 继续放在 `MainWindowView.toolbar`，不进入任何具体页面。

## Tasks

- [x] 增加 sidebar presentation 测试，要求 `My Wiki`、`Other Source`、`My Diary` 是同一组 root item。
- [x] 增加 selection action 测试，要求 `my-wiki` 走 My Wiki 内容区，不被当成 diary day key。
- [x] 增加主窗口 workspace policy 测试，要求 toolbar 在所有 sidebar mode 下保持全局稳定。
- [x] 移除 `DateSidebarView` 顶部单独的 `My Wiki` 按钮。
- [x] 把 `My Wiki` 渲染为普通 `rootRow`。
- [x] 把主窗口从 My Wiki 专用 HStack workspace 改成统一 `NavigationSplitView`。
- [x] 更新架构和需求文档。
- [x] 运行目标测试、完整测试和 build。
