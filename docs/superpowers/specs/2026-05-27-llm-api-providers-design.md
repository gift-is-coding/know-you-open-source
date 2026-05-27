# Diary Engine LLM API Providers 设计规格

## 背景

当前 Diary Engine 列表里的 `OpenAI API` 实际已经承担“云端 LLM API”入口职责，但 UI、配置模型和请求层仍以单一 OpenAI Responses API 为中心。用户想接入 Anthropic、DeepSeek、OpenRouter、Gemini、DashScope、Moonshot、BigModel 或自定义 OpenAI-compatible 服务时，需要手动改 URL/model，而且状态、文档链接和格式差异都不清楚。

## 目标

- 将用户可见的 `OpenAI API` diary engine 改为 `LLM API`。
- `LLM API` 仍然是主 Diary Engine 列表中的一个 engine，但点进去是 provider 管理页。
- 用户可以配置多个 provider 的 Base URL、Model、API Token；wire format 由 provider 决定，只在 UI 中只读展示。
- 一次只有一个 active provider，Diary 生成和 engine 状态以 active provider 为准。
- 兼容旧持久化值 `openAI`、旧 `apiBaseURL/apiModel/apiToken`、旧 Keychain key。

## Provider

第一版内置这些 provider：

| Provider | Wire format | Default URL | Default model |
| --- | --- | --- | --- |
| OpenAI | `openai_responses` | `https://api.openai.com/v1/responses` | `gpt-5` |
| Anthropic | `anthropic_messages` | `https://api.anthropic.com/v1/messages` | `claude-sonnet-4-5` |
| DeepSeek | `openai_chat` | `https://api.deepseek.com` | `deepseek-v4-pro` |
| OpenRouter | `openai_chat` | `https://openrouter.ai/api/v1` | `openai/gpt-5` |
| Google Gemini | `gemini_generate_content` | `https://generativelanguage.googleapis.com/v1beta` | `gemini-3.5-flash` |
| Qwen / 通义千问 | `openai_chat` | `https://dashscope.aliyuncs.com/compatible-mode/v1` | `qwen-plus` |
| Kimi / Moonshot | `openai_chat` | `https://api.moonshot.ai/v1` | `kimi-k2.5` |
| Zhipu GLM | `openai_chat` | `https://open.bigmodel.cn/api/paas/v4` | `glm-5.1` |
| Custom OpenAI-compatible | `openai_chat` | user input | user input |

每个 provider 展示申请 key 链接和 API docs 链接。OpenAI-compatible provider 在列表中显示兼容标记。

## 数据与安全

- `LLMAPIProviderID` 标识 provider。
- `LLMAPIWireFormat` 标识请求/解析协议。
- `LLMAPIProviderConfig` 保存 provider 的 base URL、model、wire format、token，其中 wire format 是 provider 级实现细节，不作为用户可编辑选项。
- `activeLLMAPIProviderID` 保存当前实际调用 provider。
- UserDefaults 只保存 provider id、base URL、model、wire format、active id。
- API token 只进 Keychain，并按 provider 分 key 存储。
- engine 状态签名使用 provider id、base URL、model、wire format 和 token hash，不保存 token 明文。

## 请求协议

- `openai_responses`：POST 到配置 URL，body 为 `{ model, input }`，解析 `output_text` 或 `output[].content[].text`。
- `openai_chat`：POST 到 chat completions endpoint，body 为 `{ model, messages, stream:false }`，解析 `choices[0].message.content`。
- `anthropic_messages`：POST 到 messages endpoint，header 使用 `x-api-key` 和 `anthropic-version`，body 为 `{ model, max_tokens, system?, messages }`，解析 `content[].text`。
- `gemini_generate_content`：POST 到 `models/{model}:generateContent`，header 使用 `x-goog-api-key`，body 使用 `contents` / `system_instruction`，解析 `candidates[].content.parts[].text`。

## UI 行为

- 主 Diary Engine 行显示 `LLM API`。
- 点 `Configure` 打开 `LLMAPIDetailSheet`。
- 左侧 provider 列表显示状态灯、Active badge、OpenAI-compatible badge。
- 右侧显示 Base URL、Model、API Token、只读 wire format、格式说明、申请 key 和 API docs 链接。
- `Save` 保存当前 draft。
- `Set Active` 将当前 provider 设为 active；只要求字段语法完整。
- `Test Provider` 对当前 provider 做连通性测试。
- `LLM API` 总状态取 active provider：未填灰色，已填未测黄色，测试成功绿色。

## 迁移

- 旧 `.openAI` engine 持久化值加载为 `.llmAPI`。
- 旧 `apiBaseURL/apiModel/apiToken` 自动迁移到匹配 provider。
- URL 可识别 OpenRouter、DeepSeek、DashScope、Moonshot、BigModel、Anthropic、Gemini、OpenAI；无法识别时进入 Custom。
- 旧 `summarizerAPIToken` 和 `summarizerOpenAIKey` 作为迁移来源，迁移后仍兼容旧 key。

## 非目标

- 第一版不支持多 provider 自动路由、fallback、按场景选模型。
- 第一版不做 streaming。
- 第一版不在 UserDefaults 保存 token 明文。
