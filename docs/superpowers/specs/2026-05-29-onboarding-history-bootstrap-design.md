# Onboarding 3 天历史生成设计

## 目标

首次 onboarding 完成前，明确告诉用户 KnowYou 会在本机生成最近 3 天日记，过程可能需要几分钟，并强调数据不上传 KnowYou 后端。用户确认后，系统串行生成 3 个自然日，并在主界面展示按天进度。

## 用户体验

- generating 步骤在权限和 diary engine 都 ready 后弹出确认框。
- 确认框文案强调：**KnowYou** 只从当前 Mac 的本地上下文生成，All local. No backend server.
- 用户点击开始后才进入主界面并触发 bootstrap。
- 主窗口顶部 notice 显示首次 3 天生成说明与当前按天进度。
- 左侧 My Diary 展示 3 天占位日期；未生成完成的日期正文为空态 `Generating your diary...`。

## 行为规则

- “最近 3 天”包含今天，共 3 个自然日。
- 文案只承诺从可用本地历史生成，不暗示 macOS 一定保留更早 Notification Center 记录。
- 已有成功日记的日期视为完成并跳过，不重复生成。
- 日期按从新到旧串行处理。
- 单日超过 50 个事件时沿用现有 chunked onboarding bootstrap 策略。
- 任意日期失败后继续处理后续日期；部分 chunk 成功不回滚，但该日期不计入成功完成通知。
- bootstrap 只在首次 onboarding 后执行一次，完成后后续启动不再 requeue。

## 验收标准

- onboarding bootstrap day keys 为今天起倒推 3 天。
- 确认框与 generating/onboarding 文案包含本地隐私承诺。
- notice 能展示总数、已完成数和当前日期。
- 完成通知适配 3 天。
- requirements 与 architecture 文档同步更新。
