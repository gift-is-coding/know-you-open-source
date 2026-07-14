#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
runner="$repo_root/scripts/regression/run-user-journey.sh"
app_clean_run_id="test-app-clean-$$"
app_clean_run_dir="$repo_root/build/regression/$app_clean_run_id"
permission_run_id="test-permission-clean-$$"
permission_run_dir="$repo_root/build/regression/$permission_run_id"

rm -rf "$app_clean_run_dir" "$permission_run_dir"

"$runner" --app-clean --dry-run --run-id "$app_clean_run_id" >/tmp/knowyou-regression-runner-test.out

test_file() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    echo "Expected file missing: $path" >&2
    exit 1
  fi
}

assert_contains() {
  local path="$1"
  local expected="$2"
  if ! grep -Fq -- "$expected" "$path"; then
    echo "Expected '$expected' in $path" >&2
    exit 1
  fi
}

test_file "$app_clean_run_dir/env.sh"
test_file "$app_clean_run_dir/run-metadata.json"
test_file "$app_clean_run_dir/computer-use-prompt.md"
test_file "$app_clean_run_dir/assertions.md"

assert_contains "$app_clean_run_dir/env.sh" "KNOWYOU_PROFILE_ROOT="
assert_contains "$app_clean_run_dir/env.sh" "KNOWYOU_USER_DEFAULTS_SUITE=dev.knowyou.regression.$app_clean_run_id"
assert_contains "$app_clean_run_dir/env.sh" "KNOWYOU_KEYCHAIN_SERVICE=dev.knowyou.regression.$app_clean_run_id"
assert_contains "$runner" 'PRODUCT_BUNDLE_IDENTIFIER="$regression_bundle_identifier"'
assert_contains "$app_clean_run_dir/computer-use-prompt.md" "Codex GUI / Computer Use"
assert_contains "$app_clean_run_dir/computer-use-prompt.md" "02-my-diary-reader-refresh"
assert_contains "$app_clean_run_dir/computer-use-prompt.md" "06-engine-settings-status"
assert_contains "$app_clean_run_dir/computer-use-prompt.md" "Do not drive the UI through XCUITest"
assert_contains "$app_clean_run_dir/run-metadata.json" "\"environment\": \"app-clean\""
assert_contains "$app_clean_run_dir/assertions.md" "daily dev.knowyou.app state untouched"
assert_contains "$runner" "nohup env"
assert_contains "$runner" "</dev/null &"

if [[ -d "$repo_root/.derived-data/regression/$app_clean_run_id" ]]; then
  echo "Dry run should not build derived data." >&2
  exit 1
fi

"$runner" --permission-clean --dry-run --run-id "$permission_run_id" >/tmp/knowyou-regression-runner-test.out

test_file "$permission_run_dir/run-metadata.json"
test_file "$permission_run_dir/computer-use-prompt.md"
assert_contains "$permission_run_dir/run-metadata.json" "\"environment\": \"permission-clean\""
assert_contains "$permission_run_dir/run-metadata.json" "/Applications/KnowYou New User.app"
assert_contains "$permission_run_dir/computer-use-prompt.md" "01-first-run-onboarding"
assert_contains "$permission_run_dir/computer-use-prompt.md" "/Applications/KnowYou New User.app"
assert_contains "$permission_run_dir/computer-use-prompt.md" "daily dev.knowyou.app state was not touched"

defaults delete "dev.knowyou.regression.$app_clean_run_id" >/dev/null 2>&1 || true
rm -rf "$app_clean_run_dir" "$permission_run_dir"
echo "regression runner shell tests passed"
