#!/usr/bin/env sh

set -eu

output_path="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/BuildMetadata.json"
info_plist_path="$TARGET_BUILD_DIR/$INFOPLIST_PATH"
auto_build_number="1"
build_timestamp="$(date '+%m-%d %H:%M')"
git_short_sha=""

if command -v git >/dev/null 2>&1; then
  auto_build_number="$(git -C "$SRCROOT" rev-list --count HEAD 2>/dev/null || printf '1')"
  git_short_sha="$(git -C "$SRCROOT" rev-parse --short HEAD 2>/dev/null || true)"
fi

set_plist_string() {
  key="$1"
  value="$2"

  if [ -z "$value" ]; then
    return 0
  fi

  if /usr/libexec/PlistBuddy -c "Print :$key" "$info_plist_path" >/dev/null 2>&1; then
    /usr/libexec/PlistBuddy -c "Set :$key $value" "$info_plist_path"
  else
    /usr/libexec/PlistBuddy -c "Add :$key string $value" "$info_plist_path"
  fi
}

if [ -f "$info_plist_path" ]; then
  update_channel="${KNOWYOU_UPDATE_CHANNEL:-${INFOPLIST_KEY_KYUpdateChannel:-}}"
  update_metadata_url="${KNOWYOU_UPDATE_METADATA_URL:-${INFOPLIST_KEY_KYUpdateMetadataURL:-}}"

  set_plist_string "CFBundleVersion" "$auto_build_number"
  set_plist_string "KYUpdateChannel" "$update_channel"
  set_plist_string "KYUpdateMetadataURL" "$update_metadata_url"
fi

mkdir -p "$(dirname "$output_path")"
cat >"$output_path" <<EOF
{"buildNumber":"$auto_build_number","buildTimestamp":"$build_timestamp","gitShortSHA":"$git_short_sha"}
EOF
