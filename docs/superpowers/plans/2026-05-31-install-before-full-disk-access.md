# KnowYou 安装位置与 Full Disk Access 引导优化计划

## 执行步骤

1. 先写 onboarding 内容与状态机测试，覆盖 `installApp` 顺序、安装路径判断、恢复时的权限前置阻塞，以及 Full Disk Access 文案。
2. 在 onboarding 内容模型中加入 `installApp` 步骤和 `applicationInstalled` gate。
3. 在 `AppState` 的 onboarding restore 逻辑中加入 `isInstalledInApplications` 输入，确保未安装到 `/Applications/KnowYou.app` 时不能进入 `permissions`。
4. 在 `OnboardingView` 中实现移动页、自动复制重启动作、Finder fallback，以及开发构建 bypass。
5. 更新架构与需求文档，使发布路径、onboarding 顺序和 Full Disk Access 引导保持一致。
6. 运行 targeted onboarding tests、`git diff --check`、全量 `xcodebuild test` 与 `xcodebuild build`。

## 风险与处理

- `/Applications` 写入可能因权限或已有 app 失败：显示 fallback，让用户手动拖动。
- macOS 不保证自动列出 app：文案把拖入列表作为主路径，`+` 作为备用路径。
- 开发 DerivedData 构建不应被生产安装 gate 卡死：保留开发 bypass 按钮。
