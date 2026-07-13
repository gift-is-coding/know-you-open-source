# 日记脱敏分享实现计划

**目标：** 增加一个本地优先的日记分享流程，把全文、划选文本或段落回退内容生成默认脱敏的分享图片，并在图片中包含 KnowYou 下载地址和二维码。

**实现策略：** 分享只使用当前 `DailyStory` / `DailyStoryParagraph` 的可读文本，不读取原始 SQLite 事件，不上传分享内容。为了避免 Xcode project 文件膨胀，本次把轻量分享 helper 放入现有 target 文件中，而不是新增 service 文件。

## 已完成任务

- [x] 建立独立 worktree 和分支：`.worktrees/diary-share` / `codex/diary-redacted-share`
- [x] 编写设计规格：`docs/superpowers/specs/2026-06-12-diary-redacted-share-design.md`
- [x] 先写失败测试，再实现分享内容构建与脱敏逻辑
- [x] 在日记顶部增加 `脱敏分享` / `Share Redacted` 入口
- [x] 展开分享面板，默认勾选脱敏，并支持切换到非脱敏分享
- [x] 支持复制 PNG 图片到剪贴板
- [x] 支持保存 PNG 图片到本地
- [x] 在段落右键菜单中增加脱敏分享和非脱敏分享，优先使用当前划选文本
- [x] 生成 900x1200 分享卡片，包含日记内容、KnowYou 来源、下载 URL 和二维码
- [x] 更新 `docs/architecture.md` 和 `docs/requirements-spec.md`
- [x] 运行 targeted tests、完整 test 和 build 验证

## 实际修改文件

- `KnowYou/Services/Privacy/PrivacyFilter.swift`
  - 新增 `DiarySharePayload`、`DiaryShareMode`、`DiaryShareSource`
  - 新增 `DiaryShareContentBuilder` 和展示层 `DiaryShareRedactor`
- `KnowYou/UI/Reader/DailyMarkdownView.swift`
  - 新增分享入口、checkbox、复制/保存动作、段落右键菜单
  - 新增 `DiaryShareSelectedTextResolver`，右键分享优先使用属于当前段落的 AppKit selection，无法取得时回退整段
  - 新增分享图片 renderer、QR 生成、剪贴板 writer、文件名 helper
- `KnowYou/UI/MainWindowView.swift`
  - 接入全文和段落分享 callback
  - 接入剪贴板写入、保存面板和状态消息
- `KnowYouTests/PrivacyFilterTests.swift`
  - 覆盖全文/段落 payload、脱敏规则、非脱敏保持原文
- `KnowYouTests/DailyMarkdownViewTests.swift`
  - 覆盖分享 presentation、selection resolver、QR 生成、PNG 渲染、剪贴板和文件名
- `docs/architecture.md`
  - 补充 Diary Share 架构说明
- `docs/requirements-spec.md`
  - 补充分享用户场景、隐私边界和功能要求

## 验证记录

- [x] `xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/PrivacyFilterTests`
- [x] `xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/DailyMarkdownViewTests`
- [x] `xcodebuild test -scheme KnowYou -destination 'platform=macOS'`
- [x] `xcodebuild build -scheme KnowYou -destination 'platform=macOS'`

完整测试结果包：`Test-KnowYou-2026.06.12_23-32-02-+0800.xcresult`，状态 `succeeded`，测试数 `809`。

## V1 边界

- 划选分享通过当前窗口的 AppKit text selection 解析，并校验 selection 属于当前段落；如果系统没有提供稳定 selection，则回退分享当前段落。
- 脱敏是保守展示层处理，降低误分享风险，但不承诺覆盖所有个人身份信息。
- 本次不做短链、点击统计、社交平台发布或归因分析。
