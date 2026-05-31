# KnowYou 本机新用户测试模式设计

## 目标

为了在开发机上真实验证首次用户路径，KnowYou 保留一个本机 QA 测试包：`KnowYou New User.app`。它只用于验证 onboarding、Full Disk Access、通知权限与首次过去 7 天 bootstrap，不作为正式发布包，也不替代日常开发使用的 `KnowYou.app`。

## 设计

- 日常开发继续使用普通 `KnowYou.app`，bundle id 为 `dev.knowyou.app`，运行数据仍写入 `~/Library/Application Support/KnowYou`。
- New User 测试包使用 bundle id `dev.knowyou.newuser`，展示名、bundle name 与 executable name 均为 `KnowYou New User`。
- New User 测试包的数据目录为 `~/Library/Application Support/KnowYou New User`，Keychain service 为 `dev.knowyou.newuser`。
- 运行时代码只允许通过 bundle id 选择 `AppRuntimeProfile`；除 `dev.knowyou.newuser` 外，所有 bundle id 都必须回到普通 `KnowYou` profile。
- 构建与安装由 `scripts/install-new-user-app.sh` 负责。脚本会构建、复制到 `/Applications/KnowYou New User.app`、更新 Info.plist、重命名 executable、重新签名、清 quarantine，并注册 LaunchServices。
- 生产版 `/Applications/KnowYou.app`、普通开发数据目录、普通 Keychain service 与现有 macOS 权限不得被脚本清理或重置。

## 验收标准

- 普通 bundle id、未知 bundle id 与 nil bundle id 都映射到 `KnowYou` / `~/Library/Application Support/KnowYou` / `com.knowyou.app`。
- `dev.knowyou.newuser` 只映射到 `KnowYou New User` / `~/Library/Application Support/KnowYou New User` / `dev.knowyou.newuser`。
- New User 安装产物的 `CFBundleIdentifier`、`CFBundleDisplayName`、`CFBundleName` 与 `CFBundleExecutable` 均可自动验证。
- Full Disk Access 添加器中能肉眼区分 `KnowYou New User` 与生产版 `KnowYou`。
