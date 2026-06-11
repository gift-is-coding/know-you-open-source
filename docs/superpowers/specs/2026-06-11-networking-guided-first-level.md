# Networking Guided First-Level Page 规格

## 目标

把 App 端 Networking 一级页面从“cockpit 展示页”改成用户能理解的三步操作流。页面语言使用英文，视觉和交互保持原生 SwiftUI，不使用 WebView。

## 信息架构

1. 顶部说明 Networking 的作用：用本地 My Wiki context 生成不同场景 profile，绑定 Know You 社区，再由本地 agent 带回值得人工处理的互动。
2. 隐私提示必须在第一屏可见，明确说明会脱敏，My Wiki 原始证据、私有 draft、账号细节、深层匹配理由都留在本机。
3. Step 1: `Generate profiles`
   - 提供 `Career / Hiring`、`Friends / Social` 两个默认选项。
   - 提供 `Custom scenario` 入口。
   - prompt 不在一级页面直接展示，用户先看生成结果预览。
   - `Generate from My Wiki` 必须接入真实 `NetworkingProfileGenerationService`：读取当前 My Wiki projectRoot 的 context pack，再调用当前 App 配置的 summarizer/LLM 生成 draft。
   - My Wiki 不可用或 summarizer 未配置时，页面必须显示失败/降级状态，不能把静态 mock 当成真实生成结果。
   - profile card 不重复显示姓名，姓名只在顶部作为公共 display name 展示。
   - profile 使用生成式头像视觉，不使用单字母圆形占位。
4. Step 2: `Connect communities`
   - 社区只保留 `Know You Careers` 和 `Know You Friends`。
   - 每个社区显示当前绑定的 profile，并提供 `Change` 入口。
   - 未开启 Networking 前明确提示 agent 不能发帖或回复；开启后必须把本地 activation state 写入当前 My Wiki projectRoot，供 `--networking-mcp` 读取。
5. Step 3: `Review messages and leads`
   - 消息、入站、出站、agent activity、highlight 放在底部全宽区域。
   - 通过 community picker 查看不同社区来源。
   - 人的关键动作仍是最终决策点。

## 非目标

- 本轮不重做 Supabase schema 或 Web public square。
- MCP 仅完成 App activation state 到本地 `--networking-mcp` 的最小可测链路，真实远端发布仍以后续 Supabase RPC/agent runtime 为准。
- 本轮不实现真实 profile 编辑弹窗和社区绑定变更弹窗，只保留页面入口。
- 本轮不改变底层中文默认 scenario/model contract；只保证 App 一级页面可见文案为英文。

## 验收

- `NetworkingCockpitView` 不包含 WebKit/WebView。
- 页面包含三步英文标题、隐私脱敏提示、两个默认 profile、一个 custom profile 入口、两个社区绑定和底部消息区。
- 一级页面不显示 prompt 文本。
- 头像渲染使用生成式 face avatar，不显示 profile initials。
- Focused Networking XCTest 覆盖真实 My Wiki generation wiring、activation state 持久化、MCP 未授权/已授权 payload。
- 用用户本机真实 My Wiki projectRoot 做 smoke：context pack 能读到真实 wiki/raw 结果；未开启时 MCP 写入拒绝；开启后 MCP 能读取 activation state 并返回 AI-labeled payload。
- `xcodebuild test`、`xcodebuild build` 和 `scripts/run-dev-app.sh` 使用当前 worktree 的 fresh build。
