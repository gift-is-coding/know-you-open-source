# My Wiki v1 索引详情设计

## 背景

`My Wiki` 是 KnowYou 左侧栏里的知识入口，不是产品名。当前页面偏 dashboard 卡片墙，信息密度低，且把工程状态、项目文件夹等概念暴露给普通用户。v1 要把它改成面向用户的个人知识索引：用户能快速看到被日记抽取出的核心人物、项目、主题、模式和待跟进事项，并能进入详情阅读来源、关系和总结。

## 目标

- 左侧提供高密度索引：搜索、可展开分组、每组少量近期条目、`View all` 全量入口。
- 右侧提供可读详情：总结、最近提及、来源、相关条目、完整 Markdown 页面。
- `Preferences` 对用户显示为 `Patterns`，内部仍兼容旧 category。
- 编辑入口统一处理名称、别名和总结。
- 改名冲突时不覆盖，必须引导用户选择保留、换名或合并。
- 主动发现重复实体，但必须由用户确认后才合并。

## 信息架构

左侧索引只保留一套导航，不再同时显示分类 tabs 和分类分组。默认分组包括：

- Recently active
- People
- Projects
- Topics
- Patterns
- Follow-ups

每个分组支持展开和折叠。首页每组只显示前 3 到 5 个条目；`View all` 会在右侧打开该分类的全量列表。全量列表支持搜索、选择条目和基本排序，避免几十个 People 或 Topics 把首页撑成长列表。

## 详情页

详情页参考 LLM Wiki 的可读页面，但减少图谱复杂度。详情包含：

- 标题、类型、提及数、来源数、置信度。
- `Also known as` 别名 chips。
- `Summary` 总结。
- `Recent Mentions` 最近提及，带来源日期。
- `Sources` 来源文件。
- `Related` 相关条目。
- `Markdown Page` 完整页面正文。

内部 `tags` 不直接暴露给普通用户；可读关系进入 `Related`。

## 编辑与合并

`Edit` 同时编辑 display name、aliases 和 summary。保存时先检查 slug/name 冲突：

- 无冲突：保存新 display name，旧名进入 aliases。
- 有冲突：展示冲突选择，不直接覆盖。
  - Keep current name
  - Choose another name
  - Merge with existing item

合并时保留 sources、aliases、related、mentions、summary，并重写引用。合并前写备份。

## 主动发现重复项

复用 LLM Wiki 的 dedup 思路：扫描 wiki 页面摘要，找出可能指向同一对象的条目，生成 duplicate suggestions。v1 先实现本地规则版，支持名称规范化、别名重叠、slug 相似等可解释候选；后续可接 LLM 判断。

重复项不会自动合并。只有用户点击 review 并确认后，才执行 merge。

## 不做

- v1 不做复杂图谱视图。
- v1 不把 journal count、last date、Open Project 放在主路径。
- v1 不自动 push。

## 2026-05-15 修正：入口性能与开发状态保持

- 打开 My Wiki 只读取已有 Markdown 快照，不自动执行导出、LLM Wiki ingest 或 Codex CLI pipeline。
- 日记整理改为显式操作：`More > Organize Journals`，并在后台任务执行，避免卡住主线程。
- `More` 菜单继续保留 `Find duplicates`、`Reveal Wiki Folder`、`Wiki Status`。
- 测试不得清除真实 `dev.knowyou.app` 的 `UserDefaults.standard` onboarding 状态；需要先快照，结束后原样恢复。
- DerivedData Debug 构建可以记住开发阶段的 Full Disk Access bypass，方便反复重建和本地验证；正式安装版不启用该 bypass。

## 2026-05-15 修正：点击详情卡顿

- 左侧列表判断选中状态时只能比较 `id + category`，不能比较整个 `MyWikiEntry`，因为 entry 内含完整 Markdown 正文。
- 右侧详情页默认只渲染 Markdown preview，不直接把超长正文作为可选中文本完整排版。
- 完整 Markdown 仍保留在文件系统中，用户可通过 `More > Reveal Wiki Folder` 打开。
- `Codex`、`Claude`、`Cowork` 这类 AI 工具或 agent 不能作为 `People` 出现在用户视图里；旧 starter extractor 产生的同名 People/Project 页面需要被过滤或后续迁移清理。
