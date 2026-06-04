#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script_path="$repo_root/scripts/build-pkg.sh"

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

assert_file_exists() {
  local path="$1"
  local label="$2"

  if [[ ! -f "$path" ]]; then
    echo "Assertion failed for $label" >&2
    echo "Expected file: $path" >&2
    exit 1
  fi
}

if [[ ! -f "$script_path" ]]; then
  echo "Missing package builder: $script_path" >&2
  exit 1
fi

script="$(cat "$script_path")"
assert_contains "$script" "pkgbuild" "uses pkgbuild"
assert_contains "$script" "--install-location" "sets install location"
assert_contains "$script" "/Applications" "defaults to Applications"
assert_contains "$script" "CFBundleIdentifier" "reads bundle identifier"
assert_contains "$script" "CFBundleShortVersionString" "reads marketing version"
assert_contains "$script" "CFBundleVersion" "reads build version fallback"

tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

fake_app="$tmp_dir/KnowYou Test.app"
contents_dir="$fake_app/Contents"
mkdir -p "$contents_dir/MacOS" "$contents_dir/Resources"
cat >"$contents_dir/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>KnowYou Test</string>
  <key>CFBundleIdentifier</key>
  <string>dev.knowyou.pkgtest</string>
  <key>CFBundleName</key>
  <string>KnowYou Test</string>
  <key>CFBundleDisplayName</key>
  <string>KnowYou Test</string>
  <key>CFBundleShortVersionString</key>
  <string>9.9.9</string>
  <key>CFBundleVersion</key>
  <string>999</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
</dict>
</plist>
PLIST
printf '#!/usr/bin/env bash\nexit 0\n' >"$contents_dir/MacOS/KnowYou Test"
chmod +x "$contents_dir/MacOS/KnowYou Test"
xattr -w com.knowyou.pkgtest "metadata that package building should tolerate" "$contents_dir/MacOS/KnowYou Test"

release_dir="$tmp_dir/release"
KNOWYOU_APP_PATH="$fake_app" \
KNOWYOU_RELEASE_DIR="$release_dir" \
KNOWYOU_RELEASE_MARKETING_VERSION="Test" \
KNOWYOU_RELEASE_REPO_BUILD_NUMBER="42" \
"$script_path"

pkg_path="$release_dir/KnowYou-Test-42.pkg"
assert_file_exists "$pkg_path" "generated pkg"

expanded_dir="$tmp_dir/expanded"
pkgutil --expand "$pkg_path" "$expanded_dir"

package_info="$(cat "$expanded_dir/PackageInfo")"
assert_contains "$package_info" 'identifier="dev.knowyou.pkgtest.installer"' "pkg identifier"
assert_contains "$package_info" 'version="9.9.9"' "pkg version"
assert_contains "$package_info" 'install-location="/Applications"' "pkg install location"
assert_contains "$package_info" 'relocatable="false"' "non-relocatable app"
assert_contains "$package_info" 'id="dev.knowyou.pkgtest"' "bundle identifier metadata"
assert_contains "$package_info" '<relocate/>' "empty relocate section"

payload_files="$(pkgutil --payload-files "$pkg_path")"
assert_contains "$payload_files" "KnowYou Test.app/Contents/Info.plist" "payload contains app info"
assert_contains "$payload_files" "KnowYou Test.app/Contents/MacOS/KnowYou Test" "payload contains executable"

echo "build-pkg tests passed"
