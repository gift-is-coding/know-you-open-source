# AGENTS.md

## Superpower Workflow

This repository uses Superpower workflows as the default development process.

For any feature, bugfix, refactor, or behavior change, the agent must follow this order unless the user explicitly says otherwise:

1. `using-superpowers`
2. `brainstorming`
3. `writing-plans` for multi-step work
4. `test-driven-development` before production code changes
5. `verification-before-completion` before claiming success

## Required Outputs

For substantial product work, the agent must keep `docs/superpowers/` in sync with implementation:

- Save specs to `docs/superpowers/specs/YYYY-MM-DD-<feature-name>.md`
- Save plans to `docs/superpowers/plans/YYYY-MM-DD-<feature-name>.md`

If code is implemented without the corresponding spec/plan artifact, the task is not considered complete.

## Testing Standard

For any non-trivial change:

- Add or update focused tests first
- Run the targeted test slice during implementation
- Run full verification before completion:
  - `xcodebuild test -scheme KnowYou -destination 'platform=macOS'`
  - `xcodebuild build -scheme KnowYou -destination 'platform=macOS'`

Do not claim a feature is complete, fixed, or passing without fresh command output from the current session.

## Notes

- User instructions override this file.
- If the task is too small to justify a spec/plan, the agent should say so explicitly.
