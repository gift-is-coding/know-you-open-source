# Diary Engine Recovery Nudge 设计规格

## 背景

用户完成 onboarding 进入主界面后，可能还没有配置 Diary Engine；也可能使用一段时间后，默认 engine 的 CLI、登录态或 LLM API 失效。当前主界面右上角已经有全局 Diary Engine selector，但未配置和失效状态的表达还不够明确，尤其是默认 engine 进入 yellow 失败态时，按钮可能看起来不像需要处理。

## 目标

- onboarding 后允许用户进入主界面，不用把 engine 配置做成硬阻塞。
- 当没有默认 engine 时，右上角按钮持续显示需要添加 engine 的状态，直到问题解决。
- 当默认 engine 不是 green 时，右上角按钮持续显示需要修复 engine 的状态。
- 用户点击按钮后，popover 顶部必须说明当前问题，并提供配置/重测路径。
- 用户关闭 popover 或点过按钮，不会清除未解决状态。

## 交互规则

### 未配置状态

当 `defaultEngine == .none` 时：

- toolbar button 文案显示 `Add Diary Engine`。
- toolbar button 使用黄色状态灯和强调边框。
- popover 顶部显示 `Choose a Diary Engine`。
- 说明文案为“Connect any engine to generate and refresh diary entries.”
- 下面继续显示现有 engine 列表，用户可配置 LLM API、测试 CLI/Auth engine。

### 失效状态

当 `defaultEngine != .none` 且默认 engine 的状态不是 `.green` 时：

- toolbar button 文案显示 `Fix Diary Engine`。
- toolbar button 使用黄色状态灯和强调边框。
- popover 顶部显示 `Diary Engine needs attention`。
- 说明文案明确当前默认 engine 不可用，例如 `Codex (CLI) is not ready. Retest it or configure another engine.`
- 不自动切换到 `.none`，也不静默换成其他 engine。

### 已解决状态

当默认 engine 是 `.green` 时：

- toolbar button 恢复显示默认 engine 名称。
- toolbar button 不再因为 recovery nudge 被强调。
- popover 不显示 recovery banner。

## 架构

- 在 `DiaryEngineSelectorButton.swift` 中增加一个轻量 presentation model：`DiaryEngineRecoveryNudgePresentation`。
- presentation model 只接受 `defaultEngine` 和 `engineStatuses`，输出 toolbar 文案、状态灯、popover 标题和说明。
- `MainWindowView` 根据 presentation model 驱动 toolbar button。
- `DiaryEnginePanel` 接收可选 recovery nudge，并在 engine 列表上方显示 banner。
- 不新增持久化 dismissal 状态；未解决状态由 engine runtime state 推导，因此用户点击或关闭 popover 后仍然存在。

## 测试

- 在 `MainWindowViewModelTests` 中添加纯 presentation tests。
- 覆盖：
  - default engine 为 `.none` 时显示 Add nudge。
  - 默认 engine 为 yellow 时显示 Fix nudge。
  - 默认 engine 为 green 时不显示 nudge。
  - 点击/关闭不参与模型，nudge 由状态推导，因此状态不变时 presentation 稳定。

## 非目标

- 本次不做新的 onboarding step。
- 本次不做持久化“关闭提醒”。
- 本次不做自动 fallback engine 选择。
- 本次不改 LLM API provider 配置页结构。
