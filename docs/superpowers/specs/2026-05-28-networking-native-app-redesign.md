# Networking 原生 App 重写 Spec

## 背景

当前 Networking app 端 cockpit 使用 `WKWebView` 渲染一段本地 HTML。这个实现和 KnowYou 其他原生页面的字体、颜色、控件密度、滚动行为不一致，也让本地 App 看起来像嵌入网页。侧边栏中 `Networking` 的 SF Symbol 视觉尺寸也比 `Add Source` 稍大。

## 目标

- `Networking` 仍作为一级入口保留。
- 侧边栏 `Networking` 图标视觉尺寸要比当前略小，并与 `Add Source` 的图标重量更接近。
- App 端 `NetworkingCockpitView` 必须改为原生 SwiftUI，不再依赖 `WebKit`、`WKWebView` 或 `loadHTMLString`。
- 原生页面继续表达现有产品结构：上方 `Profile Generator`，下方 `Platforms`，右侧/下方展示 inbox/activity。
- 视觉语言要贴近 KnowYou 原生 app：使用系统字体、`windowBackgroundColor`、`controlBackgroundColor`、`.primary/.secondary`、标准 SwiftUI `Button`、`TextField`、`TextEditor`、`Picker`、`Toggle`、`ScrollView`。

## 非目标

- 不改 Web 平台设计。
- 不改 Supabase schema/RLS。
- 不实现真实 profile 编辑持久化；本次仍是 cockpit 原生展示和交互壳。
- 不重做整个侧边栏。

## 验收

- `DateSidebarView` 为 `networking` root item 提供独立、更小的 system icon metrics。
- `NetworkingCockpitView.swift` 不包含 `import WebKit`、`WKWebView`、`NSViewRepresentable` 或 `loadHTMLString`。
- Networking cockpit 仍能展示 profile 生成区、平台配置区和 agent/inbox 信息。
- 通过 targeted Swift tests、full `xcodebuild test`、full `xcodebuild build`。
