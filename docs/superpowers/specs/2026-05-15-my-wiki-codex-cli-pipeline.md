# My Wiki Codex CLI Pipeline 规格

## 背景

My Wiki 的目标不是展示硬编码样例，而是复用 LLM Wiki 已经验证过的后端 pipeline：从日记原文中抽取可读 wiki 页面，并维护实体、来源、关系、总结、去重建议等结构化信息。

用户明确要求：

- 优先参考并复用 `ThirdParty/llm_wiki` 的 pipeline。
- 参考 LLM Wiki 使用 Claude Code CLI 的方式，尝试接入 Codex CLI。
- 如果真实 llm_wiki/Codex CLI pipeline 不可用，必须写失败状态；但 My Wiki 仍应先运行本地确定性 starter extractor，生成可审计的 markdown 起始页，避免用户页面空白。
- 文档继续使用中文。

## LLM Wiki 调研结论

LLM Wiki 的 Claude Code CLI 不是一个“自治 agent runner”，而是一个 LLM provider transport：

- Rust/Tauri 侧负责检测并启动 `claude` CLI。
- TypeScript 侧把聊天消息转成 Claude CLI 可接受的输入。
- pipeline 本身仍在 `src/lib/ingest.ts`、`src/lib/page-merge.ts`、`src/lib/dedup.ts`、`src/lib/dedup-runner.ts` 中执行。

真正值得复用的后端能力包括：

- `ingest.ts`：两阶段抽取。第一阶段分析原文，第二阶段生成 `FILE` / `REVIEW` 输出。
- `page-merge.ts`：合并已有页面，frontmatter 做确定性 union，正文用 LLM 合并。
- `ingest-queue.ts`：队列、重试、项目切换保护、失败记录。
- `text-chunker.ts`：面向 embedding/search 的 Markdown-aware 切片。它保护标题、段落、表格和代码块。
- `dedup.ts` / `dedup-runner.ts`：重复实体发现与用户确认后的合并。

重要边界：LLM Wiki 的 ingest prompt 目前会截断长 source；复杂切片主要服务于 embedding/search，不是 ingest 主路径。

## v1 范围

本阶段完成“真实 provider 接入 + headless runner + 高级 pipeline 失败透明 + 本地起始页可审计”：

- 在 LLM Wiki 中新增 `codex-cli` provider。
- 复用 LLM Wiki 现有 LLM client 抽象，让 ingest/dedup 未来可以直接选择 Codex CLI。
- 增加 KnowYou 专用 headless runner，通过 Vite SSR 加载 LLM Wiki 的 `autoIngest`。
- KnowYou 的 My Wiki bridge 先运行本地 starter extractor，再调用 `npm run knowyou:ingest`；高级 pipeline 失败时写入失败状态并抛错。
- starter extractor 不得生成假成功或错误本体：它只能生成保守候选，并必须把 People、Projects、Events、Topics、Patterns、Follow-ups 分清楚。

## 非目标

- 本阶段不声称 My Wiki 已经完成端到端真实抽取。
- 本阶段不自动合并重复实体。
- 本阶段不自动 push。
- 本阶段不把 Codex CLI 当成可任意操作文件系统的 agent；它只作为 LLM completion provider。

## 期望行为

### Codex CLI provider

- 设置页可以选择 `Codex CLI (local)`。
- 不要求 API Key。
- 可以检测本机 `codex` 是否存在。
- 调用时通过 `codex exec` 获取最终回答文本。
- `getProviderConfig` 不应处理 `codex-cli`，因为它不是 HTTP provider。

### Headless runner

- `npm run knowyou:ingest -- --project <path> --provider codex-cli --model gpt-5.5` 可以直接运行。
- runner 使用 Node FS adapter 替代 Tauri 文件命令。
- runner 使用 headless Tauri core adapter 调用本机 Codex CLI。
- runner 会向 `schema.md` 注入 KnowYou My Wiki 输出契约，限制生成目录为：
  - `wiki/people`
  - `wiki/projects`
  - `wiki/events`
  - `wiki/themes`
  - `wiki/preferences`
  - `wiki/open-loops`
  - `wiki/summaries`
  - `wiki/sources`
- runner 明确禁止 `wiki/entities`、`wiki/concepts` 等通用本体目录。

### KnowYou bridge

- 如果找不到 LLM Wiki pipeline，写入 `.llm-wiki/last-ingest-status.json`：
  - `status: failed`
  - `message`
  - `updatedAt`
- 如果开发源码存在且包含 runner，则调用真实 pipeline。
- 如果 runner 失败，写失败状态并把错误暴露给 UI。
- pipeline bridge 会先运行本地 starter extractor，保证已有日记能生成起始 My Wiki 页面；随后运行真实 llm_wiki pipeline。真实 pipeline 缺失或失败时，必须写入 failed 状态，不得把高级 pipeline 标记为 succeeded。

## 后续方向

下一步是增强质量和产品化：

- 将 `dedup-runner` 也接入 KnowYou 的主动发现流程。
- 为 35+ 日记增加分批、进度、取消和恢复。
- 优化 schema/prompt，让 People/Projects/Topics/Patterns 的质量更稳定。
- 把当前开发源码 runner 打包成随 app 分发的 helper 或内置资源。

## 2026-05-15 验证发现

真实 Codex CLI smoke 使用临时项目和 `knowyou-diary-2026-05-15.md` 单篇日记运行：

```bash
npm run knowyou:ingest -- --project /tmp/knowyou-mywikitest.DlI5Gb --provider codex-cli --model gpt-5.4 --max-sources 1
```

结果：运行超过 6 分钟仍停留在第一阶段 Codex CLI 调用，`.llm-wiki/last-ingest-status.json` 保持：

```json
{
  "status": "running",
  "message": "Ingesting 1 source file(s).",
  "sourcesProcessed": 0,
  "filesWritten": []
}
```

结论：

- Codex CLI provider 路径已经被调用，但当前单篇吞吐不可接受，不能绑定到前台点击。
- v1 必须把 ingest 做成明确的后台队列，带进度、取消、失败状态和可恢复。
- 现有真实项目中的 `wiki/people/codex.md`、`wiki/people/claude.md`、`wiki/people/cowork.md` 是旧 starter extractor 生成的错误页面，不是可接受的本体结果。
- LLM Wiki 原始 prompt 即使有 My Wiki contract，也仍会提示生成 `wiki/entities` / `wiki/concepts`；My Wiki 模式必须覆盖为 People/Projects/Topics/Patterns/Follow-ups。

## 2026-05-16 本地本体抽取结论

真实 Codex CLI pipeline 仍不适合作为前台路径，因此当前可用闭环是：

1. 本地 starter extractor 读取 `raw/sources/` 和 legacy `wiki/sources/`，按文件名去重。
2. 先生成可审计 markdown 起始页。
3. 再尝试 llm_wiki/Codex CLI 高级 pipeline。
4. 高级 pipeline 失败时只把高级状态写为 failed，不撤回本地 markdown。

本次真实 KnowYouContext 审计结果：

- 输入：`raw/sources` 36 个日记文件，`wiki/sources` 5 个 legacy 文件，按文件名去重后 36 篇。
- 输出：41 个 starter 页面。
- People：14 个真实人物页面；没有 `codex.md`、`claude.md`、`cowork.md`、`chatgpt.md`、`openai.md`。
- Projects：9 个工作流/项目页面。
- Events：6 个会议、面试、申请类事件页面。
- Topics：19 个主题页面。
- Patterns：5 个偏好/工作模式页面。
- Follow-ups：2 个待跟进页面。
- 所有 My Wiki 分类目录中的 frontmatter type 均与目录语义一致，没有遗留 `entity/concept/query`。
