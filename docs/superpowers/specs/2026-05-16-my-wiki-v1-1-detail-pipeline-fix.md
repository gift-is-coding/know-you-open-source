# My Wiki v1.1 详情与 Pipeline 修正规格

## 背景

当前 My Wiki 的三栏 UI 方向已经成立，但用户在真实使用时看到几个明显问题：

- 列表条目的可点击区域过小，只有标题附近容易触发。
- `Adam` 等页面显示 `appears as a real person` 这类占位总结，说明展示层读到了旧 starter extractor 的页面，而不是正式 LLM Wiki pipeline 的语义页面。
- 详情页重复展示 `Summary` 和 `Markdown Page`，用户无法判断后者的意义。
- `Sources` 与 `Related` 只是文字，无法跳转到来源或相关页面。
- app 当前读取的 My Wiki 项目目录是 `~/Library/Application Support/KnowYou/KnowledgeOntology/KnowYouContext`，这里的 ingest 状态停留在 `running, Ingested 4/36`，并残留 `generated_by: KnowYou My Wiki starter extractor` 页面；而手工跑成功的完整 pipeline 在 Obsidian 目录，两者不一致。

## 目标

v1.1 的目标是让 My Wiki 当前 app 页面只展示可信的正式语义结果，并补齐 LLM Wiki 风格的基础详情交互：

1. 整个条目行都可点击。
2. 不再把 starter extractor 占位页面当成正式本体结果展示。
3. Summary 优先读取正式结构化内容：frontmatter `description`、`## Summary` section、正文首个有效段落。
4. 详情页不默认展示完整 `Markdown Page` 原文，避免与 Summary 重复。
5. `Sources` 能打开对应 source summary 或 raw source。
6. `Related` 能跳转到当前 My Wiki 内部对应页面。
7. 当前 app 使用的 Application Support 项目目录要能跑完正式 LLM Wiki pipeline，避免用户看到旧状态。
8. 不要求一次跑完整个 source 集合；用户可以先看 preview 结果。
9. 如果 pipeline 正在处理大量文档，左侧索引区域显示一个轻量进度，不占用详情阅读空间。
10. 明确区分 entity 详情里的 `Sources` 与全局 ingest 进度：`Sources (5)` 表示这个 entity 被 5 个来源支撑，不代表 pipeline 只处理了 5 个文件。

## 非目标

- 不在 v1.1 做复杂图谱视图。
- 不重写 LLM Wiki 后端 pipeline。
- 不把 source 内容复制进 git。
- 不自动 push。
- 不清理登录态或 onboarding 状态。

## 设计

### 读取层

`MyWikiMarkdownStore` 负责把 markdown 页面解析成 `MyWikiEntry`。v1.1 做三点调整：

- 如果 frontmatter `generated_by` 包含 `starter extractor`，默认不加载为正式 My Wiki entry。
- `summary` 解析顺序改为：
  1. frontmatter `description`
  2. body 中 `## Summary` section
  3. 去掉 H1/H2 标题后的第一个有效正文段落
- 保留 `markdownBody` 作为内部编辑/调试数据，但详情 UI 不默认展示完整正文。

### 导航层

新增轻量 resolver，放在现有 My Wiki 读取/维护边界中：

- `resolveSourceURL(sourceName, projectRoot)`：
  - 裸 `.md` 文件优先找 `wiki/sources/<name>`
  - 再找 `raw/sources/<name>`
  - 带路径的引用按 project root 相对路径解析
- `resolveRelatedEntry(slug, snapshot)`：
  - 优先按 entry id 匹配
  - 再按 title slug 匹配
  - 找到后设置 `selectedEntry`

### UI 层

- `MyWikiIndexRow` 的 Button label 加 `frame(maxWidth: .infinity, alignment: .leading)` 和 `contentShape(Rectangle())`。
- `MyWikiDetailView` 删除默认 `Markdown Page` card。
- `Sources` 改成按钮；点击后由 `MyWikiPanel` 打开对应文件。
- `Related` 改成按钮；点击后由 `MyWikiPanel` 选中对应 entry。
- 左侧搜索框下方增加一条紧凑 ingest 状态：
  - `Processing sources`：pipeline 运行中。
  - `Preview generated`：用户中止全量处理，但已有部分结果可预览。
  - `Updated`：本次 ingest 完成。
  - `Needs attention`：pipeline 失败，需要用户查看状态。
- 进度文案使用 `23/36 sources` 这类整体 source 处理数，不和单个 entity 的 `Sources` 混用。

### Source 管理入口

v1.1 不做复杂工作台，但已经提供一个轻量 `Source Library` 入口，放在 My Wiki 的 `More` 菜单和左侧进度卡片里，而不是藏在单个 entity 详情里。

推荐设计：

1. `Choose Folder`：用户指定一个日记或素材文件夹。系统记录 source root，扫描支持的文件，并将它们加入待处理队列。
2. `Drag files here`：用户可以手动拖拽 markdown、txt 或未来支持的文件类型进入 My Wiki。v1 可以先复制到 `raw/sources`，后续再支持“引用原路径但不复制”。
3. 每个 source 有明确状态：`Pending`、`Processing`、`Indexed`、`Failed`、`Needs review`。
4. 全局进度来自 source 队列状态；entity 详情里的 `Sources` 来自抽取结果的证据引用。
5. Source 删除或移动时，不应直接删除已生成 entity，而是把相关 evidence 标记为失效，并在下一次 ingest/repair 时重建。

本版本的实现边界：

- `Choose Folder` 会导入所选文件夹第一层的 `.md`、`.markdown`、`.txt` 文件。
- `Import Files` 支持多选同类文件。
- 拖拽导入使用同一套复制逻辑。
- 文件会复制到当前 My Wiki 项目的 `raw/sources`，遇到同名文件会自动加 `-2`、`-3` 后缀，避免覆盖用户已有素材。
- 列表状态先按是否存在 `wiki/sources/<source>.md` 摘要页区分 `Indexed` 与 `Pending`。`Processing`、`Failed`、`Needs review` 由后续 source queue/repair 版本接入。
- 导入后不会自动清登录态，也不会自动触发全量 ingest；用户仍能先看当前结果，再决定何时运行 My Wiki。

### Pipeline

当前 app 目录里的旧 starter 页面不能再作为正式结果。v1.1 先通过读取层隐藏旧页面，并在验证阶段对当前 app 项目目录运行正式 LLM Wiki headless ingest。

如果 ingest 失败，要明确记录失败；不能再生成 starter fallback 页面来假装成功。

实现收口时，旧 `MyWikiStarterExtractor` 已从产品 target 和测试 target 移除。仓库只保留读取层对历史 starter 页面 `generated_by` 的过滤能力，用来避免旧数据污染正式 My Wiki，而不是继续生成新页面。

如果用户只需要预览，pipeline 可以在部分 source 处理后停止，并保留已经生成的正式 markdown 页面。此时状态应显示为 preview，而不是把它伪装成完整成功。

## 验收标准

- `Adam` 这类 starter 页面不会作为正式 People 结果展示。
- LLM 生成的 `adam-wu.md` 这类页面能显示真实摘要，不再出现 `appears as a real person` 占位文案。
- 点击列表条目的空白区域也能选中。
- 详情页没有默认 `Markdown Page` 原文卡片。
- Source 按钮能打开对应 markdown/source 文件。
- Related 按钮能在 My Wiki 内部跳转。
- 当前 app 项目目录的 ingest 状态变为 `succeeded`，或失败时 UI/状态明确显示失败。
- 用户中止全量 ingest 后，左侧能看到类似 `Preview generated · 23/36 sources` 的紧凑进度。
- 用户能理解 entity 的 `Sources (5)` 是证据数，而不是全局处理数。

## 测试要求

- `MyWikiMarkdownStoreTests`：
  - summary 优先读取 `description`
  - summary 能读取 `## Summary`
  - summary fallback 到首个正文段落
  - starter extractor 页面被过滤
- `MyWikiNavigationResolverTests`：
  - `.md` source 优先解析到 `wiki/sources`
  - raw source 能解析到 `raw/sources`
  - related slug 能解析到 snapshot entry
- Swift targeted tests。
- `xcodebuild build -scheme KnowYou -destination 'platform=macOS'`。
- 启动 freshly built app，用 GUI 验证 My Wiki。
