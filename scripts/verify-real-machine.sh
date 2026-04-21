#!/usr/bin/env bash
set -euo pipefail

APP_SUPPORT_DIR="$HOME/Library/Application Support/KnowYou"
DATABASE_PATH="$APP_SUPPORT_DIR/events.sqlite"
VAULT_PATH="$APP_SUPPORT_DIR/Vault"
DAY_KEY="$(date +%F)"
VERIFY_ID="knowyou-verify-$(date +%Y%m%dT%H%M%S)-$(uuidgen | tr '[:upper:]' '[:lower:]')"
CLIPBOARD_SENTINEL="KnowYou clipboard sentinel: $VERIFY_ID"
NOTIFICATION_SENTINEL="KnowYou notification sentinel: $VERIFY_ID"
NOTE_PATH="$VAULT_PATH/$DAY_KEY.md"
APP_PATH="$(find "$HOME/Library/Developer/Xcode/DerivedData" -path '*Build/Products/Debug/KnowYou.app' | head -n 1 || true)"
NOTIFICATION_DB_PATH=""
NOTIFICATION_DB_ACCESS="missing"

for candidate in \
  "$HOME/Library/Group Containers/group.com.apple.usernoted/db2/db" \
  "$HOME/Library/Group Containers/group.com.apple.usernoted/db/db" \
  "$HOME/Library/Application Support/NotificationCenter/db2/db" \
  "$HOME/Library/Application Support/NotificationCenter/db/db"
do
  if [[ -e "$candidate" ]]; then
    NOTIFICATION_DB_PATH="$candidate"
    if [[ -r "$candidate" ]]; then
      NOTIFICATION_DB_ACCESS="readable"
    else
      NOTIFICATION_DB_ACCESS="permission-denied"
    fi
    break
  fi
done

escape_applescript() {
  local value=$1
  value=${value//\\/\\\\}
  value=${value//\"/\\\"}
  printf '%s' "$value"
}

if pgrep -x "KnowYou" >/dev/null 2>&1; then
  osascript -e 'tell application id "dev.knowyou.app" to quit' >/dev/null 2>&1 || true
  pkill -x "KnowYou" >/dev/null 2>&1 || true
  for _ in 1 2 3 4 5; do
    pgrep -x "KnowYou" >/dev/null 2>&1 || break
    sleep 1
  done
fi

printf '%s' "$CLIPBOARD_SENTINEL" | pbcopy

if osascript <<OSA
display notification "$(escape_applescript "$NOTIFICATION_SENTINEL")" with title "KnowYou verification" subtitle "$(escape_applescript "$DAY_KEY")"
OSA
then
  NOTIFICATION_STATUS="requested"
else
  NOTIFICATION_STATUS="failed"
fi

if [[ -n "$APP_PATH" ]]; then
  open -a "$APP_PATH"
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    if pgrep -x "KnowYou" >/dev/null 2>&1; then
      APP_LAUNCH_STATUS="launched"
      break
    fi
    sleep 1
  done
  APP_LAUNCH_STATUS="${APP_LAUNCH_STATUS:-launch-timeout}"
else
  APP_LAUNCH_STATUS="missing-build"
fi

CLIPBOARD_SQL=""
for _ in 1 2 3 4 5 6 7 8 9 10; do
  CLIPBOARD_SQL="$(sqlite3 "$DATABASE_PATH" "SELECT sourceType || '|' || sourceApp || '|' || capturedAt FROM events WHERE dayKey = '$DAY_KEY' AND (text LIKE '%$VERIFY_ID%' OR auditText LIKE '%$VERIFY_ID%') ORDER BY capturedAt DESC LIMIT 1;" 2>/dev/null || true)"
  [[ -n "$CLIPBOARD_SQL" ]] && break
  sleep 1
done

NOTIFICATION_SQL=""
for _ in 1 2 3 4 5; do
  NOTIFICATION_SQL="$(sqlite3 "$DATABASE_PATH" "SELECT sourceType || '|' || sourceApp || '|' || capturedAt FROM events WHERE dayKey = '$DAY_KEY' AND (text LIKE '%$NOTIFICATION_SENTINEL%' OR auditText LIKE '%$NOTIFICATION_SENTINEL%') ORDER BY capturedAt DESC LIMIT 1;" 2>/dev/null || true)"
  [[ -n "$NOTIFICATION_SQL" ]] && break
  sleep 1
done

MARKDOWN_MATCH=""
for _ in 1 2 3 4 5 6 7 8 9 10; do
  MARKDOWN_MATCH="$(grep -n "$VERIFY_ID" "$NOTE_PATH" 2>/dev/null || true)"
  [[ -n "$MARKDOWN_MATCH" ]] && break
  sleep 2
done

printf '\nKnowYou real-machine verification\n'
printf -- '---------------------------------\n'
printf 'Verification ID: %s\n' "$VERIFY_ID"
printf 'Clipboard sentinel copied via pbcopy: %s\n' "$CLIPBOARD_SENTINEL"
printf 'Notification status: %s\n' "$NOTIFICATION_STATUS"
printf 'Notification sentinel: %s\n' "$NOTIFICATION_SENTINEL"
printf 'App launch status: %s\n' "$APP_LAUNCH_STATUS"
printf '\nApp Support locations\n'
printf '  Database: %s\n' "$DATABASE_PATH"
printf '  Vault:    %s\n' "$VAULT_PATH"
if [[ -n "$APP_PATH" ]]; then
  printf '  App:      %s\n' "$APP_PATH"
fi
if [[ -n "$NOTIFICATION_DB_PATH" ]]; then
  printf '  Notification DB: %s (%s)\n' "$NOTIFICATION_DB_PATH" "$NOTIFICATION_DB_ACCESS"
else
  printf '  Notification DB: not found\n'
fi

printf '\nAutomatic checks\n'
printf '  Clipboard in SQLite: %s\n' "${CLIPBOARD_SQL:-missing}"
printf '  Clipboard in Markdown: %s\n' "${MARKDOWN_MATCH:-missing}"
printf '  Notification in SQLite: %s\n' "${NOTIFICATION_SQL:-missing}"

if [[ "$NOTIFICATION_DB_ACCESS" == "permission-denied" ]]; then
  printf '\nNotification diagnosis\n'
  printf '  The Notification Center database exists but this process cannot read it.\n'
  printf '  Grant Full Disk Access to KnowYou or to the terminal app running this script, then rerun.\n'
fi

printf '\nFollow-up SQLite check\n'
printf '  sqlite3 "%s" "SELECT id, sourceType, sourceApp, dayKey, capturedAt, text, auditText, privacyAction, contentHash FROM events WHERE dayKey = '\''%s'\'' AND (text LIKE '\''%%%s%%'\'' OR auditText LIKE '\''%%%s%%'\'') ORDER BY capturedAt DESC;"\n' \
  "$DATABASE_PATH" \
  "$DAY_KEY" \
  "$VERIFY_ID" \
  "$VERIFY_ID"

printf '\nFollow-up Markdown check\n'
printf '  grep -n "%s" "%s"\n' "$VERIFY_ID" "$NOTE_PATH"
printf '  ls -l "%s"\n' "$NOTE_PATH"

printf '\nFallback if notification persistence is not visible in SQLite\n'
printf '  1. Keep the session unlocked and rerun the notification command printed above.\n'
printf '  2. If the banner still appears but no row is written, treat this macOS build as notification-store limited and accept clipboard + Markdown as the reproducible end-to-end check.\n'
