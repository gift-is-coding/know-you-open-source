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
assert_contains "$script" "let width: CGFloat = 560" "compact background width"
assert_contains "$script" "let height: CGFloat = 300" "compact background height"
assert_contains "$script" "-fs HFS+" "Finder-layout-friendly image format"
assert_contains "$script" 'ditto "$app_path" "$mount_point/KnowYou.app"' "copy app into mounted image"
assert_contains "$script" 'ln -s /Applications "$mount_point/Applications"' "copy Applications symlink into mounted image"
assert_contains "$script" "set bounds to {100, 100, 660, 400}" "compact installer window"
assert_contains "$script" "set position of item \"KnowYou.app\" of installerFolder to {150, 148}" "app icon on the left"
assert_contains "$script" "set position of item \"Applications\" of installerFolder to {430, 148}" "Applications icon on the right"
assert_contains "$script" 'DMG_MOUNT_POINT="$mount_point" osascript' "Finder targets actual mounted path"
assert_contains "$script" 'set mountPoint to system attribute "DMG_MOUNT_POINT"' "AppleScript reads mounted path"
assert_contains "$script" 'set installerFolder to POSIX file mountPoint as alias' "AppleScript opens mounted path"
assert_contains "$script" "set installerWindow to front Finder window" "AppleScript uses concrete Finder window"
assert_contains "$script" "set icon size of theViewOptions to 96" "large icon size"
assert_contains "$script" "background.png" "custom background image"
assert_contains "$script" '$mount_point/.DS_Store' "Finder layout metadata verification"
assert_contains "$script" "Finder did not persist DMG layout metadata" "layout persistence failure message"

echo "build-dmg layout tests passed"
