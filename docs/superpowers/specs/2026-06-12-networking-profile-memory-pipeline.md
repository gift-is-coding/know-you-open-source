# Networking Profile Memory Pipeline 设计

## Summary

Networking 的 profile 生成不应再把 My Wiki 当成普通文件搜索，也不应默认扫描 `raw/sources`。V1 改成以 My Wiki 为长期记忆层：先按场景选择相关的 wiki 记忆页，再把干净的 context pack 交给 LLM 生成职业和个人两个公开 profile draft。draft 应该是可审核的 profile 原文，不只是短摘要；summary 只作为 UI 顶部预览。

## Key Decisions

- 默认只读取 `wiki/` 下的记忆页，但排除 `wiki/sources` 证据镜像层；当前实现优先使用 `entities`、`concepts`、`synthesis`、`comparisons` 和 `queries` 等长期记忆页。
- `raw/sources` 只作为 My Wiki ingest 的证据层和人工诊断层，不进入 profile generation 默认 prompt。
- 职业 profile 使用 career lens，优先工作、项目、产品、agent、协作、招聘、平台、工程和企业 AI 相关页面。
- 个人/社交 profile 使用 friends lens，优先兴趣、活动、生活节奏、表达风格、社交边界和非敏感个人偏好相关页面。
- 生成失败或记忆不足时返回 degraded/failed，不生成虚构 profile。
- 公开 draft 只包含可公开摘要和 My Wiki citation，不包含原始证据、深层匹配理由、账号、token、私密关系或完整联系方式。
- 生成目标是 2,000 到 3,000 words、6 到 10 个有标题的 sections；App 需要同时显示 `Draft summary` 和 `Full profile draft`，让用户能审批原文。

## Data Flow

1. UI 或命令选择 `NetworkingProfileScenario.jobs` / `NetworkingProfileScenario.friends` / custom scenario。
2. `MyWikiNetworkingContextProvider` 构建 scenario lens，并只从 `wiki/` 目录枚举候选页。
3. 候选页按 path/type/title/body 中的场景相关度、My Wiki 页面类型和敏感边界进行排序。
4. 选出最多 18 个页面，在 16k 字符预算内压缩为 `NetworkingProfileContext.summary`，并保留 `citations`。
5. `NetworkingPromptProfileGenerator` 使用更明确的公开 profile schema 生成 summary 和 6-10 个完整 sections。
6. draft 默认是 private，需要用户 `Approve profile` 后才可同步到平台或给 agent 自动互动使用。

## Acceptance

- Career/Friends 两个默认场景都能用用户本地 My Wiki 生成 profile draft。
- Profile context citations 不包含 `raw/sources/`。
- Career context 里优先出现工作、项目、agent、产品、工程相关 My Wiki 页面。
- Friends context 里优先出现兴趣、生活、社交或个人表达相关 My Wiki 页面；如果 My Wiki 里相关内容不足，要显式表现为记忆不足，而不是编造。
- 生成 profile 的 prompt 必须要求脱敏、公开表达和人工 approval。
- 生成后的 App 预览不能只显示 summary；必须显示完整 draft body，并且有明确的 `Approve profile` 操作。
