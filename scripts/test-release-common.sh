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
assert_contains "$project_text" 'INFOPLIST_KEY_KYUpdateMetadataURL = "https://raw.githubusercontent.com/gift-is-coding/know-you-downloads/main/update-feed/latest.json";' "release update metadata URL"
assert_contains "$project_text" 'INFOPLIST_KEY_KYUpdateMetadataURL = "http://127.0.0.1:8765/Support/update-feed/debug-update.json";' "debug update metadata URL"
assert_contains "$project_text" 'scripts/write-build-metadata.sh' "build metadata script path"

build_metadata_script="$(cat "$repo_root/scripts/write-build-metadata.sh")"
assert_contains "$build_metadata_script" 'KYUpdateChannel' "build metadata script writes update channel"
assert_contains "$build_metadata_script" 'KYUpdateMetadataURL' "build metadata script writes update metadata URL"

mkdir -p "$KNOWYOU_RELEASE_DIR"
touch "$KNOWYOU_RELEASE_DIR/smoke.txt"
ensure_file_exists "$KNOWYOU_RELEASE_DIR/smoke.txt"

echo "release-common.sh tests passed"
