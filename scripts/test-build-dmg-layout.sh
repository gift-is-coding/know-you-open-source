#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script_path="$repo_root/scripts/build-dmg.sh"

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local label="$3"

  if [[ "$haystack" != *"$needle"* ]]; then
    echo "Assertion failed for $label" >&2
    echo "Expected to find: $needle" >&2
    exit 1
  fi
}

script="$(cat "$script_path")"

assert_contains "$script" "Drag KnowYou to Applications" "background install instruction"
assert_contains "$script" "prepare_release_dir" "standalone release directory setup"
assert_contains "$script" 'dmg_app_name="${KNOWYOU_DMG_APP_NAME:-KnowYou.app}"' "default dmg app name"
assert_contains "$script" 'dmg_volume_name="${KNOWYOU_DMG_VOLUME_NAME:-KnowYou}"' "default dmg volume name"
assert_contains "$script" "let width: CGFloat = 560" "compact background width"
assert_contains "$script" "let height: CGFloat = 300" "compact background height"
assert_contains "$script" "let appIconCenterX: CGFloat = 150" "background app icon center constant"
assert_contains "$script" "let applicationsIconCenterX: CGFloat = 430" "background Applications icon center constant"
assert_contains "$script" "let iconSize: CGFloat = 96" "background icon size constant"
assert_contains "$script" "let arrowStartX = appIconCenterX + iconSize / 2 + 32" "arrow starts after app icon bounds"
assert_contains "$script" "let arrowEndX = applicationsIconCenterX - iconSize / 2 - 18" "arrow ends before Applications icon bounds"
assert_contains "$script" "shaft.move(to: NSPoint(x: arrowStartX, y: arrowY))" "arrow start uses layout constant"
assert_contains "$script" "shaft.line(to: NSPoint(x: arrowEndX, y: arrowY))" "arrow end uses layout constant"
assert_contains "$script" "-fs HFS+" "Finder-layout-friendly image format"
assert_contains "$script" 'ditto "$app_path" "$mount_point/$dmg_app_name"' "copy app into mounted image"
assert_contains "$script" 'ln -s /Applications "$mount_point/Applications"' "copy Applications symlink into mounted image"
assert_contains "$script" "set bounds to {100, 100, 660, 400}" "compact installer window"
assert_contains "$script" "set position of item appName of installerFolder to {150, 148}" "app icon on the left"
assert_contains "$script" "set position of item \"Applications\" of installerFolder to {430, 148}" "Applications icon on the right"
assert_contains "$script" 'DMG_MOUNT_POINT="$mount_point" osascript' "Finder targets actual mounted path"
assert_contains "$script" 'DMG_APP_NAME="$dmg_app_name"' "Finder receives custom app name"
assert_contains "$script" 'set mountPoint to system attribute "DMG_MOUNT_POINT"' "AppleScript reads mounted path"
assert_contains "$script" 'set appName to system attribute "DMG_APP_NAME"' "AppleScript reads custom app name"
assert_contains "$script" 'set installerFolder to POSIX file mountPoint as alias' "AppleScript opens mounted path"
assert_contains "$script" "set installerWindow to front Finder window" "AppleScript uses concrete Finder window"
assert_contains "$script" "set icon size of theViewOptions to 96" "large icon size"
assert_contains "$script" "background.png" "custom background image"
assert_contains "$script" '$mount_point/.DS_Store' "Finder layout metadata verification"
assert_contains "$script" "Finder did not persist DMG layout metadata" "layout persistence failure message"

tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

swift_generator="$tmp_dir/generate-dmg-background.swift"
background_path="$tmp_dir/background.png"
awk "
  index(\$0, \"cat >\\\"\\\$swift_path\\\" <<'SWIFT'\") { in_swift = 1; next }
  in_swift && \$0 ~ /^[[:space:]]*SWIFT\$/ { exit }
  in_swift { print }
" "$script_path" >"$swift_generator"

if [[ ! -s "$swift_generator" ]]; then
  echo "Assertion failed for background generator extraction" >&2
  exit 1
fi

swift "$swift_generator" "$background_path" "Drag KnowYou to Applications" "Move the app first, then grant Full Disk Access."
pixel_width="$(sips -g pixelWidth "$background_path" 2>/dev/null | awk '/pixelWidth/ { print $2; exit }')"
pixel_height="$(sips -g pixelHeight "$background_path" 2>/dev/null | awk '/pixelHeight/ { print $2; exit }')"

if [[ "$pixel_width" != "1120" || "$pixel_height" != "600" ]]; then
  echo "Assertion failed for retina background pixel dimensions" >&2
  echo "Expected 1120x600, got ${pixel_width:-missing}x${pixel_height:-missing}" >&2
  exit 1
fi

echo "build-dmg layout tests passed"
