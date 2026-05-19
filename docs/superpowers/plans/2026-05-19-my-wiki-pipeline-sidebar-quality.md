# My Wiki Pipeline 与 Sidebar 质量实施计划

## 任务 1: 后端 prompt 回归 LLM Wiki native 行为

- 修改 `ThirdParty/llm_wiki/src/lib/output-language.ts`，把 `auto` 模式改成 source-language mode：正文跟随 source 主语言，保留 proper nouns、产品名、工具名、缩写和英文术语原文；显式语言设置继续使用 mandatory output language。
- 修改 `ThirdParty/llm_wiki/src/headless/knowyou-ingest.ts`，移除每个 source ingest 前的 `setOutputLanguage(detectLanguage(sourceContent))`。
- 修改 `ThirdParty/llm_wiki/src/lib/ingest.ts`，更新 `INGEST_CACHE_PIPELINE_VERSION`。
- 先写失败测试，再实现：
  - `src/lib/output-language.test.ts`
  - `src/headless/knowyou-ingest.test.ts`

## 任务 2: 前端详情页显示完整 Markdown

- 修改 `MyWikiDetailPresentation`，默认不截断 `markdownBody`。
- 在 `MyWikiDetailView` 中默认渲染完整 markdown page。
- 复用轻量 markdown renderer，支持标题、段落、列表、任务、引用、代码块。
- metadata 保留 Summary、Recent Mentions、Related、Duplicate Suggestions；`Sources` 移到最后并保留点击打开 source。

## 任务 3: 左侧索引简化为 LLM Wiki 风格名称树

- 移除 `Recently active` 左侧区块。
- 移除 `View all` 和分类全量列表页。
- `Entities`、`Concepts`、`Sources` 保持顺序，`Sources` 在最后。
- 行内容只显示 name，不显示 summary 或 category badge。
- 每类默认显示 10 个；超过时显示 `Show more (N)` 原地展开全部，展开后显示 `Show less`。
- 先写失败 Swift tests，再实现：
  - `KnowledgeOntologyPanelTests.testIndexSectionPresentationSupportsInlineShowMoreStates`
  - `testIndexRowUsesSimpleNameOnlyPolicy`
  - `testIndexNavigationUsesInlineShowMoreInsteadOfFullListNavigation`
  - `testDetailPresentationShowsMarkdownPageByDefault`
  - category order regression

## 任务 4: 数据清理与小批量重跑

- 备份并清空当前 app project 下的 `wiki/entities`、`wiki/concepts`、`wiki/sources`。
- 清理 `.llm-wiki` ingest cache、queue、review、status 文件。
- 使用新 pipeline 只跑 3 篇 source。
- 抽查 1 个 entity 和 1 个 concept，确认正文丰富、sources/related 可见、英文专名保留原文。

## 任务 5: 验证与收口

- `npx vitest run src/headless/knowyou-ingest.test.ts src/lib/output-language.test.ts`
- `xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/KnowledgeOntologyPanelTests`
- `xcodebuild test -scheme KnowYou -destination 'platform=macOS'`
- `xcodebuild build -scheme KnowYou -destination 'platform=macOS'`
- 启动 `.derived-data/dev` fresh app，确认没有 stale KnowYou process。
- 更新 `docs/architecture.md` 和 `docs/requirements-spec.md`。
