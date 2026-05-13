# AGENTS.md

## Superpower Workflow

This repository uses Superpower workflows as the default development process.

For any feature, bugfix, refactor, or behavior change, the agent must follow this order unless the user explicitly says otherwise:

1. `using-superpowers`
2. `brainstorming`
3. `writing-plans` for multi-step work
4. `test-driven-development` before production code changes
5. `verification-before-completion` before claiming success

Simple one-off tasks do not require the Superpower workflow. This includes requests such as:

- generating or updating demo/sample data
- small content edits
- local documentation wording tweaks
- lightweight inspection or explanation tasks

When a task stays in that lightweight bucket and does not change product behavior, the agent may execute it directly without the Superpower sequence.

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
- When launching the app after a build, inspect the current session's DerivedData output, use only the freshly built `KnowYou.app`, and delete stale historical `KnowYou.app` build artifacts so verification never points at an old binary and disk usage stays bounded.
- During GUI verification, do not clear or reset the dev bundle's persisted onboarding, auth, engine, or login state unless the test explicitly requires it. If a repro requires changing `dev.knowyou.app` UserDefaults or auth state, restore the prior completed/configured state before handing the app back to the user.

Do not claim a feature is complete, fixed, or passing without fresh command output from the current session.

## Git Push Policy

- Do not automatically push changes to the remote.
- After local implementation, testing, and commit, stop and let the user test first.
- Push only after the user explicitly confirms that the local result is ready to publish.

## Notes

- User instructions override this file.
- If the task is too small to justify a spec/plan, the agent should say so explicitly.
- For any large PR or significant product/code change, the agent must review and update `docs/architecture.md` and `docs/requirements-spec.md` before completion or push.
