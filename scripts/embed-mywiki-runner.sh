#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
target_app="${1:-}"

if [[ -z "$target_app" || ! -d "$target_app" || "$target_app" != *.app ]]; then
  echo "Usage: scripts/embed-mywiki-runner.sh /path/to/KnowYou.app" >&2
  exit 1
fi

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

require_command ditto

"$repo_root/scripts/build-mywiki-runner.sh"

runner_source="$repo_root/build/MyWikiRunner"
runner_target="$target_app/Contents/Resources/MyWikiRunner"

if [[ ! -x "$runner_source/node" ]]; then
  echo "Built MyWikiRunner is missing executable node: $runner_source/node" >&2
  exit 1
fi

if [[ ! -f "$runner_source/mywiki-runner.js" ]]; then
  echo "Built MyWikiRunner is missing mywiki-runner.js" >&2
  exit 1
fi

rm -rf "$runner_target"
mkdir -p "$target_app/Contents/Resources"
ditto "$runner_source" "$runner_target"

if [[ ! -x "$target_app/Contents/Resources/MyWikiRunner/node" ]]; then
  echo "Embedded MyWikiRunner is missing executable node: $target_app/Contents/Resources/MyWikiRunner/node" >&2
  exit 1
fi

if [[ ! -f "$target_app/Contents/Resources/MyWikiRunner/mywiki-runner.js" ]]; then
  echo "Embedded MyWikiRunner is missing mywiki-runner.js: $target_app/Contents/Resources/MyWikiRunner/mywiki-runner.js" >&2
  exit 1
fi

if [[ -d "$target_app/Contents/Resources/KnowledgeOntology/LLM Wiki.app" ]]; then
  echo "Embedded app must not include LLM Wiki.app." >&2
  exit 1
fi

echo "Embedded MyWikiRunner: $runner_target"
