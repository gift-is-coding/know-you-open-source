# My Wiki 入口重新设计方案

## 命名边界

KnowYou 仍然是产品名。`My Wiki` 只是 KnowYou 左侧栏里的一个入口，也是该功能区的页面标题。

用户不应该看到结构化抽取、关系网络、schema 编辑、图数据库这类工程术语。内部可以继续使用结构化 schema 和 markdown/wiki 文件，但 UI 必须使用普通用户能理解的语言。

## 背景判断

当前方案过重，主要问题是：

- 入口名称偏技术，用户不知道它和自己的日记有什么关系。
- 页面把 llm_wiki 的复杂关系图、审核、检查、深度研究等能力直接暴露出来，像开发工具而不是个人产品。
- 用户真正想要的是被整理后的理解结果：核心内容、更准搜索、总结文字，而不是复杂图谱。

参考 Karpathy 的 LLM Wiki 思路，KnowYou 应该保留“原始资料之上的可读 markdown/wiki 中间层”，但不要继承原项目的复杂用户界面。

## 用户价值

`My Wiki` 只解决三件事：

1. 看到自己最近反复出现的人、项目、主题、偏好和待办。
2. 用自然语言搜索自己的日记和理解层，得到更准确的答案。
3. 让 Codex、Claude、Cowork 等 agent 在执行任务前读取必要背景。

## 用户界面

左侧栏入口：

- 名称：`My Wiki`
- 图标：继续使用关系/节点类图标可以接受，但不要让页面成为大图谱入口。

`My Wiki` 首页包含：

1. 顶部搜索框
   - 占位文案：`问问你的 My Wiki...`
   - 用户可以问：`我最近为什么觉得方案太重？`、`KnowYou 现在最大的产品判断是什么？`、`我和某个人最近聊了什么？`

2. 总结区
   - `最近 7 天`
   - `最近 30 天`
   - `最近变化`
   - `需要继续关注`

3. 核心脉络区
   - `人物`
   - `项目`
   - `主题`
   - `偏好`
   - `待办`
   - `反复出现的问题`

4. 证据区
   - 搜索结果和详情页必须能回到具体日记日期或 source。
   - 用户看到的是“来自哪几天日记”，不是 raw path。

## 不再作为主入口的能力

以下能力可以保留在底层或开发/高级入口中，但第一版不要作为普通用户主界面：

- 大图谱视图
- 审核/检查工作流
- 深度研究工作流
- schema 编辑器
- llm_wiki 原始 workspace

## 内部结构

内部仍然继承 llm_wiki 的核心 pipeline 思路：

- `raw/sources/` 保存从 KnowYou 导出的日记资料。
- `purpose.md` 描述这个 My Wiki 的目标。
- `schema.md` 告诉 agent 如何维护结构化页面。
- `wiki/index.md` 维护用户可读索引。
- `wiki/log.md` 记录每次整理发生了什么。
- markdown 页面使用 frontmatter、wikilink、source references。
- ingest pipeline 保留增量处理、cache、source traceability、page merge。

新的目录建议：

```text
raw/
  sources/
wiki/
  people/
  projects/
  themes/
  preferences/
  open-loops/
  summaries/
  sources/
  index.md
  overview.md
  log.md
schema.md
purpose.md
.llm-wiki/
```

内部类型映射：

| 内部类型 | UI 名称 | 说明 |
| --- | --- | --- |
| `person` | 人物 | 家人、朋友、同事、合作方 |
| `project` | 项目 | KnowYou、客户项目、个人计划 |
| `theme` | 主题 | 健康、写作、AI agent、产品方向 |
| `preference` | 偏好 | 用户反复表达的选择倾向 |
| `open_loop` | 待办 | 承诺、未完成事项、需要回访的问题 |
| `recurring_problem` | 反复出现的问题 | 多篇日记中重复出现的困扰或风险 |
| `summary` | 总结 | 周期性或主题性综合文字 |

## 后端 pipeline 继承策略

第一版不从零写 pipeline。优先继承 `ThirdParty/llm_wiki` 中已经存在的能力：

- `src/lib/ingest.ts`：资料进入 wiki 的主流程。
- `src/lib/ingest-cache.ts`：跳过未变化资料。
- `src/lib/page-merge.ts` 和 `src/lib/sources-merge.ts`：合并已有页面，保留来源。
- `src/lib/search.ts` 与 `src/lib/embedding.ts`：搜索、RRF、向量检索。
- `src/lib/frontmatter.ts`：解析和修复 markdown frontmatter。
- `src/lib/wiki-graph.ts`：只作为关系计算来源，不直接展示大图谱。
- `src-tauri/src/commands/vectorstore.rs`：保留 LanceDB chunk-level vector store。

KnowYou 侧只做适配层：

1. 把日记导出成 `raw/sources/knowyou-diary-YYYY-MM-DD.md`。
2. 写入 KnowYou 专属 `purpose.md` 和 `schema.md`。
3. 调用继承来的 ingest/search 能力。
4. 读取生成后的 markdown/wiki 页面，转成 SwiftUI 可展示模型。
5. 给 agent 提供“最小必要上下文”接口。

## 前端策略

前端不继承 llm_wiki 的复杂 workspace。KnowYou 自己实现轻量 SwiftUI 页面：

- `MyWikiPanel`：首页，包含搜索、总结、核心脉络。
- `MyWikiSummaryCard`：展示最近总结。
- `MyWikiCategorySection`：展示人物/项目/主题/偏好/待办。
- `MyWikiDetailView`：点开某个条目后的详情。
- `MyWikiSearchView`：自然语言搜索结果。

页面详情结构：

```text
标题
一句话说明
最近状态
关键事实
相关人物 / 项目 / 主题
相关日记
给 agent 的上下文
```

## Agent 接口

第一版提供本地服务层接口，不急着暴露网络 API：

- `briefForCurrentWork()`：返回当前用户/项目/偏好的短上下文。
- `searchMyWiki(query:)`：返回总结答案、相关条目、证据日记。
- `pageContext(slug:)`：返回某个人物/项目/主题的详情。

这些接口后续可以包装成 MCP tool 或本地 HTTP API。

## 实施落点

当前分支的第一版实现分为五层：

- `MyWikiProjectExporter`：创建 My Wiki 目录、写入 `purpose.md` 与 `schema.md`，同步已生成的日记 Markdown。
- `MyWikiMarkdownStore`：读取生成后的 wiki 页面，转成首页展示模型。
- `MyWikiPanel`：提供黑底轻量首页，固定展示搜索、总结、人物、项目、主题、偏好、待办。
- `MyWikiPipelineBridge`：承接 llm_wiki 的项目发现与 pipeline 入口，后续继续复用 ingest/search/page merge/vector store。
- `MyWikiStarterExtractor`：在完整 LLM ingest 接管前，从已同步日记生成可读起始页，保证已有日记可以立即进入总结、项目、主题、偏好和待办。
- `MyWikiAgentContextProvider`：为 Codex、Claude、Cowork 等 agent 输出简短、可追溯来源的背景摘要。

旧内部文件名只作为兼容包装保留，不再作为用户文案或设计概念出现。

## 隐私边界

- 第一版只导出已经生成的日记 Markdown。
- 不直接导出未经额外授权的 SQLite 原始通知、剪贴板事件。
- 搜索结果和 agent brief 必须引用来源日期。
- 敏感信息只保留必要摘要，不复制 token、密码、完整账号、证件号。

## 成功标准

- 左侧栏入口显示为 `My Wiki`。
- 用户进入后看到的是总结、核心脉络和搜索，而不是复杂开发工具。
- 后端仍能使用 llm_wiki 的 ingest/cache/search/page merge/vector store。
- `schema.md` 继续存在，但内容面向 My Wiki 的人物、项目、主题、偏好、待办、总结。
- 当前已有日记能被同步并整理成 My Wiki 页面。
- Codex/Claude 类 agent 可以读取 My Wiki 的简短上下文。
