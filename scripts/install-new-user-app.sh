#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
derived_data_path="${DERIVED_DATA_PATH:-$repo_root/.derived-data/new-user}"
built_app="$derived_data_path/Build/Products/Debug/KnowYou.app"
installed_app="${INSTALL_APP_PATH:-/Applications/KnowYou New User.app}"

bundle_id="dev.knowyou.newuser"
app_name="KnowYou New User"
executable_name="KnowYou New User"
original_executable_name="KnowYou"

launch_after_install=true
if [[ "${1:-}" == "--no-launch" ]]; then
  launch_after_install=false
fi

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

plist_get() {
  /usr/libexec/PlistBuddy -c "Print :$2" "$1/Contents/Info.plist"
}

plist_set() {
  /usr/libexec/PlistBuddy -c "Set :$2 $3" "$1/Contents/Info.plist"
}

find_signing_identity() {
  if [[ -n "${CODE_SIGN_IDENTITY:-}" ]]; then
    printf '%s\n' "$CODE_SIGN_IDENTITY"
    return
  fi

  local identity
  identity="$(security find-identity -v -p codesigning 2>/dev/null | awk '/Apple Development:/{print $2; exit}')"
  if [[ -n "$identity" ]]; then
    printf '%s\n' "$identity"
  else
    printf '%s\n' "-"
  fi
}

remove_stale_derived_data_apps() {
  local derived_data_root="$HOME/Library/Developer/Xcode/DerivedData"
  [[ -d "$derived_data_root" ]] || return

  while IFS= read -r -d '' candidate_app; do
    local candidate_plist="$candidate_app/Contents/Info.plist"
    [[ -f "$candidate_plist" ]] || continue

    local candidate_bundle_id
    candidate_bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$candidate_plist" 2>/dev/null || true)"
    if [[ "$candidate_bundle_id" == "$bundle_id" ]]; then
      rm -rf "$candidate_app"
    fi
  done < <(find "$derived_data_root" -path '*/Build/Products/*/*.app' -type d -prune -print0)
}

require_command xcodebuild
require_command ditto
require_command codesign
require_command security

osascript -e "tell application id \"$bundle_id\" to quit" >/dev/null 2>&1 || true
pkill -f "$installed_app/Contents/MacOS/" || true
remove_stale_derived_data_apps

rm -rf "$built_app"

xcodebuild build \
  -scheme KnowYou \
  -destination 'platform=macOS' \
  -derivedDataPath "$derived_data_path" \
  PRODUCT_BUNDLE_IDENTIFIER="$bundle_id" \
  INFOPLIST_KEY_CFBundleDisplayName="$app_name" \
  INFOPLIST_KEY_CFBundleName="$app_name"

if [[ ! -d "$built_app" ]]; then
  echo "Expected app not found: $built_app" >&2
  exit 1
fi

rm -rf "$installed_app"
ditto "$built_app" "$installed_app"

old_executable="$installed_app/Contents/MacOS/$original_executable_name"
new_executable="$installed_app/Contents/MacOS/$executable_name"
if [[ ! -f "$old_executable" ]]; then
  echo "Expected executable not found: $old_executable" >&2
  exit 1
fi
mv "$old_executable" "$new_executable"

plist_set "$installed_app" CFBundleIdentifier "$bundle_id"
plist_set "$installed_app" CFBundleDisplayName "$app_name"
plist_set "$installed_app" CFBundleName "$app_name"
plist_set "$installed_app" CFBundleExecutable "$executable_name"

signing_identity="$(find_signing_identity)"
codesign \
  --force \
  --deep \
  --sign "$signing_identity" \
  --timestamp=none \
  --preserve-metadata=entitlements,requirements,flags,runtime \
  "$installed_app"

xattr -dr com.apple.quarantine "$installed_app" 2>/dev/null || true
/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister \
  -f \
  -R \
  -trusted \
  "$installed_app"

actual_bundle_id="$(plist_get "$installed_app" CFBundleIdentifier)"
actual_display_name="$(plist_get "$installed_app" CFBundleDisplayName)"
actual_name="$(plist_get "$installed_app" CFBundleName)"
actual_executable="$(plist_get "$installed_app" CFBundleExecutable)"

if [[ "$actual_bundle_id" != "$bundle_id" ||
      "$actual_display_name" != "$app_name" ||
      "$actual_name" != "$app_name" ||
      "$actual_executable" != "$executable_name" ||
      ! -f "$new_executable" ]]; then
  echo "Installed app identity check failed." >&2
  echo "CFBundleIdentifier: $actual_bundle_id" >&2
  echo "CFBundleDisplayName: $actual_display_name" >&2
  echo "CFBundleName: $actual_name" >&2
  echo "CFBundleExecutable: $actual_executable" >&2
  exit 1
fi

if [[ "$launch_after_install" == true ]]; then
  open "$installed_app"
fi

echo "Installed: $installed_app"
echo "CFBundleIdentifier: $actual_bundle_id"
echo "CFBundleDisplayName: $actual_display_name"
echo "CFBundleName: $actual_name"
echo "CFBundleExecutable: $actual_executable"
echo "Signing identity: $signing_identity"
