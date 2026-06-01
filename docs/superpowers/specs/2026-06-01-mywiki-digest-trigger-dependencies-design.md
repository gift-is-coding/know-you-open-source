# My Wiki Digest 触发与依赖修复设计

## 背景

截图里的失败不是 digest 选择无效，而是 `ThirdParty/llm_wiki/scripts/knowyou-ingest-runner.mjs` 启动时找不到 `vite`。当前 worktree 的 `ThirdParty/llm_wiki/node_modules` 缺失，Node 在执行 runner 顶部 `import { createServer } from "vite"` 时直接抛 `ERR_MODULE_NOT_FOUND`，因此 My Wiki 只显示 `Needs attention`。

## 设计

My Wiki digest 仍保持手动触发语义：选择 digest files 会自动保存，但不会自动 ingest；真正处理只在用户点击 `Update My Wiki` / `Update Now` 时发生。为了让用户知道“什么时候触发”，My Wiki 左侧顶部新增 digest 状态条：

- 标题：`My Wiki digest`
- 触发说明：`Runs when you click Update Now.`
- 时间提示：显示上次 ingest 的本地时间；没有记录时显示 `Not updated yet`
- 手动按钮：`Update Now`

同时修复 development source 依赖缺失：`MyWikiPipelineBridge` 在调用 `npm run knowyou:ingest` 前检查 `node_modules/vite`。缺失时先在 `ThirdParty/llm_wiki` 目录执行 `npm install`；安装失败则写入 `.llm-wiki/last-ingest-status.json` 的 failed 状态并展示明确错误。安装成功后再继续原 ingest 流程。

## 边界

- 本轮不新增后台自动 My Wiki digest。当前产品语义仍是用户确认 source 后手动处理，避免未经确认消耗 LLM 或处理外部 source。
- 本轮不自动升级第三方依赖。`npm audit` 发现的 moderate/high 项来自 `ThirdParty/llm_wiki` 依赖树，单独修复会改变第三方锁文件，应另起任务评估。
