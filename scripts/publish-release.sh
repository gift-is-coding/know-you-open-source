#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/scripts/release-common.sh"

require_command gh
require_command git
require_command python3
require_command shasum

"$repo_root/scripts/build-release.sh"
"$repo_root/scripts/notarize-release.sh"
"$repo_root/scripts/verify-release.sh"

ensure_file_exists "$(release_dmg_path)"

checksum_path="$(release_dmg_path).sha256"
checksum_value="$(shasum -a 256 "$(release_dmg_path)" | awk '{print $1}')"
printf '%s  %s\n' "$checksum_value" "$(basename "$(release_dmg_path)")" >"$checksum_path"

tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

downloads_clone_path="$tmp_dir/know-you-downloads"
gh repo clone "$download_repo" "$downloads_clone_path" -- -q

index_path="$downloads_clone_path/index.html"
ensure_file_exists "$index_path"

artifact_size_label="$(python3 - <<'PY' "$(release_dmg_path)"
import os
import sys

size = os.path.getsize(sys.argv[1])
print(f"{size / 1024 / 1024:.1f} MB DMG")
PY
)"

update_download_index_html "$index_path" "$artifact_size_label" "$checksum_value"

update_feed_path="$downloads_clone_path/update-feed/latest.json"
mkdir -p "$(dirname "$update_feed_path")"
release_update_feed_json >"$update_feed_path"

release_notes_path="$tmp_dir/release-notes.md"
release_notes_body >"$release_notes_path"

if gh release view "$(download_release_tag)" -R "$download_repo" >/dev/null 2>&1; then
  gh release upload "$(download_release_tag)" \
    "$(release_dmg_path)" \
    "$checksum_path" \
    -R "$download_repo" \
    --clobber
  gh release edit "$(download_release_tag)" \
    -R "$download_repo" \
    --title "$(download_release_title)" \
    --notes-file "$release_notes_path" \
    --latest
else
  gh release create "$(download_release_tag)" \
    "$(release_dmg_path)" \
    "$checksum_path" \
    -R "$download_repo" \
    --latest \
    --title "$(download_release_title)" \
    --notes-file "$release_notes_path"
fi

if [[ -n "$(git -C "$downloads_clone_path" status --porcelain -- index.html update-feed/latest.json)" ]]; then
  git -C "$downloads_clone_path" add index.html update-feed/latest.json
  git -C "$downloads_clone_path" commit -m "chore: update know you download page for v$(marketing_version)"
  git -C "$downloads_clone_path" push origin main
fi

echo "Release repo: https://github.com/$download_repo/releases/tag/$(download_release_tag)"
echo "Download URL: $(download_asset_url)"
echo "Update metadata URL: $(download_update_metadata_url)"
echo "Checksum: $checksum_value"
