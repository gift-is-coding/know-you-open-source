# Onboarding 3 天 Bootstrap 收敛计划

## Summary

- 将首次 onboarding bootstrap 从 7 天收敛为最近 3 天，包含今天、昨天、前天。
- 用户文案改为从 `available local history` 生成，避免暗示 macOS Notification Center 一定保留更早历史。
- 保留本地隐私承诺、串行生成、跳过已有日记、失败继续与 50 条 chunking 策略。

## Key Changes

- `AppState` 的 onboarding bootstrap day keys 改为 3 天，notice 与完成通知改为 `first 3 days`。
- `OnboardingContent`、`OnboardingView`、`OnboardingBootstrapNoticePresentation` 的用户可见文案同步为 3 天。
- `OnboardingProgressTests`、`OnboardingContentTests`、`OnboardingViewLayoutTests`、`OnboardingBootstrapNoticeTests`、`MainWindowViewModelTests` 全部改为 3 天期望。
- `docs/requirements-spec.md`、`docs/architecture.md` 与相关 superpowers 文档同步更新。

## Test Plan

- 先运行 focused onboarding/bootstrap tests，确认 3 天语义通过。
- 再运行 `xcodebuild test -scheme KnowYou -destination 'platform=macOS'`。
- 最后运行 `xcodebuild build -scheme KnowYou -destination 'platform=macOS'`。
