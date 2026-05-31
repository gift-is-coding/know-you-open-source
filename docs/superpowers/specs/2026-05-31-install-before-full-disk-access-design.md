# KnowYou 安装位置与 Full Disk Access 引导优化设计

## 背景

用户从 DMG、Downloads 或 DerivedData 临时路径直接运行 KnowYou 时，macOS TCC 权限会绑定到临时 bundle 身份。进入 Full Disk Access 设置后，用户可能找不到稳定的 KnowYou 条目，也不容易发现 `+` 添加入口。

## 目标

- 在 Full Disk Access 授权前，先确认生产用户正在从 `/Applications/KnowYou.app` 运行。
- 当当前 bundle 不在 `/Applications/KnowYou.app` 时，onboarding 显示 `Move KnowYou to Applications` 阻塞页。
- 主动作尝试把当前 `KnowYou.app` 复制到 `/Applications/KnowYou.app`，启动新 app，并退出旧进程。
- 自动移动失败时，提供 `Show KnowYou in Finder`，让用户手动拖到 Applications。
- Full Disk Access 说明改为以“从 Finder 拖 KnowYou.app 到系统列表”为主路径，`+` 只作为备用说明。

## 非目标

- 不尝试程序化授予 Full Disk Access。
- 不保证 macOS 一定会自动在 Full Disk Access 列表展示 KnowYou。
- 不改变 Developer ID、notarization 或 DMG 打包链路。

## 用户路径

1. 用户打开 DMG 或临时路径里的 KnowYou。
2. onboarding 在隐私说明后进入 `Move KnowYou to Applications`。
3. 用户点击 `Move to Applications and Relaunch`。
4. 成功时，新 `/Applications/KnowYou.app` 启动，旧进程退出；失败时用户可用 Finder 手动拖动。
5. 从 Applications 启动后，onboarding 才进入 Full Disk Access 步骤。
6. 用户打开 Full Disk Access，用 Finder 中的 `KnowYou.app` 拖入列表；如果拖入不可用，再用 `+` 选择 app。

## 验收

- `/Applications/KnowYou.app` 被视为已安装，DMG、Downloads、DerivedData 路径不通过。
- 未安装到 Applications 时，恢复到权限步骤会被拉回 `installApp`。
- Full Disk Access 文案把拖入列表作为主路径，并保留 `Open Full Disk Access`、`Show KnowYou in Finder`、`Check Again`。
