# 06 - Engine Selector, Settings, And Status

## Goal

Protect the engine/status experience: users should understand whether capture, notifications, and diary engines are ready, configure providers safely, and recover from unavailable engines without blocking local reading.

## Environment

- Type: `app-clean`
- Data: completed onboarding, deterministic engine status fixtures, no real API tokens
- Isolation: use a regression Keychain service and deterministic engine fixtures; do not read or write real LLM API tokens

## Steps

1. Launch KnowYou with completed onboarding.
2. Open the top-right diary engine selector.
3. Verify rows exist for supported engines: LLM API, Codex Auth, Claude Code CLI, Codex CLI, Gemini CLI, and Openclaw CLI.
4. Verify unavailable engines explain why they cannot become default.
5. Open the LLM API configuration sheet.
6. Verify provider choices include OpenAI, Anthropic, DeepSeek, OpenRouter, Gemini, Qwen, Kimi, Zhipu, and custom OpenAI-compatible.
7. Verify base URL, model, wire format, token, help links, save, set active, and test provider controls are reachable.
8. Close without saving secrets.
9. Open Settings.
10. Verify service status details for clipboard, notification database, day refresh, summarizer, and engine readiness.
11. Verify vault path controls are visible.
12. Verify Full Disk Access, notification settings, community/support/docs, and legal/privacy links are reachable without blocking the main app.

## Assertions

- The engine selector remains in the global toolbar across My Diary, Other Source, and My Wiki.
- Selecting an unavailable engine is prevented or explained.
- API tokens are never written in automated regression fixtures.
- Status rows explain degraded states instead of hiding them.
- Leaving default engine disabled still allows local reading of existing seeded stories.
- Settings does not delete or reset user state during verification.

## Automation

- Level: `pre-push` for selector/settings reachability and no-secret config checks
- Level: `nightly` for engine retest behavior with stubbed process/network responses
- Codex Skill case id: `engine-settings-status`
- Use Codex GUI / ComputerUser for engine selector, provider sheet, Settings, and degraded-status inspection.

## Update Triggers

- Diary engine list changes
- Provider list, provider defaults, or wire format changes
- Codex Auth storage changes
- Settings status copy or permission links change
- Toolbar placement changes
