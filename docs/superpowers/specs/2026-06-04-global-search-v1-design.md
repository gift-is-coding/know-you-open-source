# Global Search V1 设计

## 摘要

Global Search V1 是主窗口左侧一级导航中的独立 `Search` 入口，位置在 `Home` 下方。它效仿 Obsidian 的简单搜索体验，但范围是 KnowYou 的工作区级别：日记、My Wiki 实体/概念、已引入 source、统一 Todo。

这个版本只做本地关键词匹配，不引入 BM25、embedding、模型下载、云端索引、SQLite FTS 或问答合成。

## 范围

- 左侧一级导航顺序变为 `Home`、`Search`、`Networking (Coming soon)`、`Todo`、`My Wiki`、`My Diary`、`Other Source`。
- 点击 `Search` 后，主内容区显示全局搜索页，右侧 detail 栏保持隐藏。
- 搜索框输入不触发实时搜索；用户按 Enter 提交后才执行本地检索，避免每个 key stroke 反复扫描日记、source 和 My Wiki。
- 搜索范围包括：
  - `AppState.noteIndex` 中符合 `YYYY-MM-DD` day key 的日记 Markdown。
  - My Wiki dashboard 中已生成的 primary entries，也就是 `Entities` 和 `Concepts`。
  - `AppState.knowledgeDocumentsByConnector` 中已扫描 source 的 `localContentPath` Markdown/TXT 正文。
  - `AppState.todoItems` 中的 open/completed Todo 标题、normalized title、status 和 source day key。
- 搜索结果按 `Todo`、`Diary`、`My Wiki`、`Sources` 分组，显示标题、类型和 snippet。
- 点击结果后：
  - 搜索结果列表中的 title/snippet 必须直接高亮命中的关键词。
  - Todo 结果打开统一 Todo inbox，滚动到对应 todo row，并高亮 row 和 row title 中的命中关键词。
  - Diary 结果打开对应日期，滚动到第一个包含查询词的段落，并高亮段落中的命中关键词。
  - My Wiki 结果打开 My Wiki，并选中对应 entity 或 concept。
  - Source 结果打开对应 source 文档阅读页，并高亮包含查询词的 Markdown block 及其中的命中关键词。

## 非目标

- 不做 semantic search。
- 不做 embedding。
- 不下载模型。
- 不依赖服务端。
- 不做持久倒排索引或 SQLite FTS。
- 不做跨文档问答、摘要或 LLM rerank。
- 不替代 My Wiki 的 LLM 语义抽取、agent context 和 MCP 能力。

## 检索与排序

V1 使用轻量本地 lexical search：

- 查询先作为完整 phrase 匹配；有空格或标点时再拆成 token。
- 标题命中高于正文命中。
- Todo、Diary、My Wiki、Source 使用稳定优先级，保证搜索同一个关键词时用户先看到可行动待办，再看日记证据，再看整理后的 wiki 知识，最后看外部资料。
- 每条结果只返回一个 snippet。
- 空 query 返回空结果和引导态。
- 未提交的草稿 query 不触发搜索；结果、高亮和点击跳转都以最后一次提交的 query 为准。

## 验收

- 侧边栏中 `Search` 必须位于 `Home` 下方。
- `DateSidebarPresentation` 能正确提供 `searchRootItem` 和 `.search` selection action。
- `GlobalSearchService` 能用同一个关键词命中 Todo、Diary、My Wiki、Sources 四类结果。
- 搜索结果必须携带后续导航所需的 `todoID`、`dayKey`、`myWikiCategoryID`、`myWikiEntryID`、`connectorInstanceID` 和 `documentID`。
- 点击结果后目标页面必须接收 search query/target，用于一次性的关键词高亮与定位；用户手动切换侧边栏入口后应清除该高亮状态。
- 空 query 不返回结果。
- V1 不需要任何模型、embedding 文件或服务端依赖。
