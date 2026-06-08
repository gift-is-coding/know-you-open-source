# DMG 安装页与 MyWiki LLM 修复实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复 DMG 安装页不稳定问题，并让普通用户安装后的 MyWiki 通过 app 内置 runner 复用 KnowYou Diary Engine，不依赖用户机器上的 npm。

**Architecture:** DMG 只保留双击 app 安装的最小 Finder 页面；交互式 app 启动负责自移动到 Applications。MyWiki 侧用共享脚本把 bundled Node + headless runner embed 到 app，Swift bridge 通过 `knowyou-bridge` 复用 Diary Engine，不改变 llm_wiki 的语义 pipeline、source catalog 或 fallback 语义。

**Tech Stack:** Bash, Swift/AppKit background generator, XCTest, Vitest, macOS `sips`, MyWiki Swift bridge, llm_wiki TypeScript headless runner.

---

### Task 1: DMG 自移动安装测试与修复

**Files:**
- Modify: `scripts/test-build-dmg-layout.sh`
- Modify: `scripts/build-dmg.sh`

- [x] 在 `scripts/test-build-dmg-layout.sh` 写失败测试：断言背景文案为双击安装、app icon 居中、脚本不再创建或定位 Applications alias。
- [x] 运行 `scripts/test-build-dmg-layout.sh`，确认当前失败在旧拖拽文案。
- [x] 修改 `scripts/build-dmg.sh`：移除 Applications alias/箭头，保留 Retina-safe bitmap，并在打包前验证 MyWikiRunner。
- [x] 生成修复后背景图，确认 DMG 页面不再依赖两个 icon 对齐。
- [x] 重新运行 `scripts/test-build-dmg-layout.sh`，确认通过。

### Task 2: MyWiki Runner 产品化打包与 Diary Engine bridge

**Files:**
- Modify: `KnowYouTests/MyWikiPipelineBridgeTests.swift`
- Modify: `KnowYou/Services/MyWiki/MyWikiPipelineBridge.swift`
- Create: `scripts/embed-mywiki-runner.sh`
- Modify: `scripts/build-release.sh`
- Modify: `scripts/install-new-user-app.sh`
- Modify: `scripts/run-dev-app.sh`
- Modify: `scripts/test-release-common.sh`
- Modify: `ThirdParty/llm_wiki/src/headless/knowyou-ingest.ts`
- Modify: `ThirdParty/llm_wiki/src/headless/knowyou-ingest.test.ts`

- [x] 写桥接调用测试：bundled runner 只通过 `knowyou-bridge` 调当前 Diary engine，不在运行时传 API key/npm/development source。
- [x] 删除运行时 `developmentSource`/npm fallback 与 `MyWikiLLMInvocation`。
- [x] 运行 focused XCTest，确认 bundled runner bridge 新链路通过。
- [x] 写失败测试：Release、New User QA、dev launch 和 DMG 打包都必须 embed 或验证 MyWikiRunner。
- [x] 新增 `scripts/embed-mywiki-runner.sh`，集中构建并复制 `build/MyWikiRunner` 到 app resources。
- [x] 修改 release / New User / dev launch 脚本，确保用户可点击 app 内含 MyWikiRunner。
- [x] 验证 runner package 不包含 `node_modules`、`LLM Wiki.app` 或运行时 npm 文本。
- [x] 添加 Vitest 覆盖 runner 读取 KnowYou LLM API 参数。
- [x] 重新运行 focused XCTest 和 Vitest。

### Task 3: 验证与交付

**Files:**
- Review: all changed files

- [x] 运行 `scripts/test-build-dmg-layout.sh`。
- [x] 运行 `scripts/test-release-common.sh`。
- [x] 运行 `scripts/test-mywiki-runner-package.sh`。
- [x] 运行 `xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/MyWikiPipelineBridgeTests`。
- [x] 运行 `npx vitest run src/headless/knowyou-ingest.test.ts`。
- [x] 运行 `scripts/verify-mywiki-real-diary.sh`。
- [x] 运行完整 `xcodebuild test -scheme KnowYou -destination 'platform=macOS'`。
- [x] 运行完整 `xcodebuild build -scheme KnowYou -destination 'platform=macOS'`。
- [x] 运行 `git diff --check`。
- [x] 总结根因、修复、验证结果，并等待用户本地测试后再 push。
