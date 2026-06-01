# Home、Diary、Networking 与 Add Source Prompt 调整计划

## 实施步骤

- [x] 更新 `JournalListOrdering`，让主 Diary 列表固定为 today 加前三天，并保持 demo day 的特殊附加规则。
- [x] 调整 onboarding / 老用户三天补生成：只检查 yesterday 到 3 days ago，today 改由 Home 的 `Generate Now` 更新。
- [x] 更新 Home presentation：`Automatic Diary update` 显示本地时间，新增 `Generate Now`，并按缺失天数显示或隐藏 `Generate Last 3 Days`。
- [x] 将 Home 功能入口改为单列，顺序为 Networking、Todo、My Wiki、Today’s Diary、Other Source，并补充简短说明。
- [x] 将 Sidebar 和 Networking 页面统一为 `Networking (Coming soon)`，移除 clear identity 相关文案和图片文字。
- [x] 移除 Other Source root 的 `+`。
- [x] 更新 Generate Prompt 标题、prompt 模板和复制后的视觉引导弹窗。
- [x] 增加本地 bitmap 资产 `ExternalPromptRunGuide`，替换 `NetworkingPreviewHero`。
- [x] 更新 focused presentation / bootstrap / connector tests。

## 验证

- [x] Focused tests：Diary 四天窗口、Home presentation、Networking presentation、Sidebar、Connector prompt、老用户三天补生成。
- [x] `xcodebuild test -scheme KnowYou -destination 'platform=macOS'`
- [x] `xcodebuild build -scheme KnowYou -destination 'platform=macOS'`
- [x] `git diff --check`
- [x] `scripts/install-new-user-app.sh` 重新安装并打开 `/Applications/KnowYou New User.app`

## 备注

- 本轮不新增复杂 feed 或真实 Networking 数据结构，只做清晰 preview。
- Copy Prompt 引导图使用静态 bitmap，避免 GIF 或视频资源增加构建不稳定性。
