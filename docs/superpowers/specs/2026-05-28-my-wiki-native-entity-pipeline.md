# My Wiki 原生 Entity Pipeline 对齐规格

## 目标

My Wiki 的 entity/concept 抽取、页面生成、合并与 review 语义必须原滋原味沿用 `ThirdParty/llm_wiki` 原生 `autoIngest`。KnowYou 只保留运行壳和展示壳，不再通过 schema、purpose、output contract、entity 标签提示或旧分类兼容逻辑改变 ontology 生成语义。

## 范围

- 保留：Source Library、进度展示、agent/MCP/context pack、source 跳转、wikilink/table 渲染、打开文件夹、rename/duplicate 合并等周边能力。
- 移除：`mywiki.schema.json`、`schema.md`、`purpose.md` 的创建/读取/渲染；People/Projects/Topics/Patterns/Follow-ups 等旧分类和旧目录读取兼容；硬编码 entity facet。
- 保留 tags：但 tags 只从生成页 frontmatter 动态读取和统计，按频次排序，不向 prompt 注入标签要求。

## 行为要求

- Swift exporter 只同步 diary Markdown 到 `raw/sources`，并确保 `wiki/sources`、`wiki/entities`、`wiki/concepts` 存在。
- Headless ingest 只负责 source 选择、provider/model、状态文件、resume/error 处理，然后调用 llm_wiki 原生 `autoIngest`。
- Swift store/UI 只读取 `wiki/sources`、`wiki/entities`、`wiki/concepts`，不读取 schema config，不兼容旧目录。
- 当前分类没有 tags 时不显示 tag 筛选。

## 验证

- JS tests 必须证明 headless ingest 不写 schema/purpose，也不把 KnowYou guidance 放进 streamed prompt。
- Swift tests 必须证明 exporter/store/UI/agent/navigation 都基于原生三目录和动态 tags。
