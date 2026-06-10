# My Wiki Search Index V1 设计

## 摘要

V1 做一个效仿 Obsidian 的本地关键词搜索入口，让用户可以在 My Wiki 内搜索日记、已 materialize 的引入资料，以及已生成的 My Wiki 页面。这个版本不引入 BM25、embedding、模型下载、云端索引或持久大型倒排索引。

核心体验是：用户在 My Wiki 搜索框输入关键词，左侧从普通 Sources/Entities/Concepts 目录切换到搜索结果列表；结果按日期或来源分组，展示命中上下文和来源类型，点击后打开对应 My Wiki 页面或 raw source 文件。

## 范围

- 搜索范围包括 `<projectRoot>/wiki/**/*.md` 和 `<projectRoot>/raw/sources/**/*.md`。
- 日记通过 `raw/sources/My Diary/knowyou-diary-YYYY-MM-DD.md` 或其他包含日期的 raw source 路径被搜索。
- 引入资料通过 `raw/sources/<connector or folder>/...` 下的 Markdown/text materialized 文件被搜索。
- 结果展示命中 snippet、来源标题、相对路径、source kind、可用日期和匹配次数。
- 查询为空时保持现有 My Wiki 目录体验，不展示搜索结果。
- 查询非空且无结果时显示轻量 empty state。
- 点击搜索结果时复用现有 source/page 打开逻辑，优先打开 My Wiki entry；raw source 结果可以通过 `MyWikiNavigationResolver` 打开原始 source 或文件。

## 非目标

- 不做 BM25。
- 不做 embedding。
- 不下载模型。
- 不新增服务端。
- 不建立 SQLite/GRDB 持久全文索引。
- 不做问答合成或 LLM rerank。
- 不搜索还没有 materialize 到 My Wiki project 的远端资料全文。

## 检索与排序

V1 使用轻量本地 lexical search：

- 查询文本拆成 phrase 和 token；中文使用现有 CJK 2-gram / 3-gram 思路。
- 标题、路径、source kind、正文命中分别加权。
- 每个文档最多返回一个最佳 snippet。
- 同一文档内命中次数越多分数越高，但单词频次 capped，避免长文档刷分。
- wiki 页面略高于 raw source；用户要找整理后的知识时优先看到 My Wiki，仍能看到原始日记/资料证据。
- 排序分数相同则按日期新到旧，再按路径稳定排序。

## UI 行为

- My Wiki 搜索框文案改为 `Search My Wiki, diaries, and sources...`。
- 查询为空：继续展示现有 category sections。
- 查询非空：显示搜索摘要和结果列表，类似 Obsidian：
  - 顶部显示 `N results`。
  - 按 day 或 top-level source group 分组。
  - 每条结果显示 snippet 和小号 metadata。
  - 命中词可先用强调色文本或加粗样式，不要求完整富文本高亮。
- 结果列表不嵌套在额外卡片中；保持 My Wiki 左侧栏的安静工具感。

## 测试与验收

- 搜索服务能找到 raw diary 和 imported source，并返回 citation/path/snippet。
- 中文查询能命中连续中文短语。
- wiki 页面在相关 raw diary 之前排序。
- character budget 和 max results 不会导致空 snippet 或 UI 崩溃。
- My Wiki presentation 在 query 非空时切到搜索模式，query 为空时保持现有目录模式。
- 相关 Swift 测试通过；最终至少跑 My Wiki 搜索相关测试切片。
