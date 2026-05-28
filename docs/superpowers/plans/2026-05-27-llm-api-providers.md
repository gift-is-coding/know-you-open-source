# Diary Engine LLM API Providers 实施计划

## 交付范围

把 Diary Engine 里的 `OpenAI API` 升级为 `LLM API` provider 管理入口，并保持旧配置无感迁移。

## 步骤

1. 写配置与迁移测试。
   - 覆盖旧 `openAI` engine 到 `.llmAPI`。
   - 覆盖多 provider round-trip。
   - 覆盖 provider token 按 Keychain key 隔离。
   - 覆盖旧 URL/model/token 迁移到匹配 provider。

2. 实现 provider 配置模型。
   - 新增 `LLMAPIProviderID`、`LLMAPIWireFormat`、`LLMAPIProviderConfig`。
   - `SummarizerConfig` 增加 `activeLLMAPIProviderID` 和 provider map。
   - 保留 `apiBaseURL/apiModel/apiToken/openAIKey` 作为兼容 accessor。

3. 实现统一请求层。
   - `LLMAPIClient` 支持 OpenAI Responses、OpenAI Chat、Anthropic Messages、Gemini generateContent。
   - `CloudSummarizer` 改为通过 active provider config 构造，同时保留旧 initializer。

4. 更新状态探测与 AppState。
   - `EngineProbe` 使用 active provider 调用 `LLMAPIClient`。
   - `.openAI` 引用改为 `.llmAPI`。
   - 状态签名使用 token hash，避免 token 明文。

5. 更新 UI。
   - `APIDetailSheet` 改为 `LLMAPIDetailSheet`。
   - provider 列表展示状态灯、Active badge、OpenAI-compatible badge。
   - 支持 Save、Test Provider、Set Active。
   - wire format 只读展示，不做用户可选项。

6. 更新文档。
   - 同步 `docs/architecture.md` 和 `docs/requirements-spec.md`。

7. 验证。
   - 先跑 targeted tests。
   - 再跑全量 `xcodebuild test`。
   - 再跑 `xcodebuild build`。
   - 使用当前 DerivedData fresh build 的 `KnowYou.app` 做 GUI smoke，不重置 onboarding、auth、Keychain 或 app container。

## 风险控制

- 所有 token 只写 Keychain。
- 迁移只 add/overlay，不删除旧 Keychain key，避免回退版本丢失配置。
- Provider endpoint 组装集中在 `LLMAPIClient`，防止 UI 和探测层各写一份协议细节。
