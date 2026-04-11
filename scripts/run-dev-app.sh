#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
derived_data_path="$repo_root/.derived-data/dev"
app_path="$derived_data_path/Build/Products/Debug/KnowYou.app"

pkill -f '/KnowYou.app/Contents/MacOS/KnowYou' || true

# Clear old global Xcode app bundles so "open" never picks a stale build.
find "$HOME/Library/Developer/Xcode/DerivedData" \
  -path '*/Build/Products/Debug/KnowYou.app' \
  -type d \
  -prune \
  -exec rm -rf {} +

rm -rf "$app_path"

xcodebuild build \
  -scheme KnowYou \
  -destination 'platform=macOS' \
  -derivedDataPath "$derived_data_path"

if [[ ! -d "$app_path" ]]; then
  echo "Expected app not found: $app_path" >&2
  exit 1
fi

open -na "$app_path"
sleep 2

echo "App path: $app_path"
ps -Ao pid=,command= | rg '/KnowYou.app/Contents/MacOS/KnowYou' || true
