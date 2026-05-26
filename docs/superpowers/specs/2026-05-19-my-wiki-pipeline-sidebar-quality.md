# My Wiki Pipeline 与 Sidebar 质量规格

## 背景

当前 My Wiki 已经回到 llm_wiki 原生 `Sources / Entities / Concepts` schema，但用户在真实样例里看到两个问题：

- 实体页没有 LLM Wiki MVP 那种完整 markdown 页面，只显示很短 summary，导致“天阔”这类人物/实体缺少角色、贡献、挑战、相关人物等细节。
- pipeline 在 `auto` 输出语言下仍会把 Adam、Token Hub、AI OS、Codex 等英文专名强行中文化或音译，破坏可读性和可检索性。
- 左侧列表比 LLM Wiki MVP 复杂，包含近期活动、summary、badge 和全量列表跳转，用户只需要一个简单名称树。

## 目标

My Wiki 必须尽量复用 LLM Wiki MVP 的后端行为和阅读体验：

- 默认生成仍使用 native `Sources / Entities / Concepts`，不恢复 People/Projects 等硬分类。
- `auto` 输出语言跟随 source 主语言，但保留人名、产品名、工具名、缩写和英文术语原文；翻译只进入 aliases/tags/说明。
- KnowYou headless ingest 不得把 `outputLanguage` 临时改成检测到的 `Chinese`，避免触发强制转写。
- ingest cache pipeline version 必须在 prompt 修复后更新，旧缓存不能继续污染新结果。
- 详情页默认展示完整 `entry.markdownBody`，metadata 仍保留，`Sources` 放在最后。
- 左侧索引按 `Entities`、`Concepts`、`Sources` 展示；每个分类 name-only 默认 10 个，`Show more (N)` 原地展开，`Show less` 收回，不使用 `View all` 全量页。

## 非目标

- 不嵌入 React/Tauri 版 LLM Wiki UI。
- 不恢复 People/Projects/Events/Topics/Preferences 等默认生成目录。
- 不用 keyword、regex 或 starter extractor 伪造正式 ontology 页面。
- 不把旧内容静默迁移为新内容；实现后必须清空旧生成页和旧 ingest cache，再用新 prompt 小批次重跑。

## 验收

- TypeScript tests 覆盖 auto/explicit 输出语言、KnowYou prompt 和 cache pipeline version。
- Swift tests 覆盖左侧 10 条限制、inline show more/less、name-only row、无 full-list navigation、detail 默认显示 markdown body、分类顺序。
- 清理旧 `wiki/entities`、`wiki/concepts`、`wiki/sources` 和 `.llm-wiki` ingest cache/status 后，只重跑 3 篇 source。
- 抽查至少 1 个 entity 和 1 个 concept：页面有多段正文、related/sources 信息，且 Adam / Token Hub / AI OS / Codex 等专名不被强行中文化。
