# 知识本体 llm_wiki 复用设计

## 背景

KnowYou 当前核心是“原始资料 -> 每日日记”。用户希望在此基础上增加“知识本体”入口，让 KnowYou 不只是日记阅读器，也成为个人 context 的数据中枢。

参考项目 `nashsu/llm_wiki` 已经实现了完整的 wiki / sources / search / graph / lint / review / deep research / settings 等知识本体工作台。它的功能依赖 React 前端、Tauri command 与 Rust 后端。如果直接用 SwiftUI 重写，成本高且容易丢失原有能力；如果只做一个轻量图谱，也不符合“全盘复用原先功能”的目标。

因此本版本采用“KnowYou 宿主 + llm_wiki 子系统 + 最薄适配层”的方案。

## 目标

1. 在 KnowYou 原有左侧栏增加 `知识本体` 按钮。
2. 点击后进入 KnowYou 内的知识本体宿主页，而不是继续使用顶部 sheet 入口。
3. 保留 llm_wiki 的原有功能面：sources、wiki、search、graph、lint、review、deep research、settings 等。
4. KnowYou 负责把现有日记 Markdown 导出为 llm_wiki 项目的 `raw/sources` 输入资料。
5. 第一版优先通过受 KnowYou 管理的 llm_wiki helper / dev source 启动原功能，不重写 llm_wiki 前端和 Tauri command。
6. 文档、设计说明和后续计划全部使用中文。

## 非目标

- 不在本版本用 SwiftUI 重写 llm_wiki 的图谱、搜索、review、deep research。
- 不在本版本实现完整 WKWebView Tauri command 兼容层。
- 不改变 KnowYou 当前的日记生成流程。
- 不删除或重写 Sync Memory。

## 用户体验

主窗口左侧栏出现 `知识本体` 入口。用户点击后，中间区域切换为知识本体宿主页：

- 显示知识本体项目路径。
- 显示最近一次日记导出状态。
- 提供“同步日记到知识本体”动作。
- 提供“打开知识本体”动作，用于启动复用的 llm_wiki 工作台。
- 页面使用黑色背景，与 KnowYou 当前风格保持一致。

第一版允许知识本体以 helper 窗口形式呈现，因为这是完整复用 llm_wiki Tauri 能力的最低风险方式。后续若要完全嵌入主窗口，可在 helper 稳定后再实现 WKWebView + command bridge。

## 数据结构

KnowYou 为 llm_wiki 创建固定项目目录：

```text
<Application Support>/KnowledgeOntology/KnowYouContext/
  schema.md
  purpose.md
  wiki/
    index.md
    log.md
    overview.md
    entities/
    concepts/
    sources/
    queries/
    comparisons/
    synthesis/
  raw/
    sources/
      knowyou-diary-YYYY-MM-DD.md
    assets/
  .obsidian/
```

导出的日记文件位于 `raw/sources/`，文件名为：

```text
knowyou-diary-YYYY-MM-DD.md
```

每个导出文件包含最小 frontmatter：

```yaml
---
type: knowyou-diary
source: KnowYou
day: YYYY-MM-DD
---
```

后面接原始 KnowYou 日记 Markdown。这样 llm_wiki 的 sources/import/review/graph 工作流可以把日记当作普通资料处理。

## llm_wiki 复用方式

仓库中保留 `ThirdParty/llm_wiki` 源码副本，并记录来源、许可与本地改动：

- 来源：`https://github.com/nashsu/llm_wiki`
- 复用范围：React 前端、Tauri 后端、schema/project 结构、graph/search/review 等功能
- 本地改动：KnowYou 黑色主题、默认项目目录适配、产品文案适配

KnowYou 启动知识本体时按顺序寻找：

1. 已打包进 app bundle 的 `KnowledgeOntology/LLM Wiki.app`
2. 开发环境中的 `ThirdParty/llm_wiki` 源码目录

如果二者都不存在，宿主页应明确显示缺失状态，不静默失败。

## 隐私边界

知识本体只消费 KnowYou 已经生成的每日 Markdown。由于每日 Markdown 已经过 KnowYou 现有隐私过滤和生成流程，第一版不直接把 SQLite 原始事件导出给 llm_wiki。

后续若要让 llm_wiki 读取原始事件，必须新增独立隐私评审和用户可见授权。

## 验收标准

1. 主窗口左侧栏有 `知识本体` 按钮。
2. 点击后主内容区切换到知识本体宿主页。
3. 宿主页能创建 llm_wiki 兼容项目结构。
4. 宿主页能把现有 `YYYY-MM-DD.md` 日记导出到 `raw/sources/knowyou-diary-YYYY-MM-DD.md`。
5. 导出重复执行是幂等覆盖，不重复创建乱名文件。
6. 启动逻辑能选择 bundled helper 或开发源码目录。
7. llm_wiki 源码被纳入 `ThirdParty/llm_wiki`，并有中文说明文档记录如何构建和复用。
8. 新增测试覆盖项目创建、日记导出和 launcher 选择策略。
9. `docs/architecture.md` 与 `docs/requirements-spec.md` 同步说明“知识本体”能力边界。
