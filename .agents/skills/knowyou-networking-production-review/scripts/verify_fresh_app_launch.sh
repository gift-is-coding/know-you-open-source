#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: verify_fresh_app_launch.sh <fresh-app-path-file> <output-dir>" >&2
  exit 2
fi

fresh_app_path_file="$1"
out_dir="$2"
app="$(cat "$fresh_app_path_file")"
executable="$app/Contents/MacOS/KnowYou"
process_file="$out_dir/fresh-app-process.txt"

if [[ ! -d "$app" ]]; then
  echo "App bundle not found: $app" >&2
  exit 1
fi

if [[ ! -x "$executable" ]]; then
  echo "App executable not found: $executable" >&2
  exit 1
fi

existing_pids="$(pgrep -f "$executable" || true)"
if [[ -n "$existing_pids" ]]; then
  for pid in $existing_pids; do
    kill "$pid" >/dev/null 2>&1 || true
  done
  sleep 1
fi

open -n "$app"
sleep 3

pids="$(pgrep -f "$executable" || true)"
if [[ -z "$pids" ]]; then
  echo "No running KnowYou process found for: $executable" >&2
  exit 1
fi

: > "$process_file"
while IFS= read -r pid; do
  [[ -z "$pid" ]] && continue
  ps -p "$pid" -o pid=,command= >> "$process_file"
done <<< "$pids"

test -s "$process_file"
cat "$process_file"
