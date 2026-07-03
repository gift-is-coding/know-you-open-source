# Regression Coverage Matrix

| Product Area | Test Case | Environment | Level | Primary Artifact |
| --- | --- | --- | --- | --- |
| First-run onboarding | [01-first-run-onboarding.md](test-cases/01-first-run-onboarding.md) | permission-clean + true-clean | pre-push + manual-release | UI screenshot sequence, onboarding defaults, permission diagnosis |
| My Diary reader | [02-my-diary-reader-refresh.md](test-cases/02-my-diary-reader-refresh.md) | app-clean | pre-push | `.story.json`, `.md`, UI source detail |
| Todo inbox | [03-todo-inbox.md](test-cases/03-todo-inbox.md) | app-clean | pre-push | `Vault/Todo.md` |
| Other Source | [04-other-source-connectors.md](test-cases/04-other-source-connectors.md) | app-clean | pre-push | knowledge source index, source preview |
| My Wiki | [05-my-wiki-source-library-agent.md](test-cases/05-my-wiki-source-library-agent.md) | app-clean | pre-push + nightly | My Wiki files, Source Library state |
| Diary engines | [06-engine-settings-status.md](test-cases/06-engine-settings-status.md) | app-clean | pre-push + nightly | engine status rows, config defaults |
| Settings, reminders, updates | [07-settings-sync-reminder-update.md](test-cases/07-settings-sync-reminder-update.md) | app-clean + true-clean | nightly + manual-release | UserDefaults, LaunchAgent dry-run evidence |
| Networking | [10-networking-agent-platform.md](test-cases/10-networking-agent-platform.md) | app-clean + browser E2E | pre-push + nightly | profile draft state, public square transcript, agent API review |
| Clipboard and notification pipeline | [08-real-pipeline-smoke.md](test-cases/08-real-pipeline-smoke.md) | real-machine | manual-release | SQLite rows, Markdown sentinel |
| Release gate | [09-release-gate.md](test-cases/09-release-gate.md) | true-clean + real-machine | manual-release | build, test, signing, notarization logs |

## Required Pre-Push Set

The default pre-push gate should cover:

1. First-run onboarding correctly shows missing-permission guidance under the installed `dev.knowyou.newuser` New User app.
2. My Diary loads seeded days, supports paragraph selection, and shows source detail.
3. Refresh actions do not affect the wrong date or leave the UI permanently busy.
4. Todo supports manual add, candidate promotion, and completion persistence.
5. Other Source and My Wiki core surfaces are reachable without modal blockers.
6. Engine selector and Settings status surfaces remain reachable and understandable.
7. Networking opens as a native App surface, shows generated/approved profile states, and Web agent APIs pass browser E2E.

## Manual Release Set

Before publishing a signed build, additionally run:

1. Real clipboard sentinel into SQLite and Markdown.
2. Notification access diagnosis on the current Mac.
3. Release build, notarization, DMG packaging, and Gatekeeper verification.
4. A true-clean first-user pass in a separate macOS user or VM/snapshot.
5. A Codex-guided or human click pass for OS-controlled dialogs such as Full Disk Access, notification permission, Finder reveal, and external agent setup.
