# My Wiki v1 索引详情实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 My Wiki 改成高密度索引 + 可读详情 + 编辑/合并闭环。

**Architecture:** 继续复用当前 Swift Markdown-backed My Wiki 管线。先扩展模型和 Markdown store，再实现 rename/duplicate service，最后重构 SwiftUI 页面。

**Tech Stack:** Swift、SwiftUI、XCTest、Markdown frontmatter files。

---

## Task 1: 文档与测试基线

- [ ] 保存中文 spec 和 plan。
- [ ] 确认当前 worktree 是 `codex/my-wiki-redesign`。
- [ ] 在现有测试文件中添加失败测试，覆盖模型解析、People 生成、Patterns 命名、rename 冲突、merge、分组状态。

## Task 2: 模型和 Markdown Store

- [ ] 扩展 `MyWikiEntry`：aliases、related、confidence、mentions、markdownBody、fileURL。
- [ ] 扩展 `MyWikiMarkdownStore`：解析 frontmatter array、source_days、related、aliases 和正文 mentions。
- [ ] 保持旧 `sources` 格式兼容。

## Task 3: Starter Extractor

- [ ] 增加 `wiki/people` starter 页面生成。
- [ ] 用简单候选规则从日记中识别人名/协作对象。
- [ ] 写入 aliases、source days、confidence。

## Task 4: Rename 和 Duplicate 服务

- [ ] 实现 rename 保存：无冲突时更新 title/aliases/body。
- [ ] 实现冲突检测：同 category 下 title/slug 重复时返回 conflict。
- [ ] 实现 duplicate suggestions：规范化 title 和 aliases，找同名/别名重叠候选。
- [ ] 实现 confirmed merge：合并 frontmatter、正文、来源、相关引用，并备份。

## Task 5: SwiftUI

- [ ] 重构 `MyWikiPanel` 为左侧索引 + 右侧内容状态。
- [ ] 每个分组支持展开/折叠、首页截断、`View all`。
- [ ] `MyWikiDetailView` 展示 Summary、Recent Mentions、Sources、Related、Markdown Page。
- [ ] `More` 菜单包含 Find duplicates、Reveal Wiki Folder、Wiki Status。
- [ ] `Edit` sheet 支持 name、aliases、summary，并处理 rename conflict。

## Task 6: 验证

- [ ] 运行 My Wiki targeted tests。
- [ ] 运行 `xcodebuild test -scheme KnowYou -destination 'platform=macOS'`。
- [ ] 运行 `xcodebuild build -scheme KnowYou -destination 'platform=macOS'`。
- [ ] 启动 freshly built app，用 GUI 验证 My Wiki 页面。

## Task 7: 入口卡顿与状态保持修正

- [x] 移除 `MyWikiPanel.onAppear` 的自动同步/抽取调用。
- [x] 增加 lifecycle presentation 测试，确保进入 My Wiki 只 load dashboard。
- [x] 将 `Organize Journals` 放入 `More` 菜单，并通过后台任务执行。
- [x] 为开发构建持久化 Full Disk Access bypass，减少反复重建后的 onboarding 摩擦。
- [x] 修复 `MainWindowViewModelTests` 直接删除真实 `UserDefaults.standard` onboarding keys 的问题，改为快照后恢复。
- [x] 重新运行 targeted tests、完整 `xcodebuild test`、`xcodebuild build`，并用 GUI 验证 My Wiki 点击后不再卡住。

## Task 8: 详情点击性能与错误本体过滤

- [x] 在项目级 `AGENTS.md` 写入 build/rebuild 默认不得清理登录、onboarding、auth、Keychain 或 app container 状态。
- [x] 增加 `MyWikiDetailPresentation`，限制详情页 Markdown preview 长度，避免点击条目时排版整篇大 Markdown。
- [x] 左侧索引和全量列表的选中判断改为 `id + category`，避免 SwiftUI 每行比较完整正文。
- [x] `MyWikiMarkdownStore` 过滤旧 starter extractor 生成的 AI 工具/agent People 页面，例如 `Codex`、`Claude`、`Cowork`。
- [x] `MyWikiStarterExtractor` 删除 Codex/Claude/Cowork 的硬编码 People/Project 候选，避免 fallback 污染真实本体。
- [x] 增加 targeted tests 覆盖 Markdown preview 截断、AI 工具不作为 People、starter 不再生成 Codex 人物。
