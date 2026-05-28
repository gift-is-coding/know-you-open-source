# My Wiki 原生 Entity Pipeline 对齐执行计划

## 目标

把 KnowYou My Wiki 的 entity/concept pipeline 收敛为 llm_wiki 原生 `autoIngest`，同时保留不影响 ontology prompt 的产品周边能力。

## 步骤

- [x] 增加 RED 测试，覆盖 JS headless ingest、Swift exporter、Markdown store、UI index/tag facet、agent brief 和 related navigation。
- [x] 删除 `MyWikiSchemaConfig`、schema markdown renderer、schema tests 和 Xcode project 引用。
- [x] 修改 exporter：只创建 `raw/sources` 与原生 wiki 三目录，删除旧 prompt context 文件，raw diary 不再加 KnowYou frontmatter。
- [x] 修改 headless ingest：只做运行壳，删除旧 KnowYou prompt context，直接调用原生 `autoIngest`，并 bump cache version。
- [x] 修改 store/snapshot/UI：只读取原生三目录；删除旧 category accessors；用动态 `MyWikiTagFacet` 取代硬编码 entity facet。
- [x] 保留周边能力：Source Library、progress、agent/MCP/context pack、source navigation、wikilink/table rendering、rename/duplicate review。
- [x] 更新 architecture 和 requirements 文档。
- [x] 运行 targeted Vitest、targeted Xcode tests、typecheck、最终 Xcode build。

## 验证命令

```bash
cd ThirdParty/llm_wiki && npx vitest run src/headless/knowyou-ingest.test.ts src/lib/ingest.prompt.test.ts
cd ThirdParty/llm_wiki && npm run typecheck
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/MyWikiProjectExporterTests -only-testing:KnowYouTests/KnowledgeOntologyProjectExporterTests -only-testing:KnowYouTests/MyWikiMarkdownStoreTests -only-testing:KnowYouTests/KnowledgeOntologyPanelTests -only-testing:KnowYouTests/MyWikiAgentContextProviderTests -only-testing:KnowYouTests/MyWikiNavigationResolverTests
xcodebuild build -scheme KnowYou -destination 'platform=macOS'
```
