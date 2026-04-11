# Know You 隐私政策

最后更新：2026-04-11

## 1. 产品原则

Know You 是一个本地优先的 macOS 应用，目标是把你当天电脑上的零散上下文整理成按天组织的日记材料。

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

Know You 当前不提供云端账户系统，也不会默认把你的全部历史数据上传到自建服务器。

## 3. 数据来自哪里

当前版本的数据来源仅限于这台 Mac 上的本地信号：

- 系统剪贴板
- 本机 Notification Center 数据库

Know You 当前不采集浏览器历史、邮件、云端文档或其他未在产品说明中明确列出的数据源。

## 4. 隐私过滤发生在什么时候

隐私过滤发生在内容持久化之前。

这意味着：

- 明显敏感的内容不应以原文形式进入本地 SQLite
- 被判定为敏感的文本会被丢弃或脱敏
- 本地 Markdown 文件不是原始上下文的无过滤转储

当前实现会对诸如密码、令牌、私钥、Bearer Token 一类高风险文本做丢弃或脱敏处理。

## 5. 数据默认存放在哪里

默认情况下，Know You 会把运行数据存放在当前 Mac 的本地目录中。

当前默认路径包括：

- 数据库：`~/Library/Application Support/KnowYou/events.sqlite`
- Vault：`~/Library/Application Support/KnowYou/Vault`

每日输出工件包括：

- `YYYY-MM-DD.story.json`
- `YYYY-MM-DD.md`

## 6. 第三方总结器说明

Know You 可以接入外部总结器来增强日记生成质量，例如：

- OpenAI API
- Claude Code CLI
- Codex CLI
- Gemini CLI
- Openclaw CLI

这些能力是可选增强，不是首次 onboarding 和首次生成故事的前置依赖。

如果你主动配置并启用了第三方总结器，经过隐私过滤后的内容可能会被发送给对应第三方服务，以生成更好的结构化日记。你有责任理解并接受相应第三方服务自己的隐私政策和使用条款。

## 7. 你的控制权

你可以通过以下方式控制数据边界：

- 不配置任何第三方总结器，只使用本地 fallback 生成
- 在 Settings 中查看当前服务状态
- 修改 vault 路径
- 停止使用应用并删除本地数据库与导出文件

## 8. 社区与公开反馈

Know You 正在准备 Discord 社区，适合公开讨论产品想法和使用体验。

如果你的问题涉及：

- 隐私担忧
- 敏感工作内容
- 不适合公开披露的信息

请优先使用邮件联系，而不是公开发帖。

## 9. 联系方式

- X / Twitter: https://x.com/TianfuW49629
- Email: cestlouiswu@gmail.com

