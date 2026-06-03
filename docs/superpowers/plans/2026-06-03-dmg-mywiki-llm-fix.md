# DMG 安装页与 MyWiki LLM 修复实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复 DMG 拖拽页背景与 Finder icon 的坐标错位，并让 MyWiki LLM 使用 KnowYou 已配置的 LLM 引擎，而不是默认依赖开发者机器上的 npm + Codex CLI。

**Architecture:** DMG 侧让背景 geometry 从 icon center/icon size 派生；MyWiki 侧新增 LLM invocation 解析与 runner 参数传递，不改变 llm_wiki 的语义 pipeline、source catalog 或 fallback 语义。

**Tech Stack:** Bash, Swift/AppKit background generator, XCTest, Vitest, macOS `sips`, MyWiki Swift bridge, llm_wiki TypeScript headless runner.

---

### Task 1: DMG 几何错位测试与修复

**Files:**
- Modify: `scripts/test-build-dmg-layout.sh`
- Modify: `scripts/build-dmg.sh`

- [x] 在 `scripts/test-build-dmg-layout.sh` 写失败测试：断言背景 generator 使用 `appIconCenterX`、`applicationsIconCenterX`、`iconCenterY`、`iconSize` 和派生 arrow coordinates。
- [x] 运行 `scripts/test-build-dmg-layout.sh`，确认当前失败在缺少背景 icon center 常量。
- [x] 修改 `scripts/build-dmg.sh`：用 Finder icon center 和 icon size 派生箭头起点/终点，同时保留 Retina-safe bitmap。
- [x] 生成修复后背景图，确认箭头视觉上对齐 Applications 方向。
- [x] 重新运行 `scripts/test-build-dmg-layout.sh`，确认通过。

### Task 2: MyWiki LLM 配置与 runner 参数修复

**Files:**
- Modify: `KnowYouTests/MyWikiPipelineBridgeTests.swift`
- Modify: `KnowYou/Services/MyWiki/MyWikiPipelineBridge.swift`
- Modify: `ThirdParty/llm_wiki/src/headless/knowyou-ingest.ts`
- Modify: `ThirdParty/llm_wiki/src/headless/knowyou-ingest.test.ts`

- [x] 写失败测试：`SummarizerConfig` 为 LLM API 时，MyWiki 生成 custom provider/model/endpoint/api-mode 参数，API key 只进环境变量。
- [x] 写桥接调用测试：`runIngest` 把 LLM invocation arguments 和 environment 传给 process runner。
- [x] 运行 focused XCTest，确认新测试失败。
- [x] 实现 `MyWikiLLMInvocation`，让 MyWikiDigestRunner 默认从 `SummarizerConfig.load()` 解析 LLM 配置。
- [x] 扩展 process runner 支持环境变量传递。
- [x] 扩展 llm_wiki headless runner，支持 `--custom-endpoint`、`--ollama-url`、`--api-mode` 与 `KNOWYOU_MYWIKI_LLM_API_KEY`。
- [x] 添加 Vitest 覆盖 runner 读取 KnowYou LLM API 参数。
- [x] 重新运行 focused XCTest 和 Vitest。

### Task 3: 验证与交付

**Files:**
- Review: all changed files

- [x] 运行 `scripts/test-build-dmg-layout.sh`。
- [x] 运行 `xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/MyWikiPipelineBridgeTests`。
- [x] 运行 `npx vitest run src/headless/knowyou-ingest.test.ts`。
- [x] 运行完整 `xcodebuild test -scheme KnowYou -destination 'platform=macOS'`。
- [x] 运行完整 `xcodebuild build -scheme KnowYou -destination 'platform=macOS'`。
- [x] 运行 `git diff --check`。
- [x] 总结根因、修复、验证结果，并等待用户本地测试后再 push。
