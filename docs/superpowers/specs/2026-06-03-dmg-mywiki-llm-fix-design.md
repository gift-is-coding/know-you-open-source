# DMG 安装页与 MyWiki LLM 修复设计

## 背景

本次修复在独立 worktree `/Users/wutianfu/Documents/code/know-you/.worktrees/fix-dmg-mywiki-llm` 和分支 `codex/fix-dmg-mywiki-llm` 上进行。当前主 checkout 有未提交改动，本分支从 `origin/main` 新建，避免影响用户现有工作。

## 已确认问题

1. DMG 拖拽安装页的主要问题是错位，不是单纯模糊。背景箭头原来写死在 `x=235...325`，但 Finder icon center 是 KnowYou `{150,148}`、Applications `{430,148}`，icon size 是 `96`。箭头终点离 Applications icon 左边界还有明显距离，视觉上像没有指向目标。
2. 背景 PNG 还存在 Retina 像素密度不足风险：Finder window 是 `560x300` points，原背景只有 `560x300` pixels。
3. MyWiki LLM 对普通用户不可用的根因不是“用户 PATH 没 npm”这么小，而是当前自动 ingest 路径仍是开发者形态：Swift bridge 回退到 `ThirdParty/llm_wiki` 后执行 `npm run knowyou:ingest`，普通用户没有源码、node_modules、Node/npm。
4. MyWiki headless runner 还硬编码 `--provider codex-cli --model gpt-5.5`，没有复用 KnowYou 已配置的 Diary Engine / LLM API。普通用户即使配置了 OpenAI、Anthropic、Gemini 或 OpenAI-compatible API，MyWiki 也不会使用。

## 目标

- DMG 背景箭头用同一套 layout constants 从 Finder icon center 与 icon size 派生，避免再手写错位坐标。
- DMG 背景输出 `1120x600` pixels，同时保持 `560x300` point 布局。
- MyWiki ingest 使用 KnowYou 已保存的 LLM 配置生成 runner 参数；API key 通过环境变量传递，不放进命令行参数。
- 保留失败状态写入，不把 LLM pipeline 失败伪装成本地 fallback 成功。

## 非目标

- 不重写 MyWiki 的 LLM 语义 pipeline。
- 不清空用户的 MyWiki、UserDefaults、Keychain、TCC 或 app container。
- 本分支不发布远端 release、不 push。
- 不在这次小修里完成完整的 headless runner 产品化打包；这仍是普通用户完全摆脱 Node/npm 的后续发布工程项。

## 实现设计

### DMG

`scripts/build-dmg.sh` 的 Swift 背景生成器使用 `appIconCenterX`、`applicationsIconCenterX`、`iconCenterY`、`iconSize` 定义布局。箭头从 `appIconCenterX + iconSize / 2 + 32` 指向 `applicationsIconCenterX - iconSize / 2 - 18`，确保它位于两个 icon 框之间并接近 Applications 目标。

同时保留 Retina-safe bitmap：`pixelsWide = width * 2`、`pixelsHigh = height * 2`，并设置 `bitmap.size` 为 point 尺寸。

`scripts/test-build-dmg-layout.sh` 断言背景 generator 中存在这些 layout constants，并继续验证输出 PNG 是 `1120x600` pixels。

### MyWiki

`MyWikiLLMInvocation` 从 `SummarizerConfig` 解析 MyWiki runner 参数：

- `llmAPI`：映射到 llm_wiki 支持的 provider。OpenAI/Anthropic/Gemini 走对应 provider；DeepSeek/OpenRouter/Qwen/Kimi/Zhipu/custom 走 `custom` + endpoint + api mode。
- API token 写入 `KNOWYOU_MYWIKI_LLM_API_KEY` 环境变量。
- Claude CLI / Codex CLI 只在用户明确选用对应 engine 时使用，并把已解析 CLI 所在目录 prepend 到 PATH。
- 不支持的 engine 写入明确失败状态。

`ThirdParty/llm_wiki/src/headless/knowyou-ingest.ts` 接受 `--custom-endpoint`、`--ollama-url`、`--api-mode`，并从 `KNOWYOU_MYWIKI_LLM_API_KEY` 读取 API key。

保留 `MyWikiNPMResolver` 只作为 development-source fallback 的开发者兼容层；它不是普通用户的最终运行时方案。

## 测试

- `scripts/test-build-dmg-layout.sh`
- `xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/MyWikiPipelineBridgeTests`
- `npx vitest run src/headless/knowyou-ingest.test.ts`
- 完整验证按仓库标准执行：`xcodebuild test -scheme KnowYou -destination 'platform=macOS'`、`xcodebuild build -scheme KnowYou -destination 'platform=macOS'`、`git diff --check`
