# My Wiki 本体抽取审计

## 结论

当前 My Wiki 的本体质量问题主要不是 UI，而是数据来源混合：

1. 真实 LLM Wiki pipeline 曾生成了一些较好的页面，例如 `KnowYou Beta Readiness`、`Reader Polish`、`Product Trust`。
2. 旧 `MyWikiStarterExtractor` 又生成了硬编码页面，例如 `wiki/people/codex.md`、`wiki/people/claude.md`、`wiki/people/cowork.md`。
3. 这些 starter 页面把 AI 工具、agent 或工作流当成 `People`，这是错误本体。
4. LLM Wiki 原始 generation prompt 默认要求生成 `wiki/entities` 和 `wiki/concepts`，会和 My Wiki 的用户分类冲突。

## 抽取结果样本

### 错误样本：Codex as Person

```yaml
---
type: person
title: Codex
generated_by: KnowYou My Wiki starter extractor
---
```

判断：错误。Codex 在这些日记里是 AI 工具、CLI、agent 或开发协作者抽象，不是现实中的人。应进入 `Topics`，或在确实形成具体工作流时进入 `Projects`，但不应进入 `People`。

### 错误样本：Claude as Person

```yaml
---
type: person
title: Claude
generated_by: KnowYou My Wiki starter extractor
---
```

判断：错误。Claude 默认是 AI 工具或模型，不是人。除非日记明确提到现实中名叫 Claude 的人，否则不得生成 People 页面。

### 可接受样本：Huang Shan as Person

```yaml
---
type: person
title: Huang Shan
sources: ["knowyou-diary-2026-04-09.md"]
---
```

判断：方向可接受，但摘要质量仍不足。页面需要说明这个人是谁、与用户有什么关系、在哪些事项中出现、证据来自哪些日期，而不是泛泛地说 “appears in recent journals”。

### 可接受样本：Reader Polish as Topic

```yaml
---
type: concept
title: Reader Polish
sources: ["knowyou-diary-2026-04-04.md", "knowyou-diary-2026-04-06.md"]
---
```

判断：内容质量较好，但类型需要迁移。对用户显示应归入 `Topics`，内部 frontmatter 可以兼容旧 `concept`，但 My Wiki UI 不应让用户看到 `concept` 这个技术分类。

## 修正规则

- `People` 只收真实人。
- `Projects` 收用户正在推进的具体工作、产品、研究、计划。
- `Topics` 收反复出现的主题、问题、兴趣、方法。
- `Patterns` 收稳定偏好、工作方式、沟通习惯。
- `Follow-ups` 收需要继续处理或确认的事项。
- Codex、Claude、ChatGPT、Gemini、Openclaw、Cowork 等默认不是人。
- 单次提及不能生成一个 People 页面，除非该人是当日核心对象。

## 本次代码修正

- UI 过滤旧 starter 生成的 AI 工具/agent People 页面。
- starter extractor 不再硬编码 Codex/Claude/Cowork 为 People 或 Project。
- My Wiki generation prompt 在检测到 My Wiki contract 后，不再要求 `wiki/entities` / `wiki/concepts`。
- 详情页只渲染 Markdown preview，避免点击条目时完整排版大文件。
- 列表选中状态只比较 `id + category`，避免比较完整正文。

## 真实 pipeline smoke

临时项目单篇运行：

```bash
npm run knowyou:ingest -- --project /tmp/knowyou-mywikitest.DlI5Gb --provider codex-cli --model gpt-5.4 --max-sources 1
```

结果：超过 6 分钟仍停在第一阶段，未生成 markdown 文件。状态为：

```json
{
  "status": "running",
  "message": "Ingesting 1 source file(s).",
  "sourcesProcessed": 0,
  "filesWritten": []
}
```

这说明 Codex CLI transport 可以启动，但当前不适合作为前台交互 pipeline。下一步应该优化 pipeline 编排，而不是继续把慢任务放在点击路径上。

## 2026-05-16 真实日记抽取审计

### 根因修正

这次审计确认：单纯“命令运行成功”不等于本体成功。之前最大的问题是抽取器会把 AI 工具、开发工作流或 UI 文案误当成 People。尝试过通用英文人名正则后，真实日记里出现了大量误报，例如类名、应用名、公司名和界面词。因此 v1 不使用泛化人名正则，而采用保守候选 + 证据行命中的方式。

本次修正后的规则：

- People 只生成真实人物。
- Events 单独承接会议、面试、申请、启动会等具体事件。
- Projects 承接持续推进的产品、研究、计划或工作流。
- Topics 承接反复出现的问题、主题和方法。
- Patterns 承接稳定偏好和工作方式。
- Codex、Claude、Cowork、ChatGPT、OpenAI 等默认是工具、agent、模型或工作流，不进入 People。

### 输入覆盖

真实项目目录：

`~/Library/Application Support/KnowYou/KnowledgeOntology/KnowYouContext`

实际日记来源：

- `raw/sources`：36 个 `knowyou-diary-*.md`
- legacy `wiki/sources`：5 个 `knowyou-diary-*.md`
- 按文件名去重后：36 篇日记

抽取器现在同时读取两个目录，避免历史迁移目录里的日记被漏掉。

### 输出结果

本地 starter extractor 在真实数据上写出 41 个 My Wiki 页面：

- People：Adam、Brad、Cynthia Li、Gina、Hollis Qi、Huang Shan、Johnson、Meg、QiangA Guo、Shuo Zhou、Vivian Sun、Xuguang Gu、Zhen Yu、Zhenlei Dai
- Projects：AI Native Enterprise Framework、AIDC Research、Compliance Process Plan、KnowYou、KnowYou Beta Readiness、My Wiki、Project10 BMS Coordination、Qingtian 5.0 Acceleration、Software R&D Agents
- Events：AI Ontology Exchange、BMS Meeting、ByteDance Interview Notice、Investor Or Incubator Application Push、Lenovo-IDC Strategic Cooperation Meeting、Qingtian 5.0 Launch Meeting
- Topics：AI Agent Collaboration、Demo Readiness、Diary-First Onboarding、Evidence Provenance、Historical Refresh Isolation、Layout Stability、Local Privacy Boundaries、MVP Validation Metrics、Ontology Quality、Pipeline Performance、Product Simplicity、Product Trust、Reader Polish、Reading Continuity、Screenshot and Recording Legibility、Search and Summaries、Source App Logos、Story-First Demo Flow、Trustworthy First Screen
- Patterns：English Market UI、Prefer Lightweight UX、Preserve Login State、Reuse Existing Code、Test Before Push
- Follow-ups：April 6 Follow-Ups、Follow-ups

### 审计结论

- `wiki/people/codex.md`、`wiki/people/claude.md`、`wiki/people/cowork.md`、`wiki/people/chatgpt.md`、`wiki/people/openai.md` 均不存在。
- `wiki/events/bms-meeting.md` 是 `type: event`，并包含会议时间、房间、参与人和 BMS/Project10 线索。
- `wiki/projects/project10-bms-coordination.md` 是 `type: project`，承接持续工作流，而不是单次会议。
- `wiki/preferences/preserve-login-state.md` 是 `type: preference`，承接“不要清登录态”的稳定工作偏好。
- My Wiki 分类目录中的 frontmatter type 已全部规范化，没有遗留 `entity`、`concept`、`query`。

因此当前本地抽取的最低可用标准已经达到：它不是完整智能本体，但能在真实日记上保持基本语义边界，不再把工具当人，也不会把事件混进人物。
