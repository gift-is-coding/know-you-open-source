# New User 回归与权限页引导设计

## 背景

用户在手动或自动测试时容易卡在 Full Disk Access 权限页。根因不是 Home 或 Networking 功能本身，而是测试入口混用了 DerivedData 临时 app、日常 app 和权限回归 app。macOS 的 Full Disk Access 绑定到 bundle id 与具体 app 安装路径，因此自动化不能假设临时构建已经获得授权。

## 目标

- 新用户权限回归统一使用 `/Applications/KnowYou New User.app`。
- 该 app 必须由当前 worktree 构建并安装，bundle id 为 `dev.knowyou.newuser`，不能从 DerivedData 直接启动。
- 普通功能回归不阻塞在 Full Disk Access；用 dev bypass、app-clean profile 或已经授权的 New User app 进入主界面。
- 权限页用英文短文案解释：打开 Full Disk Access；如果列表没有 KnowYou，点击 `+`，从 Applications 选择当前 app。
- 权限页提供 `Show App to Add` 按钮和本地 bitmap 示意图，降低用户对 Finder 按钮用途的理解成本。

## 非目标

- 不程序化授予 Full Disk Access。
- 不重置日常 `dev.knowyou.app` 的 TCC、Keychain、UserDefaults 或 app container。
- 不引入 XCUITest 或第三方 UI 自动化。

## 用户体验

权限页保留 `Open Full Disk Access` 作为主按钮。辅助按钮改为 `Show App to Add`，按钮上方明确说明：如果 Full Disk Access 列表里没有 KnowYou，就点击 `+` 添加这个 app。页面中显示一张 `FullDiskAccessAddGuide` 示意图，画出 System Settings、Full Disk Access、`+` 和 `/Applications` 中的 KnowYou app。

## 验收

- presentation tests 覆盖 `+`、`Applications`、`Full Disk Access`、`Show App to Add` 与 `FullDiskAccessAddGuide`。
- 回归文档和 runner skill 都指向 `/Applications/KnowYou New User.app` 与 `dev.knowyou.newuser`。
- `scripts/install-new-user-app.sh --no-launch` 安装出来的 app 路径不是 DerivedData。
