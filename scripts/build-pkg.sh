#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/scripts/release-common.sh"

require_command pkgbuild
require_command ditto
require_command plutil

prepare_release_dir
ensure_file_exists "$app_path"

if [[ "$app_path" != *.app || ! -d "$app_path/Contents" ]]; then
  echo "KNOWYOU_APP_PATH must point to a macOS .app bundle: $app_path" >&2
  exit 1
fi

plist_path="$app_path/Contents/Info.plist"
ensure_file_exists "$plist_path"

plist_get() {
  /usr/libexec/PlistBuddy -c "Print :$2" "$1" 2>/dev/null
}

bundle_identifier="$(plist_get "$plist_path" CFBundleIdentifier || true)"
marketing_version_from_app="$(plist_get "$plist_path" CFBundleShortVersionString || true)"
build_version_from_app="$(plist_get "$plist_path" CFBundleVersion || true)"

if [[ -z "$bundle_identifier" ]]; then
  echo "App bundle is missing CFBundleIdentifier: $plist_path" >&2
  exit 1
fi

pkg_identifier="${KNOWYOU_PKG_IDENTIFIER:-$bundle_identifier.installer}"
pkg_version="${KNOWYOU_PKG_VERSION:-${marketing_version_from_app:-$build_version_from_app}}"
pkg_install_location="${KNOWYOU_PKG_INSTALL_LOCATION:-/Applications}"

if [[ -z "$pkg_identifier" || "$pkg_identifier" == *"/"* ]]; then
  echo "Invalid package identifier: $pkg_identifier" >&2
  exit 1
fi

if [[ -z "$pkg_version" ]]; then
  echo "App bundle must provide CFBundleShortVersionString or CFBundleVersion, or set KNOWYOU_PKG_VERSION." >&2
  exit 1
fi

if [[ -z "$pkg_install_location" || "$pkg_install_location" != /* ]]; then
  echo "KNOWYOU_PKG_INSTALL_LOCATION must be an absolute path: $pkg_install_location" >&2
  exit 1
fi

work_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$work_dir"
}
trap cleanup EXIT

component_plist="$work_dir/component.plist"
payload_root="$work_dir/payload"
app_name="$(basename "$app_path")"
root_relative_bundle_path="$app_name"
mkdir -p "$payload_root"
ditto --norsrc "$app_path" "$payload_root/$app_name"
xattr -cr "$payload_root/$app_name" 2>/dev/null || true

cat >"$component_plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<array>
  <dict>
    <key>BundleHasStrictIdentifier</key>
    <true/>
    <key>BundleIsRelocatable</key>
    <false/>
    <key>BundleIsVersionChecked</key>
    <true/>
    <key>BundleOverwriteAction</key>
    <string>upgrade</string>
    <key>RootRelativeBundlePath</key>
    <string>$root_relative_bundle_path</string>
  </dict>
</array>
</plist>
PLIST

plutil -lint "$component_plist" >/dev/null

pkgbuild_args=(
  --root "$payload_root"
  --component-plist "$component_plist"
  --install-location "$pkg_install_location"
  --identifier "$pkg_identifier"
  --version "$pkg_version"
)

if [[ -n "${KNOWYOU_PKG_SIGN_IDENTITY:-}" ]]; then
  pkgbuild_args+=(--sign "$KNOWYOU_PKG_SIGN_IDENTITY")
fi

rm -f "$(release_pkg_path)"
pkgbuild "${pkgbuild_args[@]}" "$(release_pkg_path)"

echo "PKG: $(release_pkg_path)"
