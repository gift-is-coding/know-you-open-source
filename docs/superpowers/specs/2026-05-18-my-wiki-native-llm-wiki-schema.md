# My Wiki 原生 LLM Wiki Schema 设计

## 背景

当前 My Wiki 已经把正式页面生成交给 `ThirdParty/llm_wiki` headless ingest，但 KnowYou 仍在默认 `mywiki.schema.json` 和 `schema.md` 中强制输出 People、Organizations、Projects、Events、Topics、Decisions、Patterns、Follow-ups、Summaries、Sources 等个人本体分类。

这导致两个问题：

- 日记是按天逐个 source ingest 的，强分类会把每天的零散线索拆成大量薄页面，尤其是 projects、topics、follow-ups。
- llm_wiki 原生能力主要围绕 `wiki/entities/`、`wiki/concepts/`、`wiki/sources/`、page merge、dedup、wikilink 和 overview 运行；KnowYou 的强分类 contract 让 dedup/review 等能力无法完整复用。

用户确认的新方向是：尽量复用 llm_wiki 的原生 pipeline；如果 People/Projects 等分类显得强行，就直接使用 llm_wiki 原生结构，KnowYou 最多加轻量标签和来源元信息。

## 目标

让 KnowYou 的 My Wiki 默认回到 llm_wiki 原生 wiki 结构：

- `wiki/sources/` 保存每篇日记的 source summary。
- `wiki/entities/` 保存重要人物、组织、工具、产品、项目等实体页面。
- `wiki/concepts/` 保存主题、模式、方法、偏好、问题和长期背景等概念页面。
- `wiki/index.md`、`wiki/overview.md`、`wiki/log.md` 继续由 llm_wiki ingest 维护。
- KnowYou 导出的 source 加轻量 frontmatter/tag，例如 `source: KnowYou`、`tags: [knowyou, diary]`，但不要求模型把内容强塞到 People/Projects/Events 等固定分类。

## 非目标

- 不把 My Wiki 降级成只浏览 raw source 的文件列表。
- 不删除 llm_wiki 的 entity/concept 抽取、page merge、dedup、review、wikilink 和 overview 能力。
- 不在这一轮实现完整 schema editor。
- 不把旧 People/Projects 页面做破坏性删除；迁移和清理必须有备份或显式重建流程。

## 设计

### Schema

默认 `mywiki.schema.json` 改成原生 llm_wiki 风格：

- Sources: `wiki/sources`, type `source`
- Entities: `wiki/entities`, type `entity`
- Concepts: `wiki/concepts`, type `concept`

为了让旧项目平滑过渡，默认 schema 仍在读取层声明 legacy directories：

- Entities legacy directories: `wiki/people`、`wiki/organizations`、`wiki/projects`、`wiki/events`
- Concepts legacy directories: `wiki/topics`、`wiki/decisions`、`wiki/preferences`、`wiki/follow-ups`、`wiki/summaries`

`schema.md` 不再包含 `KNOWYOU_MY_WIKI_OUTPUT_CONTRACT`，也不再禁止 `wiki/entities/` 和 `wiki/concepts/`。这样 `ThirdParty/llm_wiki/src/lib/ingest.ts` 会走原生 generation targets，而不是 My Wiki custom contract。

为了保留 KnowYou 语义，`purpose.md` 和 raw source frontmatter 继续说明这些 source 来自 KnowYou 日记，生成内容需要保持可追溯、少量高信号、避免暴露 secrets。

### Export

`MyWikiProjectExporter` 继续负责：

- 创建项目目录。
- 同步 `YYYY-MM-DD.md` 到 `raw/sources/knowyou-diary-YYYY-MM-DD.md`。
- 写入 KnowYou source frontmatter。

导出的 source frontmatter 增加轻量 tags：

```markdown
---
type: knowyou-diary
source: KnowYou
day: 2026-05-18
tags: [knowyou, diary]
---
```

### Ingest

`MyWikiPipelineBridge` 继续调用 llm_wiki headless runner。headless runner 仍可读取 `mywiki.schema.json`，但默认 schema 不再触发 custom output contract。

缓存策略必须跟随 schema/purpose/pipeline 版本变化失效。否则旧的 People/Projects 强分类结果会因为 source hash 未变而一直 cache hit。实现采用 cache key/signature 方案：保存和检查 ingest cache 时，hash 输入必须包含 source content、`schema.md`、`purpose.md` 和一个显式 pipeline cache version。

### Reading/UI

Swift UI 继续叫 `My Wiki`，继续从 `mywiki.schema.json` 读取 categories，而不是写死 enum。

默认显示分组变为：

- Sources
- Entities
- Concepts

详情页继续显示 title、summary、sources、related、markdown body。用户可见文案避免过度强调 “ontology”；`Entities` 和 `Concepts` 是 llm_wiki 的原生分组名，可以保留。

空状态、详情占位、首页说明和重复项复核提示也必须使用 `Sources`、`Entities`、`Concepts` 这套默认模型；不应再把默认 My Wiki 描述成 `People / Projects / Topics / Patterns / Follow-ups` 的强分类工作台。

### Dedup

复用 llm_wiki 原生 dedup 路径，因为它本来扫描 `wiki/entities` 和 `wiki/concepts`。Swift 侧的 `MyWikiDuplicateService` 可以继续作为轻量 fallback，但默认 schema 回归后，应优先让后续工作接入 `ThirdParty/llm_wiki/src/lib/dedup-runner.ts` 或至少不再阻断其适用目录。

## 数据迁移与重建

已有用户项目可能已经存在强分类目录：

- `wiki/people`
- `wiki/organizations`
- `wiki/projects`
- `wiki/events`
- `wiki/topics`
- `wiki/decisions`
- `wiki/preferences`
- `wiki/follow-ups`
- `wiki/summaries`

本轮实现不自动删除这些目录。推荐行为：

1. 新默认 schema 只创建/读取 native categories。
2. 旧目录作为 legacy 目录读取，避免用户立刻看不到历史页面。
3. cache signature 自动让旧强分类 ingest cache 失效；用户可以在备份后手动清空 generated wiki，再用 native schema 全量重跑。

在开发验证中，可以手动清理测试项目的 `wiki/` 生成目录和 `.llm-wiki/ingest-cache.json`，然后重跑 ingest，比较 native 输出质量。

## 测试策略

Swift 层：

- `MyWikiSchemaConfigTests` 验证默认 schema 只包含 Sources、Entities、Concepts。
- `MyWikiProjectExporterTests` 验证项目结构创建 native 目录，不再默认创建 People/Projects 等强分类目录。
- `MyWikiProjectExporterTests` 验证导出的 source frontmatter 包含 KnowYou tags。
- `MyWikiMarkdownStoreTests` 验证 dashboard 可读取 native categories，并可兼容 legacy 目录。

TypeScript 层：

- `knowyou-ingest.test.ts` 验证默认 schema 不再注入 `KNOWYOU_MY_WIKI_OUTPUT_CONTRACT`。
- `knowyou-ingest.test.ts` 验证没有 custom contract 时 ingest prompt 会允许 `wiki/entities` 和 `wiki/concepts`。
- cache 测试覆盖 schema/purpose 变化后不应复用旧 cache。

文档层：

- `docs/architecture.md` 和 `docs/requirements-spec.md` 更新 My Wiki 章节，删除“默认必须包含 People/Projects/Events”等强分类要求。
- 保留“正式生成必须使用 llm_wiki LLM pipeline，不允许 keyword/starter extractor 伪造可信页面”的要求。

## 验收标准

- 新建 My Wiki 项目默认目录包含 `wiki/sources`、`wiki/entities`、`wiki/concepts`，不再默认创建 People/Projects/Events 等强分类目录。
- `schema.md` 默认不包含 `KNOWYOU_MY_WIKI_OUTPUT_CONTRACT`，也不禁止 `wiki/entities/` 或 `wiki/concepts/`。
- KnowYou source frontmatter 包含 `tags: [knowyou, diary]`。
- headless ingest 默认走 llm_wiki 原生 entity/concept/source generation targets。
- 默认 My Wiki 重跑每次最多处理 3 个 source；限定批量时优先处理尚未生成 `wiki/sources/<source>.md` 的最新 raw source，避免反复覆盖同几篇。
- 默认首页索引先显示 `Entities`、`Concepts`，`Sources` 放最后；`Entities` 和 `Concepts` 展开时最多显示 10 个。
- ingest cache 的 hash/signature 包含 source content、schema、purpose 和 pipeline cache version；旧强分类 cache 不会让 native schema 重跑短路。
- Swift targeted tests 和 llm_wiki targeted tests 通过。
- 默认 My Wiki 用户可见说明、占位和重复项提示不再出现旧的 People/Projects/Topics/Patterns/Follow-ups 分类串。
