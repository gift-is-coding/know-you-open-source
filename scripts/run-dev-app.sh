#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
derived_data_path="$repo_root/.derived-data/dev"
app_path="$derived_data_path/Build/Products/Debug/KnowYou.app"
app_executable="$app_path/Contents/MacOS/KnowYou"
build_metadata_path="$app_path/Contents/Resources/BuildMetadata.json"
expected_git_sha="$(git -C "$repo_root" rev-parse --short HEAD)"

current_worktree_pids() {
  ps -Ao pid=,command= | awk -v exe="$app_executable" 'index($0, exe) { print $1 }'
}

for _ in {1..20}; do
  pids="$(current_worktree_pids)"
  if [[ -z "$pids" ]]; then
    break
  fi
  kill $pids >/dev/null 2>&1 || true
  sleep 0.25
done

remaining_pids="$(current_worktree_pids)"
if [[ -n "$remaining_pids" ]]; then
  kill -9 $remaining_pids >/dev/null 2>&1 || true
fi

rm -rf "$app_path"

xcodebuild build \
  -scheme KnowYou \
  -destination 'platform=macOS' \
  -derivedDataPath "$derived_data_path"

if [[ ! -d "$app_path" ]]; then
  echo "Expected app not found: $app_path" >&2
  exit 1
fi

"$repo_root/scripts/embed-mywiki-runner.sh" "$app_path"

if [[ ! -x "$app_path/Contents/Resources/MyWikiRunner/node" ]]; then
  echo "Expected MyWikiRunner node not found: $app_path/Contents/Resources/MyWikiRunner/node" >&2
  exit 1
fi

if [[ ! -f "$build_metadata_path" ]]; then
  echo "Build metadata not found: $build_metadata_path" >&2
  exit 1
fi

actual_git_sha="$(plutil -extract gitShortSHA raw -expect string "$build_metadata_path" 2>/dev/null || true)"

if [[ -z "$actual_git_sha" ]]; then
  echo "Unable to read gitShortSHA from: $build_metadata_path" >&2
  exit 1
fi

if [[ "$actual_git_sha" != "$expected_git_sha" ]]; then
  echo "Refusing to open stale build." >&2
  echo "Expected HEAD: $expected_git_sha" >&2
  echo "Built app SHA: $actual_git_sha" >&2
  exit 1
fi

open -n "$app_path"
sleep 2

echo "App path: $app_path"
echo "Verified gitShortSHA: $actual_git_sha"
echo "MyWikiRunner: $app_path/Contents/Resources/MyWikiRunner"
ps -Ao pid=,command= | rg '/KnowYou.app/Contents/MacOS/KnowYou' || true
