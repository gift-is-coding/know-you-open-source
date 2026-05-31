# New User 回归与权限页引导实施计划

## 步骤

1. 补充失败测试
   - 更新 onboarding content tests，断言 Full Disk Access 文案包含 `+`、`Applications`、`Show App to Add` 与图片 asset 名称。
   - 增加回归文档测试，断言 permission-clean 使用 `/Applications/KnowYou New User.app`、`dev.knowyou.newuser`，且不是 DerivedData app。
   - 增加 asset bundle 测试，确保 `FullDiskAccessAddGuide` 存在。

2. 更新权限页实现
   - 为 `OnboardingFullDiskAccessGuidance` 增加 `visualAssetName`。
   - 将权限页辅助按钮改成 `Show App to Add`。
   - 在权限按钮上方和权限要求区域加入短提示，说明找不到 KnowYou 时点击 `+` 添加当前 app。
   - 在权限页展示 `FullDiskAccessAddGuide` 本地 bitmap。

3. 固化 New User 安装规则
   - `OnboardingApplicationInstallPolicy` 区分生产 `/Applications/KnowYou.app` 与 New User `/Applications/KnowYou New User.app`。
   - 保持 `scripts/install-new-user-app.sh --no-launch` 作为权限回归安装入口。
   - 文档明确多 worktree 不并行跑 New User 权限测试，最后一次安装覆盖 `/Applications/KnowYou New User.app` 是预期行为。

4. 更新文档
   - 更新 `docs/regression/README.md`、`01-first-run-onboarding.md`、`coverage-matrix.md` 与 `knowyou-regression-runner` skill。
   - 更新 `docs/architecture.md` 与 `docs/requirements-spec.md`，记录新的权限页路径与测试边界。

5. 验证
   - 跑 focused onboarding presentation tests。
   - 跑 focused Home/Networking tests，确认前一组功能没有回退。
   - 跑完整 `xcodebuild test`、`xcodebuild build`、`git diff --check`。
   - 跑 `scripts/install-new-user-app.sh --no-launch` 并验证 `/Applications/KnowYou New User.app`、bundle id 与安装路径。
