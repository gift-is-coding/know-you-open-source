# Onboarding 3 天 Bootstrap 收敛设计

## 目标

首次 onboarding 后只生成最近 3 天日记：今天、昨天、前天。这个范围更符合 macOS Notification Center 作为“可用本地历史”而非长期归档的现实，避免让用户误以为 KnowYou 一定能恢复 7 天或更早的通知。

## 行为

- 确认弹窗、generating step、主窗口 notice 与完成通知统一使用 `first 3 days`。
- 主窗口 notice 文案必须包含 `available local history`，强调内容来自当前 Mac 上仍可用的本地历史。
- bootstrap day keys 固定为当前日期向前 3 个自然日，并继续跳过已有成功日记。
- 生成仍按天串行执行；某一天失败时继续后续日期。
- 单日超过 50 个事件时继续沿用现有 chunked full recovery：首批 50 条 full recovery，后续每批最多 50 条 incremental append。

## 验收标准

- onboarding progress、content、layout、notice 与 main-window bootstrap 测试均断言 3 天语义。
- requirements 与 architecture 不再承诺 7 天历史生成。
- New User 测试包仍只作为本机 QA flavor，验证 3 天新用户 bootstrap，不影响普通 `KnowYou.app`。
