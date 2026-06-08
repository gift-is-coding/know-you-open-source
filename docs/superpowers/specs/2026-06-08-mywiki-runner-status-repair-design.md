# MyWiki Runner Status Repair Design

## Goal

让 MyWiki 用户能看懂当前 Wiki 数据是否来自成功更新，并保证普通产品入口使用打包在 `KnowYou.app` 内的 runner，而不是依赖用户机器上的 `npm`。

## Root Cause

当前失败不是 LLM 语义质量问题。失败的状态文件显示 `MyWiki runner is not available.` 且 `sourcesProcessed: 0`、`filesWritten: []`。本机检查发现当前运行过的 `/Applications/KnowYou.app` 和裸 `xcodebuild` 的 DerivedData `KnowYou.app` 都缺少 `Contents/Resources/MyWikiRunner`；`/Applications/KnowYou New User.app` 有 runner。也就是说前一次尝试启动的是没有内置 runner 的 bundle，因此没有进入 Diary Engine/LLM 生成流程。

## Behavior

- `Last update` 只能表示最近一次成功 MyWiki ingest。
- 失败或运行中的尝试显示为状态文案，不把失败时间伪装成成功更新时间。
- 缺 runner 时显示可行动诊断：当前 app 没有内置 MyWiki runner，需要重新安装或使用带 runner 的构建。
- Update 按钮在运行时显示 `Generating...` 并禁用。
- 下一次自动调度会重试 pending/changed/failed sources；如果 runner 仍不可用，会再次失败而不会后台继续处理。
- 顶部 titlebar 的 Diary Engine 按钮移动后，onboarding 的 `enginePrompt` 不得消失或指向旧 toolbar；缺少 SwiftUI anchor 时必须使用右上角 fallback coachmark，点击真实 titlebar 按钮必须进入现有 engine setup。

## Runner Packaging

产品路径继续使用 `Contents/Resources/MyWikiRunner/node` 和 `Contents/Resources/MyWikiRunner/mywiki-runner.js`。运行时命令不得包含 `npm` 或 `node_modules`。开发启动脚本和 New User 安装脚本必须验证 runner 已嵌入，避免误打开缺 runner 的 bundle。

## Verification

- Focused Swift tests cover success time, failed attempt messaging, and missing runner diagnostics.
- Focused onboarding tests cover titlebar engine button handoff and right-top fallback coachmark.
- Runner package test verifies bundled runner help path without runtime `npm`.
- Real Diary verification runs three Diary fixture sources through bundled runner plus Diary Engine bridge harness and checks source/entity/concept outputs.
