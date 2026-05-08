# KnowYou 集成说明

本目录来自开源项目 `nashsu/llm_wiki`，用于复用其完整知识本体工作台能力，包括：

- Sources 原始资料管理
- Wiki 页面体系
- Search 搜索
- Graph 图谱
- Lint 与 Review
- Deep Research
- Settings 与模型配置

KnowYou 当前采用“宿主 + 子系统”方式集成：

1. KnowYou 左侧栏提供 `知识本体` 入口。
2. KnowYou 把每日 Markdown 日记同步到 llm_wiki 项目的 `raw/sources/`。
3. 本目录保留 llm_wiki 的 React/Tauri/Rust 功能，不用 SwiftUI 重写图谱系统。
4. KnowYou 启动开发版时会设置环境变量 `KNOWYOU_KNOWLEDGE_PROJECT_PATH`，本地改动会优先打开该项目。
5. 前端默认强制 `dark` class，使其更接近 KnowYou 的黑色风格。

开发运行：

```bash
cd ThirdParty/llm_wiki
npm install
KNOWYOU_KNOWLEDGE_PROJECT_PATH="$HOME/Library/Application Support/KnowYou/KnowledgeOntology/KnowYouContext" npm run tauri dev
```

后续打包时，可以把构建出的 `LLM Wiki.app` 放入 KnowYou app bundle 的：

```text
Contents/Resources/KnowledgeOntology/LLM Wiki.app
```

KnowYou 会优先打开 bundled helper；如果 helper 不存在，则回退到当前仓库的 `ThirdParty/llm_wiki` 开发源码目录。
