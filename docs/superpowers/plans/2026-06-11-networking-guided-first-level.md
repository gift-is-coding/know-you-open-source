# Networking Guided First-Level Page 开发计划

## 步骤

- [x] 增加 Networking cockpit 源码测试，锁定原生 SwiftUI、三步英文引导、隐私提示、隐藏 prompt、生成式头像和两个社区名称。
- [x] 重写 `NetworkingCockpitView` 为三步式页面：生成 profile、绑定社区、查看消息线索。
- [x] 英文化 App 一级页面可见文案。
- [x] 移除一级页面上的 prompt 展示。
- [x] 用 `GeneratedFaceAvatar` 替换单字母头像表现。
- [x] 保留两个社区：`Know You Careers`、`Know You Friends`。
- [x] 接入真实 `projectRoot` 和 `summarizer`，让 `Generate from My Wiki` 走 `NetworkingProfileGenerationService`。
- [x] 实现 `NetworkingActivationStateStore.save`，让 App 端 Enable 写入 MCP 可读取的本地授权状态。
- [x] 为 `Generate from My Wiki` 增加 UI 超时失败收尾，避免底层 LLM/CLI 长时间等待时按钮永久停在生成中。
- [x] 运行源码断言覆盖页面文案、禁用模式、真实生成 wiring 和 activation 持久化。
- [x] 运行 focused XCTest。
- [x] 用用户真实 My Wiki 数据验证 context pack、未授权 MCP 拒绝、启用后 MCP payload。
- [x] 运行完整 `xcodebuild test` 和 `xcodebuild build`。

## 当前验证状态

Focused `NetworkingCockpitPresentationTests` 已在本机 macOS destination 通过，完整 `xcodebuild test` 和 `xcodebuild build` 也已通过。NetworkingWeb 的 `npm run lint`、`npm run typecheck`、`npm test -- --run`、`npm run build` 和 `npm audit --audit-level=high` 已通过。

真实用户数据 smoke 已完成：当前 My Wiki projectRoot 读取到 `838` 个 wiki markdown 和 `50` 个 raw source；`--my-wiki-context` 返回真实 citation；未开启 Networking 时 `--networking-mcp` 拒绝写入；写入本地 activation state 后 MCP 返回带 `platform_id`、`profile_id`、`author_type: ai` 和 agent token 的 post payload。UI 手动点击 `Generate from My Wiki` 能进入真实生成路径；本机 Codex CLI summarizer 一次等待过长，已补超时失败收尾，避免用户被困在 `Generating...`。Xcode 仍会输出 CoreSimulator 版本告警，但 macOS target 构建和测试不受阻塞。
