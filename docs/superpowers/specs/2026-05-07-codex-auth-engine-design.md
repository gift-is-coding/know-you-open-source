# Codex Auth Engine 设计

## 背景

KnowYou 现在支持这些日记引擎：

- OpenAI API
- Claude Code CLI
- Codex CLI
- Gemini CLI
- Openclaw CLI

当前 `Codex CLI` 引擎通过 `codex exec` 启动子进程。这个路径可靠，也比较稳定，但每次请求都要付出进程启动、CLI 初始化、prompt 传递、schema/output 文件处理、终端输出归一化这些成本。

OpenClaw 里实现了一条更快的 Codex 通道：它不通过 Codex CLI 子进程生成内容，而是复用本机 Codex CLI 的 ChatGPT OAuth 登录态，然后直接请求 Codex backend。

我在 OpenClaw 源码里确认到的关键行为是：

- 解析 `CODEX_HOME`，没有时回退到 `~/.codex`。
- macOS 上优先读 Keychain，service 是 `Codex Auth`，account 是 `cli|sha256(realCodexHome).prefix(16)`。
- Keychain 读取失败时，回退读取 `<codexHome>/auth.json`。
- 从 auth record 里提取 `tokens.access_token`、`tokens.refresh_token` 和可选的 `tokens.account_id`。
- 从 access token JWT 里解析 token 过期时间和 `chatgpt_account_id`。
- token 过期时，通过 `https://auth.openai.com/oauth/token` refresh。
- 最后调用 `https://chatgpt.com/backend-api/codex/responses`，使用 Codex 专用 headers 和 Responses 风格的 streaming request body。

KnowYou 应该新增同类能力，但作为一个独立 diary engine，而不是替换现有 `Codex (CLI)`。

## 目标

新增一个独立的 `Codex Auth` 日记引擎。它和其他引擎平行存在，复用用户本机已有的 Codex ChatGPT OAuth 登录态，直接调用 Codex backend。

新引擎的语义必须清晰：

- `Codex (CLI)` 继续调用 `codex exec`。
- `Codex Auth` 读取 Codex OAuth 凭证并直连 Codex backend。
- 两个 engine 互不替换，也不在用户不知情时静默切换。

## 非目标

- 不移除、不重写现有 `Codex (CLI)`。
- 第一版不做 `Codex Auth` 到 `Codex (CLI)` 的自动 fallback。
- 不把 Codex access token 或 refresh token 存进 KnowYou 的 `UserDefaults`。
- 不在 UI 或日志里展示 access token、refresh token、account id 或原始 auth record。
- 不在 KnowYou 里实现新的浏览器 OAuth 登录流程。第一版只复用本机已经存在的 Codex CLI 登录态。
- 不让 `Codex Auth` 自动压过已有的绿色 engine 成为默认项。

## 用户体验

Settings 和 diary engine selector 里新增一个 engine：

```text
Codex Auth
```

`Codex Auth` 的配置区不需要 API key，也不需要 CLI path。配置说明应明确告诉用户：KnowYou 会复用这台 Mac 上的本地 Codex 登录态。

Probe 状态：

- 灰色：没有找到可用的 Codex 登录态。
- 黄色：找到了凭证，但 refresh 或 backend 验证失败。
- 绿色：KnowYou 成功通过 Codex Auth 发出 smoke test，并收到非空文本响应。

当 `Codex Auth` 被选为默认引擎时，它和其他 `SummaryGenerating` 引擎一样参与日记生成。如果生成失败，应用层继续使用现有 daily story fallback 规则；但这不是 engine 间自动 fallback。

## 架构

在 `DiaryEngine` 中新增：

```swift
case codexAuth
```

在 `KnowYou/Services/Summary/` 下新增四个职责清晰的组件：

- `CodexAuthStore`：发现并读取 Codex 凭证，来源是 Keychain 或 `auth.json`。
- `CodexOAuthRefresher`：刷新过期 OAuth 凭证，并在可能时写回同一个 Codex 存储来源。
- `CodexJWT`：解析 access token payload，提取过期时间和 `chatgpt_account_id`。
- `CodexDirectSummarizer`：向 Codex backend 发送 KnowYou 的总结 prompt，并返回最终文本。

边界要求：

- auth discovery 不理解日记 prompt。
- token refresh 不理解 UI 状态。
- JWT parser 不做网络或文件系统操作。
- summarizer 只向 auth provider 请求一份有效凭证，然后执行 Codex backend 请求。

## 凭证发现

`CodexAuthStore` 按以下顺序解析 Codex home：

1. 如果 `environment["CODEX_HOME"]` 非空，展开并解析它。
2. 否则使用 `~/.codex`。
3. 如果路径存在，使用 real path 推导 Keychain account；否则使用展开后的路径。

macOS 上先读 Keychain：

```text
service: Codex Auth
account: cli|sha256(realCodexHome).prefix(16)
```

Keychain secret 预期是一个 JSON auth record，至少包含：

```json
{
  "auth_mode": "chatgpt",
  "tokens": {
    "access_token": "...",
    "refresh_token": "...",
    "account_id": "..."
  }
}
```

如果 Keychain 读取失败，再读：

```text
<codexHome>/auth.json
```

auth file 只有在满足这些条件时才接受：

- JSON 解析成功。
- `auth_mode` 缺失或等于 `chatgpt`；现代 Codex 登录态预期为 `chatgpt`。
- `tokens.access_token` 是非空字符串。
- `tokens.refresh_token` 是非空字符串。

最终得到的 credential 包含：

- `accessToken`
- `refreshToken`
- `expiresAt`
- `accountID`
- `source`

`source` 标记凭证来自 Keychain 还是 auth file，并保存刷新后写回原来源所需的信息。

## JWT 解析

`CodexJWT` 使用 base64url 规则解码 JWT payload，提取：

- `exp`：token 过期时间，单位是 Unix seconds。
- `https://api.openai.com/auth.chatgpt_account_id`：ChatGPT account id。

如果 JWT 里没有 `exp`，`CodexAuthStore` 使用保守的一小时过期估计。估计基准按优先级取：

1. auth record 的 `last_refresh`
2. auth file 的 mtime
3. 当前时间

如果缺少 `chatgpt_account_id`，`Codex Auth` 视为不可用。Codex backend 请求依赖 `chatgpt-account-id` header，因此不能猜测，也不能用 UI 上看到的账号信息代替。

## Token Refresh

每次 probe 或总结请求前，`CodexDirectSummarizer` 都需要拿到一份有效 credential。

如果 credential 仍在有效期内，并且距离过期还有安全余量，就直接使用。

如果 credential 已过期或接近过期，`CodexOAuthRefresher` 发送：

```http
POST https://auth.openai.com/oauth/token
Content-Type: application/x-www-form-urlencoded

grant_type=refresh_token
refresh_token=<refresh token>
client_id=app_EMoamEEZ73f0CkXaXp7hrann
```

响应必须包含：

- `access_token`
- `refresh_token`
- `expires_in`

刷新后的 access token 需要再次解析并确认包含 `chatgpt_account_id`。

refresh 成功后：

- 如果来源是 Keychain，更新同一个 `Codex Auth` Keychain item。
- 如果来源是 `auth.json`，更新同一个文件。
- 保留原 auth record 中无关字段。
- 如果 `auth_mode` 缺失，则设置为 `chatgpt`。
- 设置 `last_refresh` 为当前 ISO timestamp。

refresh 失败时，不写入任何半成品凭证。

## Codex Backend 请求

`CodexDirectSummarizer` 请求：

```text
https://chatgpt.com/backend-api/codex/responses
```

Headers：

```text
Authorization: Bearer <accessToken>
chatgpt-account-id: <accountID>
originator: pi
OpenAI-Beta: responses=experimental
accept: text/event-stream
content-type: application/json
```

第一版沿用 OpenClaw 的 `originator: pi`，优先保证 backend 兼容性。

请求体使用 Codex Responses 形状：

```json
{
  "model": "gpt-5.4",
  "store": false,
  "stream": true,
  "instructions": "You are KnowYou's diary writer...",
  "input": [
    {
      "role": "user",
      "content": [
        {
          "type": "input_text",
          "text": "KnowYou prompt text"
        }
      ]
    }
  ],
  "text": { "verbosity": "medium" },
  "include": ["reasoning.encrypted_content"],
  "tool_choice": "auto",
  "parallel_tool_calls": true,
  "reasoning": {
    "effort": "high",
    "summary": "auto"
  }
}
```

第一版只实现 SSE，通过 `URLSession.bytes(for:)` 读取流。WebSocket 支持不在本次范围内。

summarizer 消费 SSE `data:` events，直到看到 completed response event。最终文本提取语义与 `CloudSummarizer` 一致：优先使用 `output_text`，否则拼接 message content 中 `type == "output_text"` 的文本。

## 配置

`SummarizerConfig` 不为 `Codex Auth` 存 token。

本功能唯一需要持久化的是用户选择的默认 engine；这已经由 `SummarizerConfig.defaultEngine` 负责。

模型选择等配置可以未来再加。第一版先硬编码一个与 OpenClaw 当前 Codex provider 行为一致的保守默认模型。

## Engine Probe

`EngineProbe` 为 `.codexAuth` 新增独立分支。

probe 流程：

1. 解析一份有效 Codex credential。
2. 必要时刷新 token。
3. 发送一个小型 Codex backend 请求，输入为 `Reply with OK.`
4. 如果成功解析出非空文本，返回绿色。

probe detail 不得包含 token、account id、原始 Keychain 错误、原始 backend 响应体。

## 安全与隐私

`Codex Auth` 是第三方总结器路径。用户选择它后，经过隐私过滤和 prompt 裁剪后的 diary material 会发送到 OpenAI/ChatGPT Codex backend。

必须遵守这些保护：

- 永不记录 access token、refresh token、account id、auth JSON 或 Authorization header。
- 不把 Codex 凭证存进 KnowYou 自己的设置。
- token refresh 只写回原始 Codex 存储来源。
- UI 文案明确说明该 engine 复用本机 Codex 登录态。
- 继续保证所有 summarizer 调用前都经过现有隐私过滤和 prompt budget 裁剪。
- 更新隐私文档，说明 `Codex Auth` 是一个可选外部总结器。

## 错误处理

内部使用 typed errors，最终映射成安全的用户可读信息。

预期不可用情况包括：

- Codex home 不存在。
- Keychain item 不存在，且 `auth.json` 也不存在。
- auth record 格式错误。
- access token 缺少 account id。
- refresh token 缺失。
- refresh 请求被拒绝。
- backend 请求被拒绝。
- SSE 响应格式错误或没有文本。

用户可见信息应说明恢复路径：

- 登录态缺失或过期时，提示用户重新登录 Codex CLI。
- 登录后重新测试 engine。
- 如果 direct Codex Auth 仍不可用，用户可以手动选择 `Codex (CLI)` 或其他 engine。

## 测试

测试不能读取开发者真实 Keychain，也不能读取真实 `~/.codex`。

需要新增这些 focused tests：

- `CodexJWTTests`
  - 能解析 `exp`。
  - 能解析 `chatgpt_account_id`。
  - 能拒绝 malformed token。

- `CodexAuthStoreTests`
  - 能从固定 Codex home path 计算 Keychain account。
  - Keychain JSON 优先于 auth file JSON。
  - Keychain 缺失时 fallback 到 auth file JSON。
  - 拒绝 malformed 或 incomplete auth record。
  - 构造 refreshed auth record 时保留无关字段。

- `CodexOAuthRefresherTests`
  - 发送 form-encoded refresh request。
  - 解析 refreshed credentials。
  - 拒绝缺少必需字段的响应。
  - 错误信息不暴露 token 值。

- `CodexDirectSummarizerTests`
  - 发送正确 URL 和 headers。
  - 请求体包含 `store: false` 和 `stream: true`。
  - 能把 SSE completion 解析成 output text。
  - 空响应会作为失败处理。

- `SummarizerConfigTests`
  - `.codexAuth` 能作为 default engine round-trip。
  - `makeSummarizer(for: .codexAuth)` 返回 `CodexDirectSummarizer`。

- `EngineProbeTests`
  - 缺少 auth 返回灰色。
  - refresh 或 backend 失败返回黄色。
  - backend smoke test 成功返回绿色。

## 文档更新

实现时同步更新：

- `docs/architecture.md`：生成层和 engine status 行为中加入 `Codex Auth`。
- `docs/requirements-spec.md`：可选 diary engine 列表中加入 `Codex Auth`。
- `PRIVACY.md`：说明 `Codex Auth` 是可选外部总结器，并复用本机 Codex 登录态。

## 风险

`https://chatgpt.com/backend-api/codex/responses` 不是稳定公开 OpenAI API。实现必须把这条路径隔离在 `CodexDirectSummarizer` 中，并保留 `Codex (CLI)` 作为独立 engine。

OAuth client 行为未来可能变化。KnowYou 不应隐藏这个风险。如果 refresh 或 backend 调用开始失败，engine 应变成黄色，而不是污染凭证或静默切换通道。

Codex OAuth 凭证高度敏感。实现必须至少按 API key 的安全级别处理它们；因为这些凭证来自另一个工具的登录态，日志纪律应更严格。

## 已确认范围

本设计实现产品讨论中的方案 2：`Codex Auth` 是一个独立通道，与其他 diary engine 平行。
