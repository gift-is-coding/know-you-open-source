# MyWiki Bundled Runner 产品化设计

## 背景

当前 MyWiki 自动生成链路把 `ThirdParty/llm_wiki` 当成开发源码运行时来调用。开发机上可以通过 `npm run knowyou:ingest` 跑通，但普通用户安装 `KnowYou.app` 后没有源码目录、`node_modules`、Node/npm，也不会知道为什么需要这些依赖。因此用户点击 Generate Wiki 后可能在后台失败，体感像“没有反应”。

之前的 `LLM Wiki.app` 是为复用上游 `llm_wiki` Tauri 工作台而引入的 GUI helper。它不是 KnowYou 后台可直接调用的 headless ingest runner，也不应该继续作为 MyWiki 自动生成主路径。后续项目应做减法：用户只安装和理解 `KnowYou.app`，不再暴露或打包一个额外的 `LLM Wiki.app`。

## 目标

1. MyWiki 生成必须作为 `KnowYou.app` 的内置能力发布，普通用户不需要安装 npm、Node、Vite 或 `ThirdParty/llm_wiki` 源码。
2. MyWiki 必须复用 KnowYou 当前 Diary Engine。用户只配置一次 engine/API；只要日记生成可用，MyWiki 就应可用。
3. API key 和 provider 细节留在 KnowYou 主 app/Keychain 中，不传给 headless runner，也不作为命令行参数或环境变量暴露。
4. MyWiki 继续复用 `llm_wiki` 原生 `autoIngest` 语义 pipeline，避免用 Swift 重写 ontology 抽取、页面合并、related links 和 review 逻辑。
5. 删除 `LLM Wiki.app` 作为产品运行时的定位。它不再作为 bundled helper、备用高级工作台或用户可见入口。
6. 所有失败必须写入可见状态并反馈给 UI，不得静默失败。

## 非目标

- 不重写 `llm_wiki` 的核心 ontology pipeline。
- 不把 `LLM Wiki.app` 继续打进 KnowYou 发布包。
- 不要求用户单独配置 MyWiki API key。
- 不让 runner 直接访问 OpenAI、Anthropic、Gemini、DeepSeek、OpenRouter 等外部 LLM API。
- 不保留“打开 LLM Wiki 工作台”作为 MyWiki 的正式用户路径。

## 推荐架构

```
KnowYou.app
  Contents/
    MacOS/KnowYou
    Resources/
      MyWikiRunner/
        node
        mywiki-runner.js
        runtime-assets/
```

运行时链路：

```
Generate Wiki
-> KnowYou 同步 MyWiki sources / manifest
-> Swift 启动 Resources/MyWikiRunner/mywiki-runner.js
-> runner 调用 llm_wiki autoIngest
-> runner 遇到 LLM 请求时通过 stdio JSONL 发给 KnowYou
-> KnowYou 用 Diary Engine 执行请求
-> KnowYou 把响应通过 stdio JSONL 回给 runner
-> runner 写入 wiki/sources, wiki/entities, wiki/concepts 和 last-ingest-status
-> Swift UI 刷新结果或展示失败原因
```

## 组件边界

### Bundled MyWikiRunner

`MyWikiRunner` 是 KnowYou 私有运行时资源，不是独立 app。它包含固定版本的 Node 二进制和从 `ThirdParty/llm_wiki/src/headless/knowyou-ingest.ts` 打包出的 JS runner。发布包中不得包含 `node_modules`，运行时不得调用 `npm install`、`npm run` 或依赖用户 PATH。

runner 负责：

- 读取 `--project`、`--manifest`、`--max-sources` 等 ingest 参数。
- 调用 `llm_wiki` 原生 `autoIngest`。
- 维护 `.llm-wiki/last-ingest-status.json`。
- 通过 stdout/stderr 或 JSONL 事件向 Swift 报告进度、失败和完成状态。

runner 不负责：

- 保存或读取 API key。
- 判断用户用哪个 provider。
- 直接请求外部 LLM API。
- 打开窗口或提供工作台 UI。

### KnowYou MyWiki LLM Bridge

Swift 侧新增 MyWiki LLM bridge，作为 runner 和 Diary Engine 之间的内部协议层。第一版使用子进程 `stdin/stdout` JSONL 通信，不开放 localhost 端口。

请求示例：

```json
{"type":"llm.request","id":"req-1","messages":[{"role":"user","content":"..."}],"temperature":0.2}
```

响应示例：

```json
{"type":"llm.response","id":"req-1","content":"..."}
```

失败示例：

```json
{"type":"llm.error","id":"req-1","code":"auth_failed","message":"Diary Engine authentication failed."}
```

Bridge 负责：

- 从现有 `SummarizerConfig` / Diary Engine 读取当前 engine。
- 通过现有 provider adapter 发起 LLM 请求。
- 保留 Keychain/API token 在主进程内。
- 把认证失败、限流、网络错误、未配置 engine 等错误转换成 runner 可理解的结构化错误。

### Diary Engine

Diary Engine 是唯一的 LLM 出口。MyWiki 不建立第二套 provider 配置，也不绕过 proxy、retry、错误处理和用户选择的模型策略。

第一版只要求支持 MyWiki `autoIngest` 所需的文本 LLM 请求。如果未来 MyWiki 需要 embedding、vision 或 streaming，再扩展 bridge 的 `embedding.request`、`vision.request` 或 `llm.delta` 消息；不得让 runner 临时直连外部 API。

## LLM Wiki.app 删除策略

实现时应把 `LLM Wiki.app` 从产品架构中删除：

- KnowYou 发布包不再拷贝或签名 `KnowledgeOntology/LLM Wiki.app`。
- MyWiki 自动生成不再解析 `KnowledgeOntologyLauncher.defaultBundledHelperAppURL()` 作为可运行目标。
- 用户界面不再提供打开 `LLM Wiki.app` 的正式入口。
- `ThirdParty/llm_wiki` 源码可以保留在仓库里，作为构建 headless runner 的源码输入；它不是用户安装后的运行时依赖。
- 旧的 `KnowledgeOntologyLauncher` / `KnowledgeOntologyPanel` 若只服务 GUI helper，应在实现阶段删除或降级为内部迁移代码，不能继续成为产品路径。

## 错误与状态

Generate Wiki 必须把失败变成用户可见状态：

- `runner_missing`：发布包缺少 `Resources/MyWikiRunner`。
- `runner_not_executable`：runner 或内置 node 不可执行。
- `engine_not_configured`：Diary Engine 未配置。
- `auth_failed`：Diary Engine 认证失败。
- `network_failed`：Diary Engine 网络请求失败。
- `runner_crashed`：runner 非零退出或 JSONL 协议中断。
- `no_pages_written`：ingest 完成但没有写出任何 wiki 页面。

这些状态写入 `.llm-wiki/last-ingest-status.json`，并在 Swift UI 中展示简短可读说明。UI 不得只显示 spinner 或吞掉错误。

## 构建与发布

新增构建步骤应产出可复制到 app bundle 的 `MyWikiRunner` 目录：

1. 使用固定 Node 版本作为私有运行时。
2. 将 headless runner 打包为无 `node_modules` 的 JS bundle。
3. 在 Xcode resource 阶段或 release script 中复制 `MyWikiRunner` 到 `KnowYou.app/Contents/Resources/`。
4. release signing 必须覆盖内置 node 可执行文件和 runner 相关可执行资源。
5. notarization 前检查发布包中不存在 `LLM Wiki.app`、`node_modules`、`ThirdParty/llm_wiki` 源码目录。

Debug 开发环境可以继续从源码构建 runner，但产品路径必须始终验证 bundled runner 能运行。

## 测试要求

- Swift unit tests 覆盖 MyWiki target resolution：普通用户路径只接受 bundled `MyWikiRunner`，不接受 `LLM Wiki.app`。
- Swift process tests 使用 fake runner 验证 JSONL LLM request/response/error 协议。
- Swift tests 验证 API key 不进入 runner arguments 或 environment。
- TypeScript/Vitest 覆盖 `knowyou-bridge` provider：`autoIngest` 调用 LLM 时走 bridge，而不是外部 provider。
- 真实 Diary 验收测试必须使用一组真实日记 Markdown 文档作为输入，经过 bundled MyWikiRunner 和 Diary Engine bridge 跑完整 ingest，并验证输出包含可追溯的 `wiki/sources`、`wiki/entities`、`wiki/concepts` 本体页面；不得只用空 fixture 或纯 mock 判断成功。
- Build script tests 验证 runner bundle 中没有 `node_modules`，且不会包含 `npm run` 运行时路径。
- Release tests 验证 `KnowYou.app/Contents/Resources/MyWikiRunner` 存在、可执行，且 `KnowledgeOntology/LLM Wiki.app` 不存在。
- 完整验证继续运行 `xcodebuild test -scheme KnowYou -destination 'platform=macOS'` 和 `xcodebuild build -scheme KnowYou -destination 'platform=macOS'`。

## 成功标准

- 一台没有 Node/npm 的普通 macOS 用户机器安装 KnowYou 后，可以点击 Generate Wiki 并生成 MyWiki 页面。
- 用户无需为 MyWiki 重新配置 API。
- 关闭或删除 `LLM Wiki.app` 不影响 MyWiki 自动生成。
- MyWiki 失败时 UI 显示明确原因。
- 发布包中只有 `KnowYou.app` 作为用户可见 app。
