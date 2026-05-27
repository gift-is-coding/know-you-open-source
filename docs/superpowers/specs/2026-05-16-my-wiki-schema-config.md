# My Wiki Schema 配置化设计

## 背景

当前 My Wiki 的前端和读取层仍把 `People`、`Projects`、`Events`、`Topics`、`Preferences`、`Follow-ups` 等分类写死在 Swift 类型里。这个方向不适合产品化：不同用户的个人 wiki schema 会不同，未来也需要让用户修改 schema、切换推荐配置，甚至为工作、研究、生活日志使用不同分类。

本设计修正 My Wiki 的边界：

- `ThirdParty/llm_wiki` 继续作为后端生成引擎，负责 LLM ingest、页面生成、跨 source 合并、related/wikilink、source traceability、review/search/vector 等能力。
- KnowYou 不重写本体抽取 pipeline，只负责导出日记、写入 schema 配置、调用 LLM Wiki headless runner、读取生成后的 markdown/frontmatter，并用更轻量的 UI 展示。
- My Wiki 的分类不再写死在 Swift UI 中，而是从项目级机器可读配置读取。

## 核心决策

### 1. Schema 分成机器可读和 LLM 可读两层

每个 My Wiki 项目包含：

```text
mywiki.schema.json   # KnowYou / UI / runner 读取的机器可读配置
schema.md            # LLM Wiki ingest 读取的人类/LLM 可读说明
purpose.md           # 这个 wiki 的目标
raw/sources/         # KnowYou 导出的日记
wiki/                # LLM Wiki 生成的页面
```

`mywiki.schema.json` 是源头配置。`schema.md` 由该配置生成或同步，作为 LLM Wiki 的 prompt contract。Swift UI 不再靠 enum 判断有哪些分类。

### 2. Category 和 View 分离

`People`、`Projects`、`Events` 是 ontology category；`Recent`、`All`、`Needs Review` 是 view。
`Recent` 不应成为 LLM 输出目录，也不应写入 `wiki/recent/`，它只是 UI 根据 entries 的 mentions/source dates 派生出的排序视图。

### 3. 默认推荐配置只是 preset，不是硬编码产品真理

KnowYou v1 内置一个推荐 preset：`personal-context-default`。推荐分类为：

```text
People
Organizations
Projects
Events
Topics
Decisions
Preferences
Follow-ups
Summaries
Sources
```

这些只是默认值。未来用户可以新增、删除、改名、改目录、改 frontmatter type。UI 必须能根据 schema 动态渲染。

### 4. Swift fallback 不再生成正式本体页

`MyWikiStarterExtractor` 不能再作为正式页面生成路径。LLM Wiki headless ingest 失败时，KnowYou 只能显示失败/降级状态，不能用 keyword/regex/hardcoded candidates 生成看似可信的 People、Projects、Events 等页面。

允许的 fallback：

- 写 `.llm-wiki/last-ingest-status.json`
- 保留已成功生成过的旧 wiki 页面
- 显示空状态或状态页
- 提示用户重新运行 pipeline

不允许的 fallback：

- 根据 keyword 生成 confident ontology pages
- 在 pipeline 失败时把 degraded output 标记为 succeeded
- 把 Swift 规则产物混入 LLM Wiki 正式页面

## 配置格式

v1 使用项目根目录的 `mywiki.schema.json`。当前实现字段以 `displayName`、`singularName`、`extractionGuidance` 和 `detailSections` 为准；旧草案中的 `title`、`singularTitle`、`description`、`systemImage`、`sortOrder` 不再作为 Swift/runner 的必需字段。

```json
{
  "id": "personal-context-default",
  "displayName": "Personal Context",
  "categories": [
    {
      "id": "people",
      "displayName": "People",
      "singularName": "Person",
      "directory": "wiki/people",
      "frontmatterTypes": ["person"],
      "extractionGuidance": "Extract real individual people only: family, friends, collaborators, customers, investors, creators, or named public figures. Do not classify tools, agents, companies, or product names as people.",
      "detailSections": ["Summary", "Recent Mentions", "Sources", "Related", "Markdown Page"]
    },
    {
      "id": "organizations",
      "displayName": "Organizations",
      "singularName": "Organization",
      "directory": "wiki/organizations",
      "frontmatterTypes": ["organization", "company", "team"],
      "extractionGuidance": "Extract companies, teams, communities, institutions, and product organizations that recur in the source material.",
      "detailSections": ["Summary", "Recent Mentions", "Sources", "Related", "Markdown Page"]
    },
    {
      "id": "projects",
      "displayName": "Projects",
      "singularName": "Project",
      "directory": "wiki/projects",
      "frontmatterTypes": ["project"],
      "extractionGuidance": "Extract ongoing bodies of work with goals, milestones, owners, or repeated execution context.",
      "detailSections": ["Summary", "Recent Mentions", "Sources", "Related", "Markdown Page"]
    },
    {
      "id": "events",
      "displayName": "Events",
      "singularName": "Event",
      "directory": "wiki/events",
      "frontmatterTypes": ["event"],
      "extractionGuidance": "Extract bounded happenings such as meetings, calls, trips, launches, deadlines, incidents, or decisions made at a specific time.",
      "detailSections": ["Summary", "Recent Mentions", "Sources", "Related", "Markdown Page"]
    },
    {
      "id": "topics",
      "displayName": "Topics",
      "singularName": "Topic",
      "directory": "wiki/topics",
      "legacyDirectories": ["wiki/themes"],
      "frontmatterTypes": ["topic"],
      "legacyTypes": ["theme"],
      "extractionGuidance": "Extract recurring themes, interests, questions, fields, technical areas, product ideas, and conceptual concerns.",
      "detailSections": ["Summary", "Recent Mentions", "Sources", "Related", "Markdown Page"]
    },
    {
      "id": "decisions",
      "displayName": "Decisions",
      "singularName": "Decision",
      "directory": "wiki/decisions",
      "frontmatterTypes": ["decision"],
      "extractionGuidance": "Extract explicit choices, trade-offs, commitments, and policy decisions that should guide future behavior.",
      "detailSections": ["Summary", "Rationale", "Sources", "Related", "Markdown Page"]
    },
    {
      "id": "preferences",
      "displayName": "Preferences",
      "singularName": "Preference",
      "directory": "wiki/preferences",
      "frontmatterTypes": ["preference"],
      "extractionGuidance": "Extract stable user preferences, working style, product taste, communication preferences, and explicit long-term constraints.",
      "detailSections": ["Summary", "Evidence", "Sources", "Related", "Markdown Page"]
    },
    {
      "id": "follow-ups",
      "displayName": "Follow-ups",
      "singularName": "Follow-up",
      "directory": "wiki/follow-ups",
      "legacyDirectories": ["wiki/open-loops"],
      "frontmatterTypes": ["follow-up"],
      "legacyTypes": ["open-loop"],
      "extractionGuidance": "Extract unresolved open loops, promised next steps, pending asks, waiting-for items, and things the user wants to revisit.",
      "detailSections": ["Summary", "Status", "Sources", "Related", "Markdown Page"]
    },
    {
      "id": "summaries",
      "displayName": "Summaries",
      "singularName": "Summary",
      "directory": "wiki/summaries",
      "frontmatterTypes": ["summary", "overview"],
      "extractionGuidance": "Create readable synthesis pages across days, weeks, projects, or themes. Summaries should cite sources and avoid inventing facts.",
      "detailSections": ["Summary", "Sources", "Markdown Page"]
    },
    {
      "id": "sources",
      "displayName": "Sources",
      "singularName": "Source",
      "directory": "wiki/sources",
      "frontmatterTypes": ["source", "knowyou-diary"],
      "extractionGuidance": "Represent source materials and source indexes. Do not duplicate raw secrets or credentials.",
      "detailSections": ["Summary", "Markdown Page"]
    }
  ],
  "views": [
    {
      "id": "recent",
      "displayName": "Recent",
      "kind": "recentActivity",
      "categoryIDs": ["people", "organizations", "projects", "events", "topics", "decisions", "preferences", "follow-ups"]
    },
    {
      "id": "needs-review",
      "displayName": "Needs Review",
      "kind": "needsReview",
      "categoryIDs": ["people", "organizations", "projects", "events", "topics", "decisions", "preferences", "follow-ups"]
    }
  ]
}
```

## 数据流

```text
KnowYou daily markdown
-> MyWikiProjectExporter syncs raw/sources
-> MyWikiSchemaStore writes/loads mywiki.schema.json
-> MyWikiSchemaMarkdownRenderer generates schema.md contract
-> ThirdParty/llm_wiki headless runner reads schema config/contract
-> LLM Wiki ingest prompt parses the dynamic contract and derives directories/types
-> LLM Wiki autoIngest generates wiki markdown pages
-> MyWikiMarkdownStore loads categories dynamically from config
-> MyWikiPanel renders schema-driven sections/views
```

## 需要改变的实现边界

- `MyWikiCategory` 固定 enum 需要被 `categoryID: String` 和 `MyWikiCategoryDefinition` 替代。
- `MyWikiDashboardSnapshot` 需要从固定字段数组改为动态 sections。
- `MyWikiMarkdownStore` 需要按 schema 配置扫描目录，而不是写死 `wiki/people`、`wiki/projects` 等目录。
- `MyWikiProjectExporter` 需要创建 `mywiki.schema.json`，并基于配置创建目录和生成 `schema.md`。
- `ThirdParty/llm_wiki/src/headless/knowyou-ingest.ts` 需要从 `mywiki.schema.json` 动态生成 My Wiki output contract。
- `ThirdParty/llm_wiki/src/lib/ingest.ts` 的 My Wiki prompt 分支不能继续硬编码 People/Projects/Events，而要解析 schema contract 生成 target list、allowed directory list 和 allowed type list。
- `MyWikiPipelineBridge` 不能在真实 pipeline 前运行 `MyWikiStarterExtractor` 生成正式页面。

## 成功标准

- 修改 `mywiki.schema.json` 后，Swift UI 的分类列表会变化，不需要改 Swift enum。
- 新增 `Organizations` 或 `Decisions` 这类分类后，project exporter 会创建对应目录，LLM Wiki prompt 会要求生成对应类型，UI 会读取并展示。
- `Recent` 作为 view 显示，但不会被写入 LLM Wiki 输出目录。
- pipeline 失败时不会生成 keyword fallback 本体页，只显示失败/降级状态。
- `Codex`、`Claude`、`OpenAI` 等工具不会因为 Swift 规则被写成 People；本体判断只来自 LLM Wiki ingest 和 schema contract。
- 旧的 `wiki/themes` 和 `wiki/open-loops` 仍可通过 legacy config 读取；新的默认目录分别是 `wiki/topics` 和 `wiki/follow-ups`。

## 非目标

- 本阶段不做完整 schema editor UI。
- 本阶段不重写 LLM Wiki 的 ingest、merge、search、vector store。
- 本阶段不把 LLM Wiki 的完整 Tauri UI 嵌入 KnowYou 主界面。
- 本阶段不自动 push，仍保持用户先本地测试。
