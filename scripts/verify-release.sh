#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/scripts/release-common.sh"

require_command codesign
require_command spctl
require_command xcrun

target_app="${1:-$app_path}"
ensure_file_exists "$target_app"

codesign --verify --deep --strict --verbose=2 "$target_app"
codesign -dvv "$target_app"
xcrun stapler validate "$target_app"
spctl --assess --type execute -vv "$target_app"
