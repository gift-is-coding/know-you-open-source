#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/scripts/release-common.sh"

require_command xcodebuild
require_command ditto
require_sparkle_public_key

prepare_release_dir
rm -rf "$archive_path" "$app_path" "$(release_zip_path)" "$(notarized_zip_path)"

xcodebuild archive \
  -project "$project_path" \
  -scheme "$scheme_name" \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$archive_path" \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM="$developer_team" \
  CODE_SIGN_IDENTITY="$developer_id_identity" \
  ENABLE_HARDENED_RUNTIME=YES \
  KNOWYOU_SPARKLE_PUBLIC_ED_KEY="$(sparkle_public_ed_key)"

ensure_file_exists "$archive_path/Products/Applications/KnowYou.app"

ditto "$archive_path/Products/Applications/KnowYou.app" "$app_path"
ditto -c -k --sequesterRsrc --keepParent "$app_path" "$(release_zip_path)"

echo "Archive: $archive_path"
echo "App: $app_path"
echo "Zip: $(release_zip_path)"
