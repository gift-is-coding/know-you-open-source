# 08 - Real Clipboard And Notification Pipeline Smoke

## Goal

Protect the real-machine data path from input signal to persisted event to generated Markdown. This case complements Codex GUI regression because macOS clipboard and Notification Center behavior cannot be fully represented by an isolated app-clean profile.

## Environment

- Type: `real-machine`
- Data: unique sentinel strings generated per run
- Existing harness: `scripts/verify-real-machine.sh`
- Boundary: validates this Mac's real clipboard/notification data pipeline only. It does not prove first-user permission freshness because this macOS user may already have granted TCC permissions to the same bundle id.

## Steps

1. Quit any running KnowYou process from the current build.
2. Copy a unique clipboard sentinel with `pbcopy`.
3. Attempt to display a local macOS notification with a unique notification sentinel.
4. Launch the freshly built KnowYou app.
5. Wait for launch-time clipboard bootstrap and launch-time automation.
6. Query SQLite for the clipboard sentinel.
7. Query today's Markdown for the clipboard sentinel.
8. Query SQLite for the notification sentinel when the Notification Center database is readable.
9. Report Notification Center database path and access status.

## Assertions

- Clipboard sentinel appears in the KnowYou SQLite event store.
- Clipboard sentinel appears in today's Markdown after refresh.
- Notification sentinel is either imported or the report clearly explains why the Notification Center database is missing, unreadable, or machine-dependent.
- Notification import failure does not block clipboard capture or Markdown generation.
- The harness prints exact follow-up SQLite and grep commands.
- Passing this smoke must not be described as proof of true-clean onboarding or fresh Full Disk Access behavior.

## Automation

- Level: `manual-release`
- Recommended command: `./scripts/verify-real-machine.sh`
- Codex Skill case id: `real-pipeline-smoke`
- Recommended command evidence: `./scripts/verify-real-machine.sh`

## Update Triggers

- Clipboard watcher timing changes
- Notification database reader paths or schema handling changes
- Privacy filter changes
- Database schema or Markdown composer changes
- Launch-time automation order changes
