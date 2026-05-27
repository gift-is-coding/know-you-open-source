# My Wiki Source Catalog 设计

## 摘要

My Wiki 需要在 KnowYou 可用文档和 `llm_wiki` ingest 管线之间增加一层长期有效的 source 选择层。现在的 Source Library 更像一个导入篮子：复制到 `raw/sources` 的文件会被 ingest 使用，是否已处理主要靠 `wiki/sources` 下是否有同名页面来推断。

新的 Source Catalog 会把它升级成一个可治理的资料目录。它按自然层级列出 KnowYou diary 和 external source 文档，让用户长期选择哪些资料可以进入 My Wiki，并且只处理已选择且新增或变更过的 source。

## 目标

- 展示一个 My Wiki source catalog，包含 KnowYou diary Markdown 和 external source 文档。
- 保留 source 层级。一个 source root 可以包含文件夹和嵌套文件，UI 不能把这个结构压平成简单列表。
- 持久保存用户对每个 source 的 `included in My Wiki` 选择。
- 新增 diary 默认 included，但用户可以取消任何 diary。
- 新增 external source 默认不 included，直到用户主动选择。
- 清楚标记处理状态：not included、pending、indexed、changed、excluded indexed、failed。
- 已 indexed 且内容没有变化的 source，即使仍然 included，也不再重复处理。
- 仅仅因为 source 被取消选择，不删除旧的 wiki 输出。
- 把目录上下文传给 `llm_wiki`，让嵌套 source 保留有用的来源语境。

## 非目标

- 不在 source 被取消选择时自动清理 entity 或 concept 页面。
- 不从 My Wiki catalog 编辑 external source 原文件。
- 不替换现有 Other Source 连接器管理页。
- 不要求为此功能接入云 API。Catalog 基于已经扫描到本地的文档 metadata 工作。
- 不因为 external source 出现在 catalog 里，就静默 ingest 所有 external source。

## 产品模型

所有可用文档都是候选资料。Included 的文档才是 My Wiki sources。已 included 且内容变更的文档进入待重新处理状态。

每个 source 有两类相互独立的状态：

- Inclusion state：用户是否允许 My Wiki 使用这个 source。
- Processing state：这个 source 是否需要基于上次成功处理记录和内容 hash 重新 ingest。

长期默认规则：

- 新 diary source：默认 included。
- 已存在 diary source：保留用户之前的 include 或 exclude 选择。
- 新 external source：默认 not included。
- 已存在 external source：保留用户之前的 include 或 exclude 选择。
- 取消选择一个以前 indexed 的 source，不删除 `wiki/sources` 或由它派生出的 entity/concept 页面。
- 重新选择一个以前 indexed 且未变化的 source，不强制重新处理。

## Catalog 层级

Source Catalog 必须镜像用户在 My Wiki 外部已经看到的层级。

顶层 root 包括：

- My Diary
- Local Folder connector instances
- Obsidian connector instances
- Feishu Docs connector instances
- Notion connector instances
- Google Drive connector instances
- 手动导入的 My Wiki source folders

每个 root 可以包含文件夹和文件。Local Folder、Obsidian、Google Drive、手动导入的 source folder 必须保留嵌套路径。Feishu 和 Notion 如果 metadata 能表示文档树，也应该保留树结构；如果暂时不能，可以先作为 connector root 下的分组文档列表。

目录行是可选择的控制节点：

- 选择一个目录，默认选择当前可见的 descendant files。
- 取消一个目录，默认取消当前可见的 descendant files。
- 子文件可以覆盖目录默认选择。
- 当 descendants 部分 included、部分 excluded 时，目录显示 mixed state。
- 批量操作作用于当前筛选后可见的树，而不是隐藏行。

Catalog 应保留类似 `Projects/AI/notes.md` 的相对路径。这个路径既用于显示，也会作为 ingest 的 folder context。

## UI 行为

现有 My Wiki `Source Library` sheet 会从纯文件导入弹窗升级为 catalog manager。

主布局需要支持：

- 分层 source tree 或 outline。
- 按标题、文件名、路径、connector 名称搜索。
- 按 source root、source type、processing state 过滤。
- 每行一个 inclusion checkbox。
- 目录行支持三态选择。
- 显示 all、included、pending、changed、failed 的数量。
- 批量 include visible、exclude visible、invert visible。
- 在可用时打开 source 原文或已生成的 source summary。

每个 source file row 显示：

- 标题或文件名。
- 相对路径。
- Source root 或 connector 名称。
- 可用时显示 source 最后更新时间。
- Inclusion checkbox。
- Processing badge。
- 可选的 generated summary 链接。

Processing badges：

- `Not included`：候选文档，未被 My Wiki 使用。
- `Pending`：已 included，但从未成功 indexed。
- `Indexed`：已 included，且 indexed hash 与当前内容一致。
- `Changed`：已 included，但上次成功 indexed 后内容发生变化。
- `Excluded, indexed`：当前 excluded，但以前已有 My Wiki 输出。
- `Failed`：上次处理失败。

## 数据模型

新增一个 My Wiki 专属 source catalog 状态，和 external source connector config 分开。它可以保存在 My Wiki project folder 中，让选择状态随项目迁移：

`<projectRoot>/.knowyou/source-catalog.json`

持久状态记录用户选择和处理 checkpoint，不复制完整文档内容。

每个 source identity 建议字段：

- `sourceID`：稳定身份，由 source kind、connector instance、remote ID 或 diary day key 推导。
- `sourceKind`：diary、external-document、manual-file。
- `connectorInstanceID`：可选。
- `connectorID`：可选。
- `displayTitle`。
- `relativePath`。
- `sourcePath`：本地 source 的绝对路径。
- `sourceURL`：可选 remote URL。
- `contentHash`。
- `remoteUpdatedAt`：可选。
- `included`。
- `includedDefault`：首次发现时使用的 diary 或 external 默认值。
- `lastIndexedHash`：可选。
- `lastIndexedAt`：可选。
- `lastIngestError`：可选。
- `rawSourcePath`：materialize 后位于 `raw/sources` 下的 project-relative path。
- `wikiSummaryPath`：已知时位于 `wiki/sources` 下的 project-relative path。

目录选择可以用显式 directory records 表示，也可以从 child records 推导。实现需要保留足够状态来支持目录级 include/exclude 和子项 override，并且在 included 目录下出现新文件时不丢失用户意图。

## Source Identity

稳定 identity 比文件名更重要。

- Diary source identity：`diary:<dayKey>`。
- Imported knowledge document identity：现有 `ImportedKnowledgeDocument.id`。
- Manual source file identity：project-relative raw source path 或稳定 path hash。

Materialize 到 `raw/sources` 时，文件名必须避免冲突，同时保留足够路径上下文以追溯 source。比如嵌套文件 `Projects/AI/notes.md` 可以 deterministic 地 materialize 到 `raw/sources/Projects/AI/notes.md`，而不是压平成 `notes.md`。

## Pipeline 行为

`Update My Wiki` 从“sync diaries，然后 ingest 最近的 raw sources”变为：

1. 从 diary 文件、imported knowledge document rows、manual My Wiki sources 刷新 catalog。
2. 只对新发现 source 应用默认 inclusion。
3. 保留已有用户选择。
4. 将 included sources 以稳定层级路径 materialize 到 `raw/sources`。
5. 构建 ingest plan，只包含 `contentHash` 不同于 `lastIndexedHash` 的 included source，或 summary 缺失的 included source。
6. 只对计划内 source 运行 `llm_wiki`。
7. 成功后更新 `lastIndexedHash`、`lastIndexedAt`、`wikiSummaryPath`，并清除之前的错误。
8. 失败时记录 `lastIngestError`，不覆盖之前成功的 checkpoint。

Headless `llm_wiki` runner 应接受显式 source list 或 manifest。它不应该通过扫描 `raw/sources` 下所有 Markdown 文件来决定 eligible source set。

Manifest 应为每个 source 提供 folder context，帮助 `llm_wiki` 保留来源语境：

- `sourcePath`：project-relative raw source path。
- `sourceID`：稳定 source identity。
- `displayTitle`。
- `folderContext`：相对文件夹路径或 connector tree path。
- `sourceKind`。

## Exclusion 语义

Exclusion 表示“未来 My Wiki 处理不要使用这个 source”。它不表示“删除已经生成的知识”。

如果一个 source 在 indexed 后被 excluded：

- 保留 `wiki/sources/<summary>.md`。
- 保留可能由它生成的 entity 和 concept 页面。
- 行状态显示为 `Excluded, indexed`。
- 从未来 ingest plans 中排除。

如果用户后来再次 include 它：

- 如果当前 content hash 仍然匹配 `lastIndexedHash`，显示 `Indexed` 并跳过重新处理。
- 如果 content hash 不同，显示 `Changed` 并在下一次 update 中处理。

## 错误处理

Catalog refresh 应按 source root 降级。一个 broken connector 或 missing folder 不应该隐藏 diary 或其他 connectors。

UI 应在受影响的 root 附近展示 source-root errors。文件级 ingest errors 应保留在 source row 上，方便用户修复 source 或 prompt 后 retry。

如果 catalog state 无法 decode，KnowYou 应保留不可读文件作为 backup，然后按默认值重建，而不是删除用户 project data。

## 隐私与安全

External source 对 My Wiki 仍然是 opt-in。Source 出现在 catalog 中，不代表用户授权 LLM 处理。Include checkbox 是 permission boundary。

Materialization step 不能写回 external source 文件。它只写入 My Wiki project folder。

写入 `raw/sources`、读取 `wiki/sources`、把 source path 传给 MCP bridge 时，path handling 必须防止 traversal 到 project 外部。

## 测试策略

Focused tests 需要覆盖：

- 新 diary sources 默认 included。
- 已存在 diary 的 include/exclude 选择会被保留。
- 新 external sources 默认 excluded。
- Included 且 unchanged 的 source 在成功 indexed 后会被跳过。
- Changed 且 included 的 source 会进入 ingest plan。
- Excluded indexed source 保留之前的 summary path，但不会进入 ingest。
- Nested source paths 会保留在 catalog rows 和 materialized raw source paths 中。
- 目录 include/exclude 会作用于 descendants，并支持 child overrides。
- Descendants 选择不一致时，目录显示 mixed state。
- `llm_wiki` headless ingest 在提供 manifest 时接受显式 source set，不扫描所有 raw sources。
- 单个 source ingest 失败会记录错误，但不覆盖之前成功 checkpoint。

完成前的完整验证必须包括 targeted Swift tests、targeted `llm_wiki` tests，然后运行仓库要求的 Xcode test 和 build commands。

## 验收标准

- 打开 Source Library 时看到的是持久分层 catalog，而不只是 copied raw files。
- My Diary files 默认 included，且可以取消勾选。
- External source files 默认 unchecked，且可以被 include。
- Folder rows 支持 include、exclude 和 mixed descendant state。
- Update My Wiki 只处理 included 且 pending 或 changed 的 sources。
- 以前 indexed 且 unchanged 的 source 不会被重新处理。
- Exclude 一个 indexed source 不会删除旧 wiki 输出。
- Nested source folder context 会通过 materialization 和 ingest 保留下来。
