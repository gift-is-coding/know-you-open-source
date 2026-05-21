# 文件连接器同步设计

## 摘要

KnowYou 将新增一类 `Knowledge Imports` 能力，用来把外部文档同步到 KnowYou 自己管理的本地缓存中。第一版目标是做一个本地优先的连接器平台：本地连接器覆盖 Obsidian 和普通文件夹，API 连接器覆盖飞书、Notion 和 Google Drive。

这套能力必须和现有 `Sync Memory` 区分开。`Sync Memory` 继续作为单向导出路径，把 KnowYou 每天生成的日记 Markdown 复制到 Obsidian 和 OpenClaw。`Knowledge Imports` 则是反方向：从外部工具拉取资料，导入 KnowYou 的本地知识库，为后续阅读、搜索和 agent context 做准备。

## 目标

- 新增一个外部知识源连接器分类。
- 把外部文件导入本地存储，而不是依赖实时动态链接。
- 将导入文档规范化为 Markdown 或类似 Markdown 的文本，并保存 metadata。
- 支持手动同步和每日定时同步。
- 记录远端身份、本地内容 hash、同步 cursor 和删除状态。
- 避免和现有 Obsidian 每日日记导出形成同步循环。
- 第一版保持可扩展，但不引入完整双向同步。

## 非目标

- 第一版不做双向编辑和冲突处理。
- 不把 KnowYou 中编辑过的知识内容写回飞书、Notion、Google Drive、Obsidian 或本地文件夹。
- 不替换现有每日日记 `.story.json` 和 `.md` 生成管线。
- 默认不把 KnowYou 自己导出的 daily memory 目录重新导入知识库。
- 已导入内容的阅读不依赖云端实时可用。

## 产品模型

当前 `Sync Memory` 表面需要在概念上拆成两个分类：

- `Daily Memory Export`
  - 保留现有行为。
  - 把 KnowYou 生成的 `YYYY-MM-DD.md` 日记文件复制到外部 memory 目标。
  - 第一优先级目标仍然是 Obsidian 和 OpenClaw。
  - 方向是 KnowYou 到外部工具。

- `Knowledge Imports`
  - 新增行为。
  - 从外部工具拉取文档到 KnowYou 本地缓存。
  - 第一优先级连接器是 Obsidian、本地文件夹、飞书、Notion 和 Google Drive。
  - 方向是外部工具到 KnowYou。

UI 可以把两者放在一个更大的 `Connectors` 或 `Sources` 面板下，但数据模型和同步引擎必须把导出渠道和导入渠道分开。

## 第一版连接器集合

### Obsidian

Obsidian 导入会扫描一个或多个 vault 根目录下的 Markdown 文件。导入时需要在 metadata 中保留相对路径，原文按 Markdown 保存，并记录文件修改时间和内容 hash。

默认情况下，Obsidian 导入必须跳过现有 KnowYou 导出目录：

`<vault>/KnowYou/Daily Memories/`

如果文件带有 KnowYou daily memory export 的 frontmatter 或 sidecar origin marker，也必须跳过。

### 本地文件夹

本地文件夹导入扫描用户选择的目录。第一版支持 Markdown 和纯文本。PDF、docx 和富文档解析可以作为后续扩展，除非后续实现计划明确把它们纳入第一阶段。

本地文件夹连接器可以覆盖 iCloud Drive、Dropbox、OneDrive、项目文档目录、导出的笔记归档等场景，不需要为每个云盘先做 provider-specific API。

### 飞书

飞书导入需要走 API-backed connector 边界，包含凭据存储、远端文档身份和增量同步状态。第一版应尽量把飞书文档规范化为 Markdown-like 文本；如果无法完整转换，则回退为纯文本，同时保留源 URL 和远端 metadata。

设计不能假设用户只有一个飞书 workspace。连接器配置需要能表示账号和 workspace 身份。

### Notion

Notion 导入应支持用户配置 token 或 OAuth 授权，支持选择 pages/databases，并能递归导出页面内容为 Markdown-like 文本。

Notion block ID 和 page ID 应作为远端稳定 ID 保存。`last_edited_time` 可以作为廉价变更检测，内容 hash 作为最终去重边界。

### Google Drive

Google Drive 导入应支持用户选择文件夹或文件。Google Docs 应导出为 Markdown-like 文本或纯文本 fallback。原生 `.md` 和 `.txt` 文件保留原始内容。metadata 需要包含 Drive file ID、web URL、mime type、modified time，以及可获得的 parent path。

## 本地存储

导入内容由 KnowYou 管理，存放在 Application Support 下：

`Application Support/KnowYou/KnowledgeSources/<connector>/<source-id>/...`

每个导入文档应有稳定的本地记录：

- `content.md`
- `metadata.json`

本地文件布局主要用于可移植性和人工检查。SQLite 仍然是列表、去重、同步状态和未来检索能力的主索引。

建议 metadata 字段：

- `connectorID`
- `accountID` 或 `workspaceID`
- `sourceID`
- `remoteID`
- `remoteURL`
- `sourcePath`
- `title`
- `mimeType`
- `contentHash`
- `remoteUpdatedAt`
- `firstImportedAt`
- `lastSyncedAt`
- `deletedAt`
- `normalizationVersion`
- `originKind`

## SQLite 索引

新增知识导入索引，和每日日记表分开。索引需要支持：

- 连接器实例和配置摘要。
- 导入文档记录。
- 远端 sync cursor 或 page token。
- 每个连接器的最后同步状态。
- 远端删除的 tombstone。

文档身份优先基于 connector instance 加远端稳定 ID。对于本地文件，身份应使用 bookmark/path-derived stable source ID 加相对路径。内容 hash 用于重复内容去重，但不能替代 source identity，因为同一份内容可能合理地存在于多个外部位置。

## 同步引擎

每个导入连接器遵循同一个概念接口：

- `listChanges(since:)`
- `fetchDocument(id:)`
- `normalizeToMarkdown(document:)`
- `saveLocalSnapshot(document:)`

第一版需要支持：

- 手动立即同步。
- 每日定时同步。
- 每个连接器单独开启/关闭。
- 每个连接器记录最后成功同步时间。
- 每个文档基于 content hash 去重。
- 每个文档基于远端更新时间比较变更。
- 对远端删除记录 tombstone。

同步必须是幂等的。没有外部变化时重复运行同步，不应重写本地文件，也不应把用户可见状态更新成“有新内容导入”。

## 循环防护

现有 Obsidian 导出路径存在循环风险：KnowYou 把每日日记 Markdown 写入 Obsidian 后，Obsidian 导入可能又把这些文件拉回 KnowYou 知识库。

循环防护是硬性要求：

- Obsidian 导入默认跳过 `<vault>/KnowYou/Daily Memories/`。
- `Daily Memory Export` 写出 frontmatter marker，例如 `knowyou_export: daily_memory`，或写出 sidecar `.knowyou-origin.json`。
- `Knowledge Imports` 跳过带有 KnowYou export marker 的文件。
- 如果用户显式选择导入 export 目录，本地文件夹连接器应提示这是 KnowYou 生成的镜像，并默认保持禁用。
- 第一版中，导入文档永远不写回外部来源。

## 调度

`Daily Memory Export` 和 `Knowledge Imports` 可以复用底层 LaunchAgent 基础设施，但它们应暴露独立的 schedule 和状态：

- `Daily Memory Export` 保留当前 `Auto Sync Daily` 行为。
- `Knowledge Imports` 拥有自己的每日导入同步设置。
- 手动动作分开：`Export Daily Memories Now` 和 `Import Knowledge Now`。

这样可以避免用户开启日记导出时意外启用 API 导入，或反过来开启导入时意外导出日记。

## 错误处理

连接器错误需要限定在具体 connector instance 上：

- auth 过期。
- permission denied。
- rate limited。
- remote unavailable。
- 本地文件夹不存在。
- 文件类型不支持。
- normalization 失败。

单个连接器失败不能阻塞其他连接器同步。UI 应显示每个连接器的最后成功时间、最后失败信息和本次变更文档数量。

## 隐私与安全

第一版会把用户选择的外部知识源导入本地存储。这个事实需要在 onboarding 或连接器设置文案里明确说明。凭据和 refresh token 必须使用 Keychain 或等价的安全本地存储，不能放在 UserDefaults。

导入内容应保持本地。现有 summarizer 或未来 agent 功能只能通过明确的产品路径读取它。导入系统本身不应把内容发送给 LLM provider。

现有 clipboard/notification 事件的隐私过滤器不会自动套用到用户主动选择的知识导入内容上。UI 和文档需要说明这个边界：导入文档视为用户批准的 source material。

## UI 形态

第一版可以扩展当前 `Sync Memory` panel，也可以替换为更宽的 `Connectors` panel。推荐产品形态：

- 二级菜单里新增或改名为 `Connectors`。
- 面板分两个 section：
  - `Daily Memory Export`
  - `Knowledge Imports`
- 每个 connector row 显示：
  - 名称
  - 方向
  - 状态
  - 最后同步时间
  - 本地文档数量
  - Configure / Sync Now / Disable 操作

UI 应避免把 Obsidian 表达成一个方向模糊的连接器。应显示为 `Obsidian Export` 和 `Obsidian Import` 两个独立 row，或放在两个清晰分隔的 section 中。

## 测试策略

重点测试：

- Obsidian 导入跳过 `KnowYou/Daily Memories`。
- import connectors 忽略 KnowYou export marker。
- 本地文件夹导入能规范化 Markdown 和纯文本文件。
- content hash 去重避免不必要的重写。
- remote ID identity 允许变更内容更新同一条本地记录。
- 远端删除会记录 tombstone。
- 单个连接器失败不会导致整个同步 run 失败。
- 现有 Sync Memory export 测试继续通过。
- config persistence 能把 export 和 import 设置分开保存。

API 连接器测试使用 protocol-backed fake，不做真实网络调用。

## 文档更新

实现时需要更新：

- `docs/architecture.md`
- `docs/requirements-spec.md`

文档里当前“KnowYou 不做外部知识库同步”的产品边界需要改写。新边界应说明：KnowYou 支持外部知识源到本地缓存的单向导入，但仍不支持双向外部知识库编辑。

## 实现备注

- 飞书、Notion 和 Google Drive 的 auth flow 可能需要拆成独立实现阶段，即使第一版已经先设计统一 connector abstraction。
- 全文搜索和 agent-context retrieval 是下游消费方，不属于第一版 connector sync engine 的必要范围。
- PDF 和富文档解析应在 Markdown/text 管线稳定后再加入。
