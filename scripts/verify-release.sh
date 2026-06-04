#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/scripts/release-common.sh"

require_command codesign
require_command spctl
require_command xcrun

target_app="${1:-$app_path}"
ensure_file_exists "$target_app"

mywiki_node="$target_app/Contents/Resources/MyWikiRunner/node"
if [[ ! -x "$mywiki_node" ]]; then
  echo "Release is missing executable MyWikiRunner node: $mywiki_node" >&2
  exit 1
fi

if [[ -d "$target_app/Contents/Resources/KnowledgeOntology/LLM Wiki.app" ]]; then
  echo "Release must not include LLM Wiki.app" >&2
  exit 1
fi

if ! codesign -d --entitlements :- "$mywiki_node" 2>/dev/null | grep -q 'com.apple.security.cs.allow-jit'; then
  echo "Release MyWikiRunner node is missing allow-jit entitlement required by V8 under hardened runtime" >&2
  exit 1
fi

codesign --verify --deep --strict --verbose=2 "$target_app"
codesign -dvv "$target_app"
xcrun stapler validate "$target_app"
spctl --assess --type execute -vv "$target_app"
