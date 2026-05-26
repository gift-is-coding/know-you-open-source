# My Wiki Schema 配置化执行计划

## 目标

把 My Wiki 的分类、视图和 LLM Wiki 输出契约从 Swift 硬编码中移出，改为项目级 `mywiki.schema.json` 驱动。KnowYou 继续负责导出日记、准备 schema、触发 pipeline、读取生成结果和展示 UI；正式本体抽取、关系发现、去重、总结和 agent context 依赖 `ThirdParty/llm_wiki` 的 LLM pipeline，不再用 keyword/regex/starter extractor 伪造可信本体页。

## 核心原则

- My Wiki 入口叫 `My Wiki`，不是产品名。
- `People`、`Organizations`、`Projects`、`Events`、`Topics`、`Decisions`、`Preferences`、`Follow-ups`、`Summaries`、`Sources` 是默认推荐 schema，不是产品写死的唯一 schema。
- `Recent`、`Needs Review` 是 view，不是 ontology category。
- schema 配置可以被用户项目覆盖；未来 schema editor 只需要改配置，不需要改 Swift UI。
- pipeline 不可用时写失败状态并保留已有页面，不生成降级本体页。
- 文档、spec 和 plan 使用中文维护。

## 实施步骤

### 1. Schema 配置模型

- 新增 `KnowYou/Services/MyWiki/MyWikiSchemaConfig.swift`
- 定义 `MyWikiSchemaConfig`、`MyWikiCategoryDefinition`、`MyWikiViewDefinition`
- 字段以当前实现为准：
  - `displayName`
  - `singularName`
  - `directory`
  - `legacyDirectories`
  - `frontmatterTypes`
  - `legacyTypes`
  - `extractionGuidance`
  - `detailSections`
- 默认 preset：
  - `People`
  - `Organizations`
  - `Projects`
  - `Events`
  - `Topics`
  - `Decisions`
  - `Preferences`
  - `Follow-ups`
  - `Summaries`
  - `Sources`
- 默认 `Topics` 目录为 `wiki/topics`，兼容 legacy `wiki/themes`
- 默认 `Follow-ups` 目录为 `wiki/follow-ups`，兼容 legacy `wiki/open-loops`

### 2. Project exporter

- `MyWikiProjectExporter` 创建或读取 `mywiki.schema.json`
- 按 schema 创建目录，而不是写死 `wiki/people`、`wiki/projects` 等
- 生成 `schema.md`，让 LLM Wiki headless ingest 能读取同一个输出契约
- 同步 KnowYou 日记到 `raw/sources/knowyou-diary-YYYY-MM-DD.md`

### 3. Markdown store 与 UI

- `MyWikiMarkdownStore` 从 schema 读取目录和 legacy 目录
- `MyWikiDashboardSnapshot` 保存 `schema` 和 `entriesByCategoryID`
- `MyWikiCategory` 保留兼容层，但不再作为唯一数据源
- `MyWikiPanel` 使用 schema 生成可折叠分组和 `View all`
- `MyWikiDetailView` 展示 Summary、Recent Mentions、Sources、Related、完整 Markdown 页面
- `MyWikiAgentContextProvider` 遍历 schema categories 输出 agent brief

### 4. Pipeline bridge

- `MyWikiPipelineBridge` 调用 `ThirdParty/llm_wiki` headless runner
- 默认通过 `codex-cli` provider 使用 Codex CLI 的认证与大模型能力
- 移除正式 ingest 前的 `MyWikiStarterExtractor` 调用
- pipeline missing/fail 时写 `.llm-wiki/last-ingest-status.json`
- 不生成 keyword/regex fallback ontology pages

### 5. LLM Wiki headless runner

- `ThirdParty/llm_wiki/src/headless/knowyou-ingest.ts` 读取 `mywiki.schema.json`
- 从 schema 动态生成 `<!-- KNOWYOU_MY_WIKI_OUTPUT_CONTRACT -->`
- `ThirdParty/llm_wiki/src/lib/ingest.ts` 解析 contract
- prompt 根据配置目录和 frontmatter types 生成，不再硬编码 People/Projects/Events

### 6. 文档同步

- 更新 `docs/superpowers/specs/2026-05-16-my-wiki-schema-config.md`
- 更新 `docs/superpowers/plans/2026-05-16-my-wiki-schema-config.md`
- 更新 `docs/architecture.md`
- 更新 `docs/requirements-spec.md`

## 测试计划

- Swift targeted tests：
  - `MyWikiSchemaConfigTests`
  - `MyWikiProjectExporterTests`
  - `MyWikiMarkdownStoreTests`
  - `MyWikiPipelineBridgeTests`
  - `MyWikiAgentContextProviderTests`
  - `KnowledgeOntologyPanelTests`
- LLM Wiki targeted tests：
  - `src/headless/knowyou-ingest.test.ts`
  - `src/lib/ingest.prompt.test.ts`
- 完整验证：
  - `xcodebuild test -scheme KnowYou -destination 'platform=macOS'`
  - `xcodebuild build -scheme KnowYou -destination 'platform=macOS'`

## 已完成记录

- 已新增 schema config 与默认推荐 preset。
- 已让 exporter、markdown store、UI index/detail、agent context provider 从 schema 动态读取分类。
- 已让 pipeline bridge 停止调用 starter fallback，并在失败时写入失败状态。
- 已让 LLM Wiki headless runner 和 ingest prompt 按 `mywiki.schema.json` / contract 动态生成目标目录和 frontmatter types。
- 已更新中文 spec、架构文档和需求文档。

## 后续非目标

- 本阶段不做完整 schema editor UI。
- 本阶段不重写 LLM Wiki 的 ingest、merge、search、review、vector store。
- 本阶段不自动 push；用户本地测试后再决定是否推送。
