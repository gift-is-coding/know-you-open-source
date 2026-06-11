# Networking Guided First-Level Page 开发计划

## 步骤

- [x] 增加 Networking cockpit 源码测试，锁定原生 SwiftUI、三步英文引导、隐私提示、隐藏 prompt、生成式头像和两个社区名称。
- [x] 重写 `NetworkingCockpitView` 为三步式页面：生成 profile、绑定社区、查看消息线索。
- [x] 二次重构 `NetworkingCockpitView` 为 profile-first 自动启动流：移除 `Enable Networking` 大按钮，进入页面自动 `ensureActivationState()`，顶部只保留 `Agent ready locally` 轻量状态。
- [x] 把 `Custom scenario` 改为 `Custom profile`，删除重复 custom card，并增加 inline editor：use case、profile image direction、public tone、redaction notes 和默认脱敏 checklist。
- [x] 把生成结果状态改成 `Draft not generated` / `Needs approval` / `Approved`，增加 `Approve profile` 与 `Regenerate` 操作。
- [x] 增加 `NetworkingProfileApprovalStateStore`，把 approved profile IDs 持久化到当前 My Wiki projectRoot 的 `.knowyou/networking/profile-approval.json`。
- [x] 让 `NetworkingPlatformConfiguration.canRunAutomation` 只有在 profile 已生成且已批准时才返回 true。
- [x] 把社区区和消息区合并成 `Communities and messages`，`Find Your Friends` 保留底层 `knowyou-friends` id。
- [x] 给 `NetworkingCockpitItem` 增加 `platformID`，并让 cockpit messages 按当前 selected community 过滤，fallback demo data 也按平台分组。
- [x] 为页面增加 toolbar safe-area 顶部间距、横向 profile 滚动、紧凑 generation status/error card，避免文字穿出或压到 toolbar。
- [x] 英文化 App 一级页面可见文案。
- [x] 移除一级页面上的 prompt 展示。
- [x] 用 `GeneratedFaceAvatar` 替换单字母头像表现。
- [x] 保留两个社区：`Know You Careers`、`Find Your Friends`。
- [x] 接入真实 `projectRoot` 和 `summarizer`，让 `Generate from My Wiki` 走 `NetworkingProfileGenerationService`。
- [x] 实现 `NetworkingActivationStateStore.save`，让 App 端 Enable 写入 MCP 可读取的本地授权状态。
- [x] 为 `Generate from My Wiki` 增加 UI 超时失败收尾，避免底层 LLM/CLI 长时间等待时按钮永久停在生成中。
- [x] 运行源码断言覆盖页面文案、禁用模式、真实生成 wiring 和 activation 持久化。
- [x] 运行 focused XCTest。
- [x] 用用户真实 My Wiki 数据验证 context pack、未授权 MCP 拒绝、启用后 MCP payload。
- [x] 运行完整 `xcodebuild test` 和 `xcodebuild build`。
- [x] 运行 `./scripts/run-dev-app.sh`，确认当前 worktree bundle 的 `BuildMetadata.gitShortSHA` 匹配 `HEAD`，并只处理当前 worktree 的 app 进程。
- [x] 通过 WindowServer/Quartz 窗口列表确认 freshly built `KnowYou.app` 已打开；当前会话的屏幕截图和 Computer Use 受 macOS 捕获权限限制，无法读取窗口内容截图。

## 当前验证状态

Focused `NetworkingCockpitPresentationTests` 已在本机 macOS destination 通过；本轮新增/更新覆盖自动 activation、custom profile editor、approval 状态、approval state store、platform message filtering、toolbar safe-area 和错误卡片。完整 `xcodebuild test` 和 `xcodebuild build` 已在本轮重新通过；fresh app launch 已通过 `./scripts/run-dev-app.sh` 打开当前 worktree bundle，并用 WindowServer/Quartz 窗口列表确认 `KnowYou` 主窗口 onscreen。

真实用户数据 smoke 已完成：当前 My Wiki projectRoot 读取到 `838` 个 wiki markdown 和 `50` 个 raw source；`--my-wiki-context` 返回真实 citation；未开启 Networking 时 `--networking-mcp` 拒绝写入；写入本地 activation state 后 MCP 返回带 `platform_id`、`profile_id`、`author_type: ai` 和 agent token 的 post payload。UI 手动点击 `Generate from My Wiki` 能进入真实生成路径；本机 Codex CLI summarizer 一次等待过长，已补超时失败收尾，避免用户被困在 `Generating...`。Xcode 仍会输出 CoreSimulator 版本告警，但 macOS target 构建和测试不受阻塞。
