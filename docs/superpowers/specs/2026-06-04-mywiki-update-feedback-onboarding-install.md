# My Wiki Update Feedback 和 Onboarding 安装判断设计

## 背景

New User 安装体验暴露了两个问题：

- `My Wiki digest` 的 `Update Now` 点击后缺少可见反馈；如果后台在跑，用户不知道是否已开始。
- Onboarding 在用户已经把 app 拖进 Applications 后，仍可能继续提示移动到 Applications。

## 目标

- My Wiki 手动更新进入后台任务后，按钮立即切换为生成中状态、禁用重复点击，并在 digest 卡片内显示可见状态。
- 如果 My Wiki 项目目录不可用，Update 入口不能静默返回，界面要显示不可用状态。
- Onboarding 安装判断要接受 macOS 上 `/Applications` 的真实数据卷路径 `/System/Volumes/Data/Applications`，同时继续拒绝 DMG、Downloads 和 DerivedData。

## 非目标

- 不改变 My Wiki runner 架构。
- 不新增新的 LLM 配置入口。
- 不重做 Onboarding 流程视觉设计。

## 方案

- 在 `MyWikiDigestSchedulePresentation` 中集中表达按钮标题、禁用状态和状态文案。
- 在 `MyWikiPanel.syncDiaries()` 开始时立即写入本地 running progress placeholder，直到 `.llm-wiki/last-ingest-status.json` 提供真实进度。
- 当 `projectRoot == nil` 时，digest 卡片显示 folder unavailable，按钮禁用；其它入口调用更新时也写入 status message 并弹出状态。
- `OnboardingApplicationInstallPolicy` 改为比较目标 app 名和允许的 Applications 父路径，而不是只做固定字符串路径相等。

## 测试

- `KnowledgeOntologyPanelTests` 覆盖 My Wiki 更新中 presentation。
- `KnowledgeOntologyPanelTests` 覆盖 My Wiki 项目不可用 presentation。
- `MyWikiIngestProgressStoreTests` 覆盖 running placeholder 的标题和 detail。
- `OnboardingContentTests` 覆盖 `/System/Volumes/Data/Applications` 下的正式版和 New User 版。
