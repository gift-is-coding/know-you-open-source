#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
derived_data_path="$repo_root/.derived-data/dev"
app_path="$derived_data_path/Build/Products/Debug/KnowYou.app"
app_executable="$app_path/Contents/MacOS/KnowYou"
build_metadata_path="$app_path/Contents/Resources/BuildMetadata.json"
expected_git_sha="$(git -C "$repo_root" rev-parse --short HEAD)"
mode="open"

usage() {
  cat <<'USAGE'
Usage: scripts/run-dev-app.sh [--open|--fresh]

  --open   Open the existing current-worktree dev app. If it is missing,
           build it. Never terminates running KnowYou processes. Default.
  --fresh  Close only this worktree's dev app, remove its app bundle, rebuild,
           embed MyWikiRunner, verify metadata, then open it.
USAGE
}

if [[ $# -gt 1 ]]; then
  usage >&2
  exit 2
fi

if [[ $# -eq 1 ]]; then
  case "$1" in
    --open)
      mode="open"
      ;;
    --fresh|--rebuild)
      mode="fresh"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
fi

current_worktree_pids() {
  ps -Ao pid=,command= | awk -v exe="$app_executable" 'index($0, exe) { print $1 }'
}

stop_current_worktree_app() {
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
}

build_app() {
  if xcodebuild build \
    -scheme KnowYou \
    -destination 'platform=macOS' \
    -derivedDataPath "$derived_data_path"; then
    return 0
  fi

  echo "Signed dev build failed; retrying without code signing for local launch." >&2
  xcodebuild build \
    -scheme KnowYou \
    -destination 'platform=macOS' \
    -derivedDataPath "$derived_data_path" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY=
}

embed_runner() {
  "$repo_root/scripts/embed-mywiki-runner.sh" "$app_path"

  if [[ ! -x "$app_path/Contents/Resources/MyWikiRunner/node" ]]; then
    echo "Expected MyWikiRunner node not found: $app_path/Contents/Resources/MyWikiRunner/node" >&2
    exit 1
  fi
}

verify_metadata() {
  local strict="$1"

  if [[ ! -f "$build_metadata_path" ]]; then
    echo "Build metadata not found: $build_metadata_path" >&2
    [[ "$strict" == "strict" ]] && exit 1
    return 0
  fi

  actual_git_sha="$(plutil -extract gitShortSHA raw -expect string "$build_metadata_path" 2>/dev/null || true)"

  if [[ -z "$actual_git_sha" ]]; then
    echo "Unable to read gitShortSHA from: $build_metadata_path" >&2
    [[ "$strict" == "strict" ]] && exit 1
    return 0
  fi

  if [[ "$actual_git_sha" != "$expected_git_sha" ]]; then
    echo "Warning: opening a dev app whose gitShortSHA differs from current HEAD." >&2
    echo "Expected HEAD: $expected_git_sha" >&2
    echo "Built app SHA: $actual_git_sha" >&2
    [[ "$strict" == "strict" ]] && exit 1
  fi
}

if [[ "$mode" == "fresh" ]]; then
  stop_current_worktree_app
  rm -rf "$app_path"
fi

if [[ ! -d "$app_path" ]]; then
  build_app
fi

if [[ ! -d "$app_path" ]]; then
  echo "Expected app not found: $app_path" >&2
  exit 1
fi

if [[ "$mode" == "fresh" || ! -x "$app_path/Contents/Resources/MyWikiRunner/node" ]]; then
  embed_runner
fi

if [[ "$mode" == "fresh" ]]; then
  verify_metadata strict
else
  verify_metadata warn
fi

open "$app_path"
sleep 2

echo "App path: $app_path"
echo "Mode: $mode"
echo "MyWikiRunner: $app_path/Contents/Resources/MyWikiRunner"
echo "Current worktree app PIDs:"
current_worktree_pids || true
