#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

export KNOWYOU_RELEASE_MARKETING_VERSION="1.2.3"
export KNOWYOU_RELEASE_BUILD_NUMBER="45"
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

assert_eq "1.2.3" "$(marketing_version)" "marketing_version"
assert_eq "45" "$(build_number)" "build_number"
assert_eq "KnowYou-1.2.3-45" "$(artifact_basename)" "artifact_basename"
assert_eq "$repo_root/build/test-release/KnowYou-1.2.3-45.zip" "$(release_zip_path)" "release_zip_path"
assert_eq "$repo_root/build/test-release/KnowYou-1.2.3-45-notarized.zip" "$(notarized_zip_path)" "notarized_zip_path"
assert_eq "$repo_root/build/test-release/KnowYou-1.2.3-45.dmg" "$(release_dmg_path)" "release_dmg_path"

mkdir -p "$KNOWYOU_RELEASE_DIR"
touch "$KNOWYOU_RELEASE_DIR/smoke.txt"
ensure_file_exists "$KNOWYOU_RELEASE_DIR/smoke.txt"

echo "release-common.sh tests passed"
