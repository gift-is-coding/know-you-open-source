#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
project_path="$repo_root/KnowYou.xcodeproj"
scheme_name="${KNOWYOU_SCHEME:-KnowYou}"
release_dir="${KNOWYOU_RELEASE_DIR:-$repo_root/build/release}"
archive_path="${KNOWYOU_ARCHIVE_PATH:-$release_dir/KnowYou.xcarchive}"
app_path="${KNOWYOU_APP_PATH:-$release_dir/KnowYou.app}"
notary_profile="${KNOWYOU_NOTARY_PROFILE:-know-you-notary}"
developer_team="${KNOWYOU_DEVELOPER_TEAM:-3DY726RPHL}"
developer_id_identity="${KNOWYOU_DEVELOPER_ID_IDENTITY:-Developer ID Application: danhu ouyang (3DY726RPHL)}"
download_repo="${KNOWYOU_DOWNLOAD_REPO:-gift-is-coding/know-you-downloads}"
default_sparkle_public_ed_key="DPaKuqvU48UAoI0rOvKtWaStpzMsX9fwypStdx4md/M="

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

require_sparkle_public_key() {
  if [[ -z "$(sparkle_public_ed_key)" ]]; then
    echo "Missing KNOWYOU_SPARKLE_PUBLIC_ED_KEY. Generate it with Sparkle generate_keys and export it before building a release." >&2
    exit 1
  fi
}

sparkle_public_ed_key() {
  printf '%s\n' "${KNOWYOU_SPARKLE_PUBLIC_ED_KEY:-$default_sparkle_public_ed_key}"
}

build_setting() {
  local key="$1"
  xcodebuild -project "$project_path" -scheme "$scheme_name" -configuration Release -showBuildSettings \
    | awk -F ' = ' -v key="$key" '$1 ~ ("^[[:space:]]*" key "$") { print $2; exit }'
}

marketing_version() {
  if [[ -n "${KNOWYOU_RELEASE_MARKETING_VERSION:-}" ]]; then
    printf '%s\n' "$KNOWYOU_RELEASE_MARKETING_VERSION"
    return
  fi

  build_setting "MARKETING_VERSION"
}

build_number() {
  if [[ -n "${KNOWYOU_RELEASE_BUILD_NUMBER:-}" ]]; then
    printf '%s\n' "$KNOWYOU_RELEASE_BUILD_NUMBER"
    return
  fi

  build_setting "CURRENT_PROJECT_VERSION"
}

release_repo_build_number() {
  if [[ -n "${KNOWYOU_RELEASE_REPO_BUILD_NUMBER:-}" ]]; then
    printf '%s\n' "$KNOWYOU_RELEASE_REPO_BUILD_NUMBER"
    return
  fi

  git -C "$repo_root" rev-list --count HEAD
}

release_repo_commit() {
  if [[ -n "${KNOWYOU_RELEASE_REPO_COMMIT:-}" ]]; then
    printf '%s\n' "$KNOWYOU_RELEASE_REPO_COMMIT"
    return
  fi

  git -C "$repo_root" rev-parse --short HEAD
}

release_date() {
  if [[ -n "${KNOWYOU_RELEASE_DATE:-}" ]]; then
    printf '%s\n' "$KNOWYOU_RELEASE_DATE"
    return
  fi

  date '+%Y-%m-%d'
}

artifact_basename() {
  printf 'KnowYou-%s-%s\n' "$(marketing_version)" "$(release_repo_build_number)"
}

release_zip_path() {
  printf '%s/%s.zip\n' "$release_dir" "$(artifact_basename)"
}

notarized_zip_path() {
  printf '%s/%s-notarized.zip\n' "$release_dir" "$(artifact_basename)"
}

release_dmg_path() {
  printf '%s/%s.dmg\n' "$release_dir" "$(artifact_basename)"
}

checksum_asset_name() {
  printf '%s.sha256\n' "$(basename "$(release_dmg_path)")"
}

sparkle_signature_attributes() {
  local signer="${KNOWYOU_SPARKLE_SIGN_UPDATE:-sign_update}"

  if [[ "$signer" == */* ]]; then
    ensure_file_exists "$signer"
  else
    require_command "$signer"
  fi

  "$signer" "$(release_dmg_path)" | tr -d '\n'
}

download_release_tag() {
  printf 'v%s-build%s\n' "$(marketing_version)" "$(release_repo_build_number)"
}

download_release_title() {
  printf 'KnowYou v%s (%s)\n' "$(marketing_version)" "$(release_repo_build_number)"
}

download_asset_url() {
  printf 'https://github.com/%s/releases/download/%s/%s\n' \
    "$download_repo" \
    "$(download_release_tag)" \
    "$(basename "$(release_dmg_path)")"
}

download_update_metadata_url() {
  if [[ -n "${KNOWYOU_UPDATE_METADATA_URL:-}" ]]; then
    printf '%s\n' "$KNOWYOU_UPDATE_METADATA_URL"
    return
  fi

  printf 'https://raw.githubusercontent.com/%s/main/update-feed/latest.json\n' "$download_repo"
}

release_update_feed_json() {
  local published_at="${KNOWYOU_RELEASE_PUBLISHED_AT:-$(release_date)T00:00:00Z}"
  local summary
  summary="$(release_notes_body)"

  KNOWYOU_RELEASE_SUMMARY="$summary" python3 - <<'PY' \
    "$(marketing_version)" \
    "$(download_release_title)" \
    "$published_at" \
    "$(download_asset_url)"
import json
import os
import sys

version = sys.argv[1]
title = sys.argv[2]
published_at = sys.argv[3]
download_url = sys.argv[4]
summary = os.environ["KNOWYOU_RELEASE_SUMMARY"]

payload = {
    "version": version,
    "summary": summary,
    "publishedAt": published_at,
    "downloadURL": download_url,
}

json.dump(payload, sys.stdout, ensure_ascii=False, indent=2)
sys.stdout.write("\n")
PY
}

release_update_appcast_xml() {
  local signature_attributes="$1"
  local published_at="${KNOWYOU_RELEASE_PUBLISHED_AT:-$(release_date)T00:00:00Z}"
  local release_notes
  release_notes="$(release_notes_body)"

  KNOWYOU_RELEASE_NOTES="$release_notes" python3 - <<'PY' \
    "$(marketing_version)" \
    "$(release_repo_build_number)" \
    "$(download_release_title)" \
    "$published_at" \
    "$(download_asset_url)" \
    "$signature_attributes"
import email.utils
import html
import os
import sys
from datetime import datetime, timezone

marketing_version = sys.argv[1]
build_number = sys.argv[2]
title = sys.argv[3]
published_at = sys.argv[4]
download_url = sys.argv[5]
signature_attributes = sys.argv[6].strip()
release_notes = os.environ["KNOWYOU_RELEASE_NOTES"]

try:
    parsed_date = datetime.fromisoformat(published_at.replace("Z", "+00:00"))
except ValueError:
    parsed_date = datetime.now(timezone.utc)

if parsed_date.tzinfo is None:
    parsed_date = parsed_date.replace(tzinfo=timezone.utc)

pub_date = email.utils.format_datetime(parsed_date.astimezone(timezone.utc))
escaped_title = html.escape(title)
escaped_url = html.escape(download_url, quote=True)
description = "<![CDATA[" + release_notes.replace("]]>", "]]]]><![CDATA[>") + "]]>"

print(f"""<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>KnowYou Updates</title>
    <link>https://github.com/gift-is-coding/know-you-downloads</link>
    <description>KnowYou direct release updates</description>
    <item>
      <title>{escaped_title}</title>
      <sparkle:version>{html.escape(build_number)}</sparkle:version>
      <sparkle:shortVersionString>{html.escape(marketing_version)}</sparkle:shortVersionString>
      <pubDate>{html.escape(pub_date)}</pubDate>
      <description>{description}</description>
      <enclosure url="{escaped_url}" type="application/octet-stream" {signature_attributes} />
    </item>
  </channel>
</rss>""")
PY
}

release_notes_body() {
  if [[ -n "${KNOWYOU_RELEASE_NOTES_FILE:-}" ]]; then
    ensure_file_exists "$KNOWYOU_RELEASE_NOTES_FILE"
    cat "$KNOWYOU_RELEASE_NOTES_FILE"
    return
  fi

  if [[ -n "${KNOWYOU_RELEASE_NOTES:-}" ]]; then
    printf '%s\n' "$KNOWYOU_RELEASE_NOTES"
    return
  fi

  cat <<EOF
KnowYou turns daily computer context into a story-first journal on macOS.

Release:
- Version: $(marketing_version)
- Build: $(release_repo_build_number)
- Commit: $(release_repo_commit)
- Artifact: $(basename "$(release_dmg_path)")
- Notarization: Accepted on $(release_date)

Install:
- Download the DMG asset below.
- Open the DMG and drag \`KnowYou.app\` to \`Applications\`.
- Launch the app and complete the macOS permission prompts for clipboard and notifications.

Verification:
- \`codesign --verify --deep --strict --verbose=2\` passed.
- \`xcrun stapler validate\` passed.
- \`spctl --assess --type execute -vv\` accepted the app as \`Notarized Developer ID\`.
EOF
}

update_download_index_html() {
  local index_path="$1"
  local artifact_size_label="$2"
  local checksum_value="$3"

  python3 - <<'PY' \
    "$index_path" \
    "$(download_asset_url)" \
    "https://github.com/$download_repo/releases/tag/$(download_release_tag)" \
    "$(marketing_version) ($(release_repo_build_number))" \
    "$(release_repo_commit)" \
    "$artifact_size_label" \
    "$checksum_value"
import pathlib
import re
import sys

path = pathlib.Path(sys.argv[1])
download_url = sys.argv[2]
release_notes_url = sys.argv[3]
version_label = sys.argv[4]
commit_sha = sys.argv[5]
artifact_size = sys.argv[6]
checksum = sys.argv[7]

text = path.read_text(encoding="utf-8")

patterns = [
    (
        r'(<a class="btn btn-primary" href=")[^"]+(">Download for macOS</a>)',
        rf'\g<1>{download_url}\g<2>',
    ),
    (
        r'(<a class="btn btn-secondary" href=")[^"]+(">Release notes</a>)',
        rf'\g<1>{release_notes_url}\g<2>',
    ),
    (
        r'(<div class="metric-label">Version</div>\s*<div class="metric-value">)([^<]+)(</div>)',
        rf'\g<1>{version_label}\g<3>',
    ),
    (
        r'(<div class="metric-label">Commit</div>\s*<div class="metric-value"><code>)([^<]+)(</code></div>)',
        rf'\g<1>{commit_sha}\g<3>',
    ),
    (
        r'(<div class="metric-label">Artifact</div>\s*<div class="metric-value">)([^<]+)(</div>)',
        rf'\g<1>{artifact_size}\g<3>',
    ),
    (
        r'(<div class="metric-label">SHA-256</div>\s*<div class="metric-value"><code>)([^<]+)(</code></div>)',
        rf'\g<1>{checksum}\g<3>',
    ),
    (
        r'(<div class="notice">\s*)(.*?)(\s*</div>)',
        (
            r'\1Open the DMG and drag KnowYou to Applications. '
            r'This build is signed with Developer ID, notarized by Apple, and stapled. '
            r'Gatekeeper verification passed before release.\3'
        ),
    ),
]

for pattern, replacement in patterns:
    updated_text, count = re.subn(pattern, replacement, text, count=1, flags=re.S)
    if count != 1:
        raise SystemExit(f"Failed to update pattern: {pattern}")
    text = updated_text

path.write_text(text, encoding="utf-8")
PY
}

ensure_file_exists() {
  local path="$1"
  [[ -e "$path" ]] || {
    echo "Expected file not found: $path" >&2
    exit 1
  }
}

ensure_notary_profile() {
  if ! xcrun notarytool history --keychain-profile "$notary_profile" >/dev/null 2>&1; then
    echo "Missing notarytool keychain profile: $notary_profile" >&2
    echo "Store it first with xcrun notarytool store-credentials." >&2
    exit 1
  fi
}

prepare_release_dir() {
  mkdir -p "$release_dir"
}
