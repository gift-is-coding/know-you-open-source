#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

export KNOWYOU_RELEASE_MARKETING_VERSION="1.2.3"
export KNOWYOU_RELEASE_BUILD_NUMBER="45"
export KNOWYOU_RELEASE_REPO_BUILD_NUMBER="145"
export KNOWYOU_RELEASE_DIR="$repo_root/build/test-release"

source "$repo_root/scripts/release-common.sh"

assert_eq() {
  local expected="$1"
  local actual="$2"
  local label="$3"

  if [[ "$expected" != "$actual" ]]; then
    echo "Assertion failed for $label" >&2
    echo "Expected: $expected" >&2
    echo "Actual:   $actual" >&2
    exit 1
  fi
}

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

assert_eq "1.2.3" "$(marketing_version)" "marketing_version"
assert_eq "45" "$(build_number)" "build_number"
assert_eq "145" "$(release_repo_build_number)" "release_repo_build_number"
assert_eq "KnowYou-1.2.3-145" "$(artifact_basename)" "artifact_basename"
assert_eq "$repo_root/build/test-release/KnowYou-1.2.3-145.zip" "$(release_zip_path)" "release_zip_path"
assert_eq "$repo_root/build/test-release/KnowYou-1.2.3-145-notarized.zip" "$(notarized_zip_path)" "notarized_zip_path"
assert_eq "$repo_root/build/test-release/KnowYou-1.2.3-145.dmg" "$(release_dmg_path)" "release_dmg_path"

project_text="$(cat "$repo_root/KnowYou.xcodeproj/project.pbxproj")"
assert_contains "$project_text" 'INFOPLIST_FILE = KnowYou/Config/Info.plist;' "explicit app Info.plist"
assert_contains "$project_text" 'KNOWYOU_SPARKLE_PUBLIC_ED_KEY = "DPaKuqvU48UAoI0rOvKtWaStpzMsX9fwypStdx4md/M=";' "Sparkle public key setting"
assert_contains "$project_text" 'KNOWYOU_UPDATE_CHANNEL = direct;' "update channel setting"
assert_contains "$project_text" 'KNOWYOU_UPDATE_METADATA_URL = "https://raw.githubusercontent.com/gift-is-coding/know-you-downloads/main/update-feed/latest.json";' "release update metadata URL"
assert_contains "$project_text" 'KNOWYOU_UPDATE_METADATA_URL = "http://127.0.0.1:8765/Support/update-feed/debug-update.json";' "debug update metadata URL"
assert_contains "$project_text" 'KNOWYOU_SPARKLE_FEED_URL = "https://raw.githubusercontent.com/gift-is-coding/know-you-downloads/main/update-feed/appcast.xml";' "release Sparkle appcast URL"
assert_contains "$project_text" 'scripts/write-build-metadata.sh' "build metadata script path"

info_plist="$(cat "$repo_root/KnowYou/Config/Info.plist")"
assert_contains "$info_plist" '<key>KYUpdateMetadataURL</key>' "Info.plist update metadata key"
assert_contains "$info_plist" '<string>$(KNOWYOU_UPDATE_CHANNEL)</string>' "Info.plist update channel setting"
assert_contains "$info_plist" '<string>$(KNOWYOU_UPDATE_METADATA_URL)</string>' "Info.plist update metadata setting"
assert_contains "$info_plist" '<key>SUFeedURL</key>' "Info.plist Sparkle feed key"
assert_contains "$info_plist" '<string>$(KNOWYOU_SPARKLE_FEED_URL)</string>' "Info.plist Sparkle feed setting"
assert_contains "$info_plist" '<key>SUPublicEDKey</key>' "Info.plist Sparkle public key"

assert_eq "DPaKuqvU48UAoI0rOvKtWaStpzMsX9fwypStdx4md/M=" "$(sparkle_public_ed_key)" "sparkle_public_ed_key default"

build_metadata_script="$(cat "$repo_root/scripts/write-build-metadata.sh")"
assert_contains "$build_metadata_script" 'KYUpdateChannel' "build metadata script writes update channel"
assert_contains "$build_metadata_script" 'KYUpdateMetadataURL' "build metadata script writes update metadata URL"
assert_contains "$build_metadata_script" 'KNOWYOU_UPDATE_METADATA_URL' "build metadata script reads update metadata setting"

mkdir -p "$KNOWYOU_RELEASE_DIR"
touch "$KNOWYOU_RELEASE_DIR/smoke.txt"
ensure_file_exists "$KNOWYOU_RELEASE_DIR/smoke.txt"

echo "release-common.sh tests passed"
