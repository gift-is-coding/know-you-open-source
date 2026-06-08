# DMG 安装页与 MyWiki LLM 修复设计

## 背景

本次修复在独立 worktree `/Users/wutianfu/Documents/code/know-you/.worktrees/fix-dmg-mywiki-llm` 和分支 `codex/fix-dmg-mywiki-llm` 上进行。当前主 checkout 有未提交改动，本分支从 `origin/main` 新建，避免影响用户现有工作。

## 已确认问题

1. DMG 拖拽安装页的主要问题是错位，不是单纯模糊。继续依赖 Applications alias、箭头和两个 Finder icon 坐标会让安装页反复不稳定。
2. MyWiki LLM 对普通用户不可用的根因不是“用户 PATH 没 npm”这么小，而是用户可点击的 app 产物里没有稳定内置 MyWikiRunner 时，Swift bridge 只能失败或回退到开发者形态；普通用户没有源码、node_modules、Node/npm。
3. MyWiki 必须复用 KnowYou 已配置的 Diary Engine。内置 runner 只承载 llm_wiki 原生 ingest；LLM request 通过 `knowyou-bridge` 回到 Swift summarizer，而不是让用户重新配置 API。

## 目标

- DMG 不再依赖 Applications alias 和箭头坐标；背景只提示双击 app 安装，app 自己复制到 Applications 并重启。
- DMG 背景输出 `1120x600` pixels，同时保持 `560x300` point 布局。
- MyWiki ingest 使用 app 内置 `Contents/Resources/MyWikiRunner`，并通过 My Wiki Diary Engine bridge 复用 KnowYou 已保存的 LLM engine。
- Release、New User QA、dev launch 和 DMG 打包链路都必须保证 MyWikiRunner 被 embed；缺失时打包失败。
- 保留失败状态写入，不把 LLM pipeline 失败伪装成本地 fallback 成功。

## 非目标

- 不重写 MyWiki 的 LLM 语义 pipeline。
- 不清空用户的 MyWiki、UserDefaults、Keychain、TCC 或 app container。
- 本分支不发布远端 release、不 push。
- 不发布远端 release、不 push。

## 实现设计

### DMG

`scripts/build-dmg.sh` 的 Swift 背景生成器只保留居中的 app icon 位置和 “Double-click KnowYou to install” 文案。DMG 内不再创建 Applications alias，也不再设置 Applications icon 坐标。脚本在打包前验证 app 内存在 `Contents/Resources/MyWikiRunner/node` 和 `mywiki-runner.js`。

同时保留 Retina-safe bitmap：`pixelsWide = width * 2`、`pixelsHigh = height * 2`，并设置 `bitmap.size` 为 point 尺寸。

`scripts/test-build-dmg-layout.sh` 断言背景 generator 中存在这些 layout constants，并继续验证输出 PNG 是 `1120x600` pixels。

### MyWiki

`MyWikiPipelineBridge` 在 `.bundledRunner` 目标下启动 `Contents/Resources/MyWikiRunner/node mywiki-runner.js --provider knowyou-bridge`。runner 输出 JSONL `llm.request` 时，Swift 侧 `MyWikiLLMBridge` 交给当前 diary summarizer 完成，并把 response/error 写回 runner stdin。API key 不出现在 runner 命令行。

删除运行时 `developmentSource`/npm fallback。MyWiki 产品路径只接受 bundled runner；开发和发布构建仍可在 build step 使用 npm 来生成 `MyWikiRunner`，但用户点击 Update/Generate 时不会调用 npm。

## 测试

- `scripts/test-build-dmg-layout.sh`
- `scripts/test-release-common.sh`
- `scripts/test-mywiki-runner-package.sh`
- `xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/MyWikiPipelineBridgeTests`
- `npx vitest run src/headless/knowyou-ingest.test.ts`
- `scripts/verify-mywiki-real-diary.sh`
- 完整验证按仓库标准执行：`xcodebuild test -scheme KnowYou -destination 'platform=macOS'`、`xcodebuild build -scheme KnowYou -destination 'platform=macOS'`、`git diff --check`
