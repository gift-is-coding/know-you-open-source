# KnowYou 集成说明

本目录来自开源项目 `nashsu/llm_wiki`，用于复用其完整知识本体工作台能力，包括：

- Sources 原始资料管理
- Wiki 页面体系
- Search 搜索
- Graph 图谱
- Lint 与 Review
- Deep Research
- Settings 与模型配置

KnowYou 当前采用“宿主 + 内置 runner”方式集成：

1. KnowYou 左侧栏提供 `My Wiki` 入口。
2. KnowYou 把每日 Markdown 日记同步到 llm_wiki 项目的 `raw/sources/`。
3. 发布版 KnowYou 会内置 `Contents/Resources/MyWikiRunner`，该 runner 打包 llm_wiki 的 headless `autoIngest` 路径和私有 Node runtime。
4. runner 的 LLM 请求通过 `knowyou-bridge` JSONL 协议回到 KnowYou，由 KnowYou 已配置的 Diary Engine 执行；普通用户不需要 npm、Node、额外依赖或第二套 API key。
5. 本目录仍保留 llm_wiki 的 React/Tauri/Rust 工作台，作为开发期调试和上游能力复用源码，不是用户安装包里的运行依赖。

开发期如果需要调试原 llm_wiki 工作台，仍按上游 React/Tauri 项目的开发方式运行；这只服务于本仓库开发者，不是 KnowYou 产品安装、My Wiki 自动生成或普通用户点击 `Update My Wiki` 的依赖。

产品打包不复制额外 GUI 工作台。发布脚本会构建 headless runner 并放入 KnowYou app bundle 的：

```text
Contents/Resources/MyWikiRunner/
```

My Wiki 自动生成只调用这个内置 runner。runner 不包含 `node_modules`，也不会要求用户系统上已有 `npm` 或 `node`。
