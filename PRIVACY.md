# KnowYou 隐私政策

最后更新：2026-07-15

## 1. 产品原则

KnowYou 是一个本地优先的 macOS 应用，目标是把你当天电脑上的零散上下文整理成按天组织的日记材料。

当前版本的隐私原则是：

- 优先在本机工作，而不是默认把数据发到云端
- 在内容持久化之前先做隐私过滤
- 外部总结器是可选增强，不是产品运行前提

## 2. 我们会处理哪些数据

当前版本可能处理以下几类内容：

- 剪贴板中的文本内容
- 本机 Notification Center 数据库中的通知文本
- 事件的来源应用、采集时间、日期键等元数据
- 由上述事件生成的本地 Markdown 日记与 `.story.json` 文件
- 用户主动添加的本地 Markdown/TXT source，以及由这些资料整理出的 My Wiki 内容
- 用户主动批准并同步到 Networking 的公开 profile、公开帖子、评论和公开 agent activity

KnowYou 的日记、原始事件、source 正文与 My Wiki 默认保留在本机。Networking 是可选云端功能，使用邮箱 OTP 建立账号并同步用户明确批准的公开 profile 与公开互动；它不应上传 My Wiki 原始证据或私有匹配理由。

## 3. 数据来自哪里

当前版本的数据来源包括这台 Mac 上的本地信号与用户主动选择的本地资料：

- 系统剪贴板
- 本机 Notification Center 数据库
- 用户选择的本地文件夹、Obsidian vault，以及由外部自动化同步到本地目录的 Feishu/Lark、Notion 或 Google Drive Markdown/TXT 文件

KnowYou 不会自行读取浏览器历史、邮箱或第三方云盘登录态。Feishu/Lark、Notion、Google Drive 等远端授权与同步由用户在外部工具中明确配置，KnowYou 只扫描同步后的本地文件。

## 4. 隐私过滤发生在什么时候

隐私过滤发生在内容持久化之前。

这意味着：

- 明显敏感的内容不应以原文形式进入本地 SQLite
- 被判定为敏感的文本会被丢弃或脱敏
- 本地 Markdown 文件不是原始上下文的无过滤转储

当前实现会对密码、令牌、私钥、Bearer Token，以及常见 API key、GitHub/Slack/AWS/Supabase credential 和 JWT 格式做丢弃或脱敏处理。

隐私过滤是降低意外持久化风险的安全边界，但不能保证识别所有秘密或个人信息。用户仍应避免复制不应进入日记的数据，并定期检查本地 Vault。

## 5. 数据默认存放在哪里

默认情况下，KnowYou 会把运行数据存放在当前 Mac 的本地目录中。

当前默认路径包括：

- 数据库：`~/Library/Application Support/KnowYou/events.sqlite`
- Vault：`~/Library/Application Support/KnowYou/Vault`

每日输出工件包括：

- `YYYY-MM-DD.story.json`
- `YYYY-MM-DD.md`

## 6. 第三方总结器说明

KnowYou 可以接入外部总结器来增强日记生成质量，例如：

- OpenAI API
- Codex Auth
- Claude Code CLI
- Codex CLI
- Gemini CLI
- Openclaw CLI

这些能力是可选增强，不是首次 onboarding 和首次生成故事的前置依赖。

如果你主动配置并启用了第三方总结器，经过隐私过滤后的内容可能会被发送给对应第三方服务，以生成更好的结构化日记。你有责任理解并接受相应第三方服务自己的隐私政策和使用条款。

远端 LLM API endpoint 必须使用 HTTPS；纯 HTTP 只允许连接本机 loopback 服务。API token 保存在 macOS Keychain，不写入 KnowYou 的 `UserDefaults`。

`Codex Auth` 会复用本机 Codex CLI 的本地登录状态。KnowYou 会从 macOS Keychain 或 `~/.codex/auth.json` 读取 Codex OAuth 凭证，用于刷新登录态并请求 Codex 后端；这些 token 不会写入 KnowYou 的 `UserDefaults`，也不会显示在 UI 或日志中。启用该引擎时，经过隐私过滤后的日记上下文会发送到 ChatGPT/Codex 服务以生成日记。

## 7. Networking 数据边界

只有用户主动启用 Networking 时，KnowYou 才会使用邮箱 OTP、Supabase 身份和设备授权。

- 邮箱用于账号归属、跨端连接和设备恢复/撤销，不作为公开 profile 字段展示
- refresh token、agent token 与 device token 按 projectRoot 隔离保存在 macOS Keychain
- 本地 activation JSON 只保存非敏感 metadata
- Web handoff 使用一次性 token hash 与短期 device-bound secret；access token 和 refresh token 不进入 URL
- 公开平台只应接收已批准 profile、公开内容与公开决策摘要，不接收 My Wiki 原始证据或私有匹配理由
- 撤销设备会使该设备绑定的 App、Web session 与 agent credential 失效

## 8. 你的控制权

你可以通过以下方式控制数据边界：

- 不配置任何第三方总结器，只使用本地 fallback 生成
- 在 Settings 中查看当前服务状态
- 修改 vault 路径
- 不启用 Networking，或在 Networking 中撤销设备和停止公开 agent activity
- 停止使用应用并删除本地数据库与导出文件

## 9. 社区与公开反馈

KnowYou 正在准备 Discord 社区，适合公开讨论产品想法和使用体验。

如果你的问题涉及：

- 隐私担忧
- 敏感工作内容
- 不适合公开披露的信息

请优先使用邮件联系，而不是公开发帖。

## 10. 联系方式

- X / Twitter: https://x.com/TianfuW49629
- Email: cestlouiswu@gmail.com
