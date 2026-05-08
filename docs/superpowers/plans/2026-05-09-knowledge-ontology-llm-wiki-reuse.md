# 知识本体 llm_wiki 复用实施计划

## 总体策略

先打通“KnowYou 左侧入口 -> 日记导出 -> llm_wiki 兼容项目 -> 打开复用工作台”的完整链路。避免在第一版重写 llm_wiki 的图谱和抽取功能。

## 任务 1：建立知识本体项目导出器

测试先行：

- 新增 `KnowledgeOntologyProjectExporterTests`
- 验证第一次同步会创建 llm_wiki 兼容目录结构
- 验证 `YYYY-MM-DD.md` 会导出为 `raw/sources/knowyou-diary-YYYY-MM-DD.md`
- 验证重复同步会覆盖同名文件且不产生重复文件

实现：

- 新增 `KnowledgeOntologyProjectExporter`
- 复用 llm_wiki 的项目目录约定
- 为 KnowYou 日记添加最小 frontmatter

## 任务 2：建立知识本体 launcher

测试先行：

- 新增 `KnowledgeOntologyLauncherTests`
- 验证优先选择 bundled helper app
- 验证没有 bundled helper 时选择开发源码目录
- 验证二者都不存在时返回缺失状态

实现：

- 新增 `KnowledgeOntologyLauncher`
- 封装 `NSWorkspace.openApplication` 与 dev source fallback
- 不在测试中真实启动外部进程

## 任务 3：加入左侧 `知识本体` 入口和宿主页

实现：

- `DateSidebarView` 增加 `知识本体` 按钮
- `MainWindowView` 增加 reader / ontology 两种主模式
- 新增 `KnowledgeOntologyPanel`
- 宿主页提供同步、打开、显示路径和状态
- 颜色使用黑色背景、浅色文字，贴近 KnowYou 风格

## 任务 4：vendor llm_wiki 并记录复用方式

实现：

- 添加 `ThirdParty/llm_wiki`
- 排除 `.git`、`node_modules`、`dist`、`target`
- 增加 `ThirdParty/llm_wiki/KNOWYOU_INTEGRATION_CN.md`
- 主题层做 KnowYou 黑色风格微调

## 任务 5：同步项目文档

实现：

- 更新 `docs/architecture.md`
- 更新 `docs/requirements-spec.md`

## 任务 6：验证

必须运行：

- `xcodebuild test -scheme KnowYou -destination 'platform=macOS'`
- `xcodebuild build -scheme KnowYou -destination 'platform=macOS'`

如果完整测试耗时或环境失败，至少先运行新增测试切片并保留完整失败输出。
