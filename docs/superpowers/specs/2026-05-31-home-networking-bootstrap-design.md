# Home、Networking 与老用户三天补生成设计

## 目标

让老用户和新用户都能在主窗口第一屏快速理解 KnowYou：应用需要在后台持续运行，会按固定节奏生成当天日记；同时把 Networking 从空 placeholder 提升为可视化预告，并为升级后跳过 onboarding 的老用户提供最近 3 天补生成入口。

## 产品行为

- 左侧一级菜单顺序为 `Home`、`Networking`、`Todo`、`My Wiki`、`My Diary`、`Other Source`，随后是已添加的 Feishu/Lark、Notion、Google Drive 等来源。
- `Home` 是默认入口，页面使用少量英文短句、视觉资产、下一次日记检查倒计时、4 个功能跳转卡片和 `Generate Last 3 Days` 按钮。
- `Networking` 页面不再显示简单 coming-soon 文案，而是用英文短句和视觉资产说明 profile、求职/社交多场景、AI 身份透明。
- Todo 页面中创建待办和右侧 inbox 的用户可见中文文案全部改为英文。
- 已完成 onboarding 但 bootstrap 仍处于 idle、且最近 3 天存在缺失日记的用户，可通过自动检测或 Home 按钮进入现有三天 bootstrap 流程；已有日记日期跳过。

## 实现边界

- 不引入远端 Networking 后端，不合并旧 networking worktree 的完整实现。
- 不清除 dev bundle 的登录、onboarding、auth、engine 或 UserDefaults 状态。
- 三天补生成复用 `AppState` 现有 onboarding bootstrap、进度、notice 和串行生成逻辑。

## 验收

- 新增和更新的 XCTest 覆盖 sidebar 顺序、Home/Networking presentation、Todo 英文文案和老用户补生成排队。
- 本地 asset catalog 包含 Home 与 Networking 的 bitmap 视觉资产。
- 完成前运行 targeted tests、完整 `xcodebuild test`、完整 `xcodebuild build`、`git diff --check`，再用 fresh dev app 脚本启动。
