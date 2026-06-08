#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
runner_dir="${KNOWYOU_MYWIKI_RUNNER_DIR:-$repo_root/build/MyWikiRunner}"

"$repo_root/scripts/build-mywiki-runner.sh"

[[ -x "$runner_dir/node" ]] || { echo "Missing executable node"; exit 1; }
[[ -f "$runner_dir/mywiki-runner.js" ]] || { echo "Missing mywiki-runner.js"; exit 1; }
[[ ! -d "$runner_dir/node_modules" ]] || { echo "Runner must not ship node_modules"; exit 1; }
[[ ! -d "$runner_dir/LLM Wiki.app" ]] || { echo "Runner must not ship LLM Wiki.app"; exit 1; }

if rg -n "npm run|npm install|node_modules" "$runner_dir/mywiki-runner.js"; then
  echo "Runner bundle contains runtime npm/node_modules dependency text"
  exit 1
fi

"$runner_dir/node" "$runner_dir/mywiki-runner.js" --help >/tmp/knowyou-mywiki-runner-help.txt 2>&1 || true
rg -n "Missing required --project|Usage|--project" /tmp/knowyou-mywiki-runner-help.txt >/dev/null
echo "mywiki runner package tests passed"
