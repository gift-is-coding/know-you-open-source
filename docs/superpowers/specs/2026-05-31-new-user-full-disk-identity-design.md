# KnowYou New User Full Disk Access 身份设计

## 目标

`KnowYou New User.app` 必须在 macOS Full Disk Access 列表中与生产版 `KnowYou.app` 肉眼可区分，避免用户给错权限或误以为测试包不存在。

## 设计

- New User 测试包使用独立 bundle id：`dev.knowyou.newuser`。
- New User 测试包使用独立展示名、bundle name 和 executable name：`KnowYou New User`。
- New User 测试包继续使用独立数据目录：`~/Library/Application Support/KnowYou New User`。
- New User 测试包继续使用独立 Keychain service：`dev.knowyou.newuser`。
- 安装脚本负责构建、复制到 `/Applications/KnowYou New User.app`、重命名 bundle 内 executable、更新 Info.plist、重新签名、清 quarantine，并注册 LaunchServices。
- 安装脚本会清理旧的 Xcode DerivedData New User app，避免系统权限选择器看到过期 `KnowYou.app` 测试包。

## 验收标准

- `CFBundleIdentifier == dev.knowyou.newuser`。
- `CFBundleDisplayName == KnowYou New User`。
- `CFBundleName == KnowYou New User`。
- `CFBundleExecutable == KnowYou New User`。
- `/Applications/KnowYou New User.app/Contents/MacOS/KnowYou New User` 存在且可执行。
- 生产版 `/Applications/KnowYou.app` 不被修改。
