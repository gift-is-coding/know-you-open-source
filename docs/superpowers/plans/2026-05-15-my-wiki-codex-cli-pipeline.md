# My Wiki Codex CLI Pipeline 计划

## 目标

把 My Wiki 后端从“假数据可用”推进到“真实 LLM Wiki pipeline 可运行、失败透明”。这一步先服务开发 worktree：通过 `ThirdParty/llm_wiki` 源码运行 headless runner，并用 Codex CLI 做本地 LLM provider。

## 工作项

1. 调研 LLM Wiki 的 CLI 接入方式。
   - 确认 Claude Code CLI 只作为 LLM provider transport。
   - 找出 ingest、merge、dedup、chunker 的实际代码入口。

2. 为 LLM Wiki 增加 Codex CLI provider。
   - 扩展 `LlmConfig.provider` 类型。
   - 设置页新增 `Codex CLI (local)` preset。
   - Codex CLI 不要求 API Key。
   - LLM client 根据 provider 分发到 `codex-cli-transport`。
   - Tauri 新增 `codex_cli_detect` 和 `codex_cli_complete`。

3. 改造 KnowYou bridge 的失败逻辑。
   - 高级 pipeline 不可用时写失败状态，但保留本地 starter extractor 生成的可审计起始页。
   - 写入 `.llm-wiki/last-ingest-status.json`。
   - 开发源码可用时调用 `npm run knowyou:ingest`。
   - 抛出明确错误，供 UI 显示真实失败。

4. 增加 headless runner。
   - 用 Vite SSR 加载 LLM Wiki `autoIngest`，避免重写 pipeline。
   - 提供 Node FS adapter。
   - 提供 headless Tauri core/event adapter。
   - 用 Codex CLI 执行 `codex exec --output-last-message`。
   - 注入 KnowYou My Wiki 输出契约，禁止 `wiki/entities` 和 `wiki/concepts`。

5. 测试优先。
   - LLM Wiki：`hasUsableLlm` 覆盖 `codex-cli`。
   - LLM Wiki：`getProviderConfig` 对 `codex-cli` 抛 subprocess transport 错误。
   - KnowYou：pipeline 不可用时不会物化 starter pages。
   - KnowYou：pipeline 缺失时会写失败状态。
   - LLM Wiki：headless runner 复用 `autoIngest` 生成 wiki 页面。
   - KnowYou：development source runner 会被正确调用，失败会写状态。

6. 验证。
   - `npm run typecheck`
   - `npm run test:mocks -- src/lib/has-usable-llm.test.ts src/lib/__tests__/llm-providers.test.ts`
   - `npm run test:mocks -- src/headless/knowyou-ingest.test.ts src/lib/has-usable-llm.test.ts src/lib/__tests__/llm-providers.test.ts`
   - `npm run build`
   - `cargo check`
   - `xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/MyWikiPipelineBridgeTests`
   - `xcodebuild build -scheme KnowYou -destination 'platform=macOS'`
   - `xcodebuild test -scheme KnowYou -destination 'platform=macOS'`
   - 真实 Codex CLI smoke：临时项目 + 一篇日记 + `npm run knowyou:ingest`

7. My Wiki prompt 与真实 smoke 修正。
   - 检测 `KNOWYOU_MY_WIKI_OUTPUT_CONTRACT` 后，generation prompt 不再要求 `wiki/entities` 和 `wiki/concepts`。
   - My Wiki generation prompt 改为 People/Projects/Topics/Patterns/Follow-ups/Sources/Overview。
   - 明确 Codex、Claude、ChatGPT、Gemini、Openclaw、Cowork 等默认是 AI 工具、agent、CLI 或 workflow，不生成 People 页面。
   - 真实 Codex CLI 单篇 smoke 超过 6 分钟未完成，记录为当前不可接受的吞吐问题，而不是写假成功。
   - 后续需要把真实 pipeline 做成后台队列，并考虑降低每篇调用次数、批处理多篇、缩短 prompt、或改用更适合的直接 API/结构化输出。

8. 本地 starter extractor 语义修正。
   - [x] 增加 Events 分类，避免把具体会议、面试、申请混入 Projects 或 Topics。
   - [x] starter extractor 同时读取 `raw/sources` 和 legacy `wiki/sources`，按文件名去重。
   - [x] 移除通用人名正则，改为保守候选，避免把工具、公司、UI 文案误抽为 People。
   - [x] 删除旧 starter 生成的 `Codex/Claude/Cowork` People/Project 页面。
   - [x] 规范化旧页面 frontmatter：`entity/concept/query` 迁移到 My Wiki 目录对应类型。
   - [x] 证据优先使用命中实体关键词的原始行，避免实体页显示泛化日记摘要。
   - [x] 在真实 KnowYouContext 上运行抽取并审计分类结果。

## 验收标准

- Codex CLI provider 能通过类型检查和 provider 单测。
- Tauri Rust 命令能编译。
- Headless runner 能在测试中复用 `autoIngest`。
- KnowYou bridge 测试证明高级 pipeline 不会假装成功，并且会调用 development runner；同时本地 starter extractor 会先生成可审计 My Wiki 页面。
- 真实 Codex CLI smoke 如果不能在可接受时间内生成页面，必须保留失败/未完成证据，不允许回退到 starter extractor 假数据。

## 下一阶段计划

下一阶段做质量和产品化：

- 接入 LLM Wiki `dedup-runner` 到 My Wiki 的主动发现。
- 对多篇日记做批处理进度、取消、恢复和失败重试。
- 用真实 KnowYou 日记评估抽取质量，收紧 schema 和 prompt。
- 将 development runner 产品化为 bundled helper。
