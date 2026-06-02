#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fixture_dir="${KNOWYOU_LOCAL_UPDATE_DIR:-$repo_root/Support/update-feed}"
public_path="${KNOWYOU_LOCAL_UPDATE_PUBLIC_PATH:-Support/update-feed}"
version="${KNOWYOU_LOCAL_UPDATE_VERSION:-9.9.0}"
build_number="${KNOWYOU_LOCAL_UPDATE_BUILD:-9999}"
base_url="${KNOWYOU_LOCAL_UPDATE_BASE_URL:-http://127.0.0.1:8765}"
published_at="${KNOWYOU_LOCAL_UPDATE_PUBLISHED_AT:-2026-06-02T00:00:00Z}"
title="${KNOWYOU_LOCAL_UPDATE_TITLE:-KnowYou Local Debug $version}"
asset_name="${KNOWYOU_LOCAL_UPDATE_ASSET_NAME:-KnowYou-local-update-$version.dmg}"
source_dmg="${KNOWYOU_LOCAL_UPDATE_DMG:-}"
release_notes="${KNOWYOU_LOCAL_UPDATE_NOTES:-本地 fake 更新，用来测试 KnowYou 的更新胶囊、更新内容 sheet，以及 Sparkle 检查入口。

- 左上角应该显示更明显的更新胶囊。
- 点击胶囊后，sheet 应该显示完整更新内容。
- 如果没有提供真实 DMG，这个 appcast 只用于 UI 预览；提供真实 DMG 后会写入 Sparkle 签名 enclosure。}"

trim_slashes() {
  local value="$1"
  value="${value#/}"
  value="${value%/}"
  printf '%s\n' "$value"
}

asset_url="$(printf '%s/%s/%s' "${base_url%/}" "$(trim_slashes "$public_path")" "$asset_name")"
signature_attributes='sparkle:edSignature="local-fixture-placeholder" length="1"'
mode_label="UI-only fixture"

mkdir -p "$fixture_dir"

if [[ -n "$source_dmg" ]]; then
  [[ -f "$source_dmg" ]] || {
    echo "Expected KNOWYOU_LOCAL_UPDATE_DMG to point to a file: $source_dmg" >&2
    exit 1
  }

  target_dmg="$fixture_dir/$asset_name"
  cp "$source_dmg" "$target_dmg"

  signer="${KNOWYOU_SPARKLE_SIGN_UPDATE:-sign_update}"
  if [[ "$signer" == */* ]]; then
    [[ -x "$signer" ]] || {
      echo "Expected Sparkle sign_update tool to be executable: $signer" >&2
      exit 1
    }
  elif ! command -v "$signer" >/dev/null 2>&1; then
    echo "Missing Sparkle sign_update tool. Set KNOWYOU_SPARKLE_SIGN_UPDATE or install Sparkle tools." >&2
    exit 1
  fi

  signature_attributes="$("$signer" "$target_dmg" | tr -d '\n')"
  mode_label="signed DMG fixture"
fi

KNOWYOU_LOCAL_VERSION="$version" \
KNOWYOU_LOCAL_BUILD="$build_number" \
KNOWYOU_LOCAL_TITLE="$title" \
KNOWYOU_LOCAL_PUBLISHED_AT="$published_at" \
KNOWYOU_LOCAL_NOTES="$release_notes" \
KNOWYOU_LOCAL_ASSET_URL="$asset_url" \
KNOWYOU_LOCAL_SIGNATURE_ATTRIBUTES="$signature_attributes" \
KNOWYOU_LOCAL_OUTPUT_DIR="$fixture_dir" \
python3 - <<'PY'
import email.utils
import html
import json
import os
import pathlib
from datetime import datetime, timezone

version = os.environ["KNOWYOU_LOCAL_VERSION"]
build_number = os.environ["KNOWYOU_LOCAL_BUILD"]
title = os.environ["KNOWYOU_LOCAL_TITLE"]
published_at = os.environ["KNOWYOU_LOCAL_PUBLISHED_AT"]
release_notes = os.environ["KNOWYOU_LOCAL_NOTES"]
asset_url = os.environ["KNOWYOU_LOCAL_ASSET_URL"]
signature_attributes = os.environ["KNOWYOU_LOCAL_SIGNATURE_ATTRIBUTES"].strip()
output_dir = pathlib.Path(os.environ["KNOWYOU_LOCAL_OUTPUT_DIR"])

try:
    parsed_date = datetime.fromisoformat(published_at.replace("Z", "+00:00"))
except ValueError:
    parsed_date = datetime.now(timezone.utc)

if parsed_date.tzinfo is None:
    parsed_date = parsed_date.replace(tzinfo=timezone.utc)

pub_date = email.utils.format_datetime(parsed_date.astimezone(timezone.utc))
description = "<![CDATA[" + release_notes.replace("]]>", "]]]]><![CDATA[>") + "]]>"

debug_payload = {
    "version": version,
    "summary": release_notes,
    "publishedAt": published_at,
    "downloadURL": asset_url,
}

(output_dir / "debug-update.json").write_text(
    json.dumps(debug_payload, ensure_ascii=False, indent=2) + "\n",
    encoding="utf-8",
)

appcast = f"""<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>KnowYou Debug Updates</title>
    <link>{html.escape(asset_url, quote=True)}</link>
    <description>Local debug appcast for previewing the Sparkle update flow.</description>
    <item>
      <title>{html.escape(title)}</title>
      <sparkle:version>{html.escape(build_number)}</sparkle:version>
      <sparkle:shortVersionString>{html.escape(version)}</sparkle:shortVersionString>
      <pubDate>{html.escape(pub_date)}</pubDate>
      <description>{description}</description>
      <enclosure url="{html.escape(asset_url, quote=True)}" type="application/octet-stream" {signature_attributes} />
    </item>
  </channel>
</rss>
"""

(output_dir / "appcast.xml").write_text(appcast, encoding="utf-8")
PY

echo "Prepared KnowYou local update fixture: $mode_label"
echo "  Version: $version ($build_number)"
echo "  Feed:    $fixture_dir"
echo "  URL:     $asset_url"
echo
echo "Serve it with:"
echo "  cd '$repo_root' && /usr/bin/python3 -m http.server 8765 --bind 127.0.0.1"
