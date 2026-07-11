---
name: knowyou-networking-production-review
description: >
  Use after implementing or modifying KnowYou Networking App/Web/platform code when the work needs a production-readiness gate: deterministic Web and macOS verification, fresh local preview/app launch checks, Claude Code review, and benchmarks/test cases for code functionality, App UX, Web UX, handoff, MCP/security, and production integration.
---

# KnowYou Networking Production Review

Run this skill before claiming a Networking feature/fix is production-ready, before committing a substantial Networking diff, or whenever the user asks for a Claude review pipeline focused on real App/Web experience.

## Workflow

1. Confirm the exact checkout first:

```bash
git status --short --branch
git log --oneline -2
```

2. Run the production review pipeline from the repo root:

```bash
.agents/skills/knowyou-networking-production-review/scripts/run_pipeline.sh
```

The script writes a review packet under `docs/reviews/networking-production-review/YYYYMMDD-HHMMSS/` with command logs, local preview evidence, fresh app metadata, Claude output, failures, and follow-up benchmarks.

## Options

- `--skip-full-xcode-test`: only use when the full suite is already known to be blocked or too slow for the current turn. Report it as a waiver.
- `--skip-launch`: skip opening the fresh macOS app, but still build and capture the app path/metadata.
- `--skip-claude`: use only when Claude CLI auth or budget is blocked. Treat this as a review blocker, not as success.
- `--keep-server`: leave `NetworkingWeb` running after the review so the user can inspect `http://127.0.0.1:<port>/?platform=knowyou-friends`.
- `--dry-run`: validate the pipeline shape without executing expensive commands.

## Pass Criteria

Call the work ready only when the report result is `PASS` and the Claude review artifact exists, unless the user explicitly accepted a skipped Claude review. A failed Claude auth call, CSS chunk failure, stale app metadata failure, localhost production fallback failure, or timed-out full `xcodebuild test` is a blocker.

## Benchmarks

Every review should cover:

- Code functionality: Web tests/lint/typecheck/build, targeted Networking Swift tests, full macOS test/build when feasible.
- App UX: stale activation migration, three-step cockpit guidance, Open Square inline errors, fresh app launch from the current worktree.
- Web UX: signed-out no-composer guidance, viewer-scoped profile rail, handoff sign-in, first CSS chunk health.
- Production integration: no non-DEBUG localhost token handoff, no plaintext MCP token output, platform queue shape, Supabase viewer scoping.

Never hide skipped gates. If the pipeline cannot complete, return the exact failing gate and the report path.
