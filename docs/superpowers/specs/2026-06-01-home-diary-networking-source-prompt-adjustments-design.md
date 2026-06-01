# Home、Diary、Networking 与 Add Source Prompt 调整设计

## 背景

这轮调整延续 `codex/home-networking-bootstrap` 分支，目标是把新 Home 和 Networking preview 从“能看”推进到“用户一眼能懂”，同时修正老用户三天补生成和 Add Source prompt 的引导细节。

## 用户体验

- 左侧 Diary 列表只展示 `Today + last 3 days`，避免旧内容把入口撑成 7 天或更多。
- Home 不显示倒计时，改为 `Automatic Diary update` 加下一次自动检查的本地时间。
- Home 提供 `Generate Now`，只更新今天；`Generate Last 3 Days` 只在昨天到前三天缺少 model diary 时出现。
- Home 下方入口单列展示，顺序为 `Networking (Coming soon)`、`Todo`、`My Wiki`、`Today’s Diary`、`Other Source`，每项用短但完整的人话解释用途。
- Networking 在侧边栏和页面标题中都标记为 `Networking (Coming soon)`，页面显示 `Coming soon`，并移除 `Clear identity` / `identity stays clear` 表述。
- Other Source root 不再显示右侧 `+`，点击 root 仍进入来源管理页。
- Generate Prompt 弹窗标题改为 `Generate Prompt and Run in Codex/Claude to Set Up`。复制后弹出视觉引导，说明去 Codex 或 Claude Code 粘贴运行并完成授权。

## 行为边界

- “过去三天”定义为 yesterday、2 days ago、3 days ago，不包含 today。
- Onboarding 和老用户恢复共用同一套三天补生成队列，只排缺失日期，已有 model diary 跳过。
- KnowYou 不保存 Feishu、Notion、Google Drive 的远程凭据；prompt 必须要求外部自动化环境检查、安装并授权所需 CLI、MCP 或本地工具。

## 验收标准

- Sidebar root 顺序保持 `Home`、`Networking (Coming soon)`、`Todo`、`My Wiki`、`My Diary`、`Other Source`，已添加的 Feishu/Lark、Notion、Google Drive 等来源排在 `Other Source` 后面。
- Diary 列表窗口最多只含 today 加前三天，demo day 仍按 onboarding 规则附加。
- Home copy 为英文，包含本地自动更新时间、`Generate Now`、条件化的 `Generate Last 3 Days` 和单列功能入口。
- Networking preview 不再包含 clear identity 相关 copy 或图片文字。
- Copy Prompt 后出现 `ExternalPromptRunGuide` 引导图。
