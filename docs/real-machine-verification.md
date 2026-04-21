# Real-Machine Verification Harness

This repository includes a real-machine shell harness for checking KnowYou on a real Mac with actual clipboard and local notification inputs.

## What It Does

The harness:

- quits an already running KnowYou instance so launch-time automation starts from a clean state
- copies a unique clipboard sentinel with `pbcopy`
- attempts a real local macOS notification with a unique sentinel via `osascript`
- launches the latest Debug build of KnowYou if it can find one in DerivedData
- waits for launch-time clipboard bootstrap plus launch-time automation to refresh today
- automatically checks SQLite and today's Markdown for the clipboard sentinel
- reports whether the local Notification Center database is missing, readable, or blocked by Full Disk Access
- prints exact follow-up commands for deeper SQLite and Markdown inspection

Run it from the repo root:

```bash
./scripts/verify-real-machine.sh
```

## Expected Paths

The app currently uses:

- `~/Library/Application Support/KnowYou/events.sqlite`
- `~/Library/Application Support/KnowYou/Vault`

## What Counts As Verified

On a machine where the app can be launched from DerivedData, the harness should automatically verify:

- real clipboard -> SQLite
- SQLite -> today's Markdown through launch-time automation

Notification persistence remains machine-dependent. The script reports whether a notification row appeared in SQLite, but that is not guaranteed on every macOS build.

If the script reports `permission-denied` for the Notification Center database, the notification path is blocked before KnowYou can import anything. In that case:

1. grant Full Disk Access to KnowYou or the terminal app running the harness
2. rerun the script
3. only treat notification import as testable once the database is reported as `readable`

## Why The Ordering Matters

KnowYou now bootstraps the current clipboard contents during app startup before the first automation refresh runs. The harness depends on that ordering:

1. quit any old app instance
2. write the real clipboard sentinel
3. launch the app
4. let startup capture and generation run

That removes the earlier race where today's Markdown could be generated before the new clipboard item had reached SQLite.

## Follow-Up Commands

The script prints exact commands, but the core checks are:

```bash
sqlite3 "$HOME/Library/Application Support/KnowYou/events.sqlite" \
  "SELECT id, sourceType, sourceApp, dayKey, capturedAt, text, auditText, privacyAction, contentHash FROM events;"
```

```bash
grep -n "YOUR-VERIFY-ID" "$HOME/Library/Application Support/KnowYou/Vault/YYYY-MM-DD.md"
```

## Notification Caveat

On current macOS releases, `osascript -e 'display notification ...'` is not always a reliable persistence test for the local notification store.

If the notification banner appears but the sentinel does not show up in SQLite, use the same printed notification command again while the session is unlocked and notifications are allowed for the source app. If that still does not persist, accept clipboard + Markdown as the reproducible end-to-end verification on that machine and treat notification persistence as a machine-dependent manual check.
