#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
mode=""
run_id=""
dry_run=false
launch_after_prepare=true
reset_new_user_state=false

usage() {
  cat <<'EOF'
Usage:
  scripts/regression/run-user-journey.sh --app-clean [--run-id ID] [--dry-run] [--no-launch]
  scripts/regression/run-user-journey.sh --permission-clean [--run-id ID] [--dry-run] [--no-launch] [--reset-new-user-state]
  scripts/regression/run-user-journey.sh --true-clean-checklist [--run-id ID]

This script prepares KnowYou regression runs for Codex GUI / Computer Use.
It does not click the native app and must not be treated as an XCUITest or UI automation replacement.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app-clean|--permission-clean|--true-clean-checklist)
      mode="${1#--}"
      ;;
    --run-id)
      shift
      run_id="${1:-}"
      ;;
    --dry-run)
      dry_run=true
      ;;
    --no-launch)
      launch_after_prepare=false
      ;;
    --reset-new-user-state)
      reset_new_user_state=true
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 64
      ;;
  esac
  shift
done

if [[ -z "$mode" ]]; then
  echo "Missing regression mode." >&2
  usage >&2
  exit 64
fi

if [[ -z "$run_id" ]]; then
  run_id="$(date +%Y%m%dT%H%M%S)-$mode"
fi

run_dir="$repo_root/build/regression/$run_id"
profile_root="$run_dir/profile"
evidence_dir="$run_dir/evidence"
env_file="$run_dir/env.sh"
metadata_file="$run_dir/run-metadata.json"
prompt_file="$run_dir/computer-use-prompt.md"
assertions_file="$run_dir/assertions.md"
app_clean_app_path="$repo_root/.derived-data/regression/$run_id/Build/Products/Debug/KnowYou.app"
new_user_app_path="/Applications/KnowYou New User.app"

mkdir -p "$run_dir" "$profile_root" "$evidence_dir"

json_escape() {
  python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$1"
}

write_env_file() {
  local environment="$1"
  local suite="dev.knowyou.regression.$run_id"
  local keychain_service="dev.knowyou.regression.$run_id"

  cat >"$env_file" <<EOF
export KNOWYOU_REGRESSION_MODE=1
export KNOWYOU_REGRESSION_ENVIRONMENT=$environment
export KNOWYOU_PROFILE_ROOT="$profile_root"
export KNOWYOU_USER_DEFAULTS_SUITE=$suite
export KNOWYOU_KEYCHAIN_SERVICE=$keychain_service
export KYUpdateMetadataURL="http://127.0.0.1:8765/Support/update-feed/debug-update.json"
export KYUpdateChannel="debug"
EOF
}

write_metadata() {
  local environment="$1"
  local app_path="$2"
  local git_sha
  git_sha="$(git -C "$repo_root" rev-parse --short HEAD)"
  cat >"$metadata_file" <<EOF
{
  "runId": $(json_escape "$run_id"),
  "environment": $(json_escape "$environment"),
  "repoRoot": $(json_escape "$repo_root"),
  "gitShortSHA": $(json_escape "$git_sha"),
  "runDirectory": $(json_escape "$run_dir"),
  "profileRoot": $(json_escape "$profile_root"),
  "appPath": $(json_escape "$app_path"),
  "evidenceDirectory": $(json_escape "$evidence_dir"),
  "dryRun": $dry_run
}
EOF
}

write_assertions() {
  local environment="$1"
  cat >"$assertions_file" <<EOF
# Regression Assertions

- environment: $environment
- daily dev.knowyou.app state untouched
- no XCUITest target, AppleScript/System Events/AX shell driver, or third-party UI automation is used
- native app clicks and observations are performed by Codex GUI / Computer Use only
- screenshots, SQLite checks, Markdown checks, and final status should be saved under: $evidence_dir
EOF
}

write_prompt() {
  local environment="$1"
  local app_path="$2"
  shift 2
  local cases=("$@")

  {
    cat <<EOF
# KnowYou Codex GUI / Computer Use Regression

Use the repo-local skill: \`.agents/skills/knowyou-regression-runner/SKILL.md\`.

Environment: \`$environment\`
Run directory: \`$run_dir\`
Evidence directory: \`$evidence_dir\`
Launch path: \`$app_path\`

Hard boundaries:
- Do not drive the UI through XCUITest, AppleScript/System Events/AX shell scripts, or third-party UI automation.
- Use Codex GUI / Computer Use for native macOS clicks and visual assertions.
- Use Browser or Chrome only when the product intentionally opens a browser surface.
- Do not modify real Codex, Claude Code, Cursor, Gemini, OpenClaw, browser, OAuth, or external account config.
- Keep evidence in \`$evidence_dir\`.

Test cases to execute:
EOF
    for case_file in "${cases[@]}"; do
      printf -- '- `%s`\n' "$case_file"
    done
    cat <<'EOF'

Execution pattern:
1. Read the listed test case files from docs/regression/test-cases.
2. Launch or activate the app from the launch path above.
3. Click only visible, user-reachable controls.
4. Capture screenshots for major transitions.
5. Pair GUI observations with shell evidence where the case asks for persisted files or SQLite rows.
6. Mark each case pass, fail, blocked, or manual-only with the failing step and evidence path.
7. Before reporting success, confirm daily dev.knowyou.app state was not touched.
EOF
  } >"$prompt_file"
}

seed_app_clean_profile() {
  local suite="dev.knowyou.regression.$run_id"
  local app_support="$profile_root/Application Support/KnowYou"
  local vault="$app_support/Vault"

  mkdir -p "$app_support" "$vault"
  "$repo_root/scripts/seed-demo-april-04-06.sh" "$app_support" >/dev/null
  defaults write "$suite" hasCompletedOnboarding -bool true
  defaults write "$suite" onboardingProgressState -string complete
  defaults write "$suite" onboardingBootstrapState -string complete
  defaults write "$suite" explicitlyDisabledSummarizerAutoSelection -bool true
}

build_app_clean_app() {
  local derived_data="$repo_root/.derived-data/regression/$run_id"
  rm -rf "$derived_data/Build/Products/Debug/KnowYou.app"
  xcodebuild build \
    -scheme KnowYou \
    -destination 'platform=macOS' \
    -derivedDataPath "$derived_data"
}

launch_app_clean_app() {
  source "$env_file"
  env \
    KNOWYOU_REGRESSION_MODE="$KNOWYOU_REGRESSION_MODE" \
    KNOWYOU_REGRESSION_ENVIRONMENT="$KNOWYOU_REGRESSION_ENVIRONMENT" \
    KNOWYOU_PROFILE_ROOT="$KNOWYOU_PROFILE_ROOT" \
    KNOWYOU_USER_DEFAULTS_SUITE="$KNOWYOU_USER_DEFAULTS_SUITE" \
    KNOWYOU_KEYCHAIN_SERVICE="$KNOWYOU_KEYCHAIN_SERVICE" \
    KYUpdateMetadataURL="$KYUpdateMetadataURL" \
    KYUpdateChannel="$KYUpdateChannel" \
    "$app_clean_app_path/Contents/MacOS/KnowYou" >"$run_dir/app.stdout.log" 2>"$run_dir/app.stderr.log" &
  echo $! >"$run_dir/app.pid"
}

prepare_permission_clean() {
  if [[ "$dry_run" == false ]]; then
    "$repo_root/scripts/install-new-user-app.sh" --no-launch
  fi

  if [[ "$reset_new_user_state" == true && "$dry_run" == false ]]; then
    rm -rf "$HOME/Library/Application Support/KnowYou New User"
    defaults delete dev.knowyou.newuser >/dev/null 2>&1 || true
    tccutil reset SystemPolicyAllFiles dev.knowyou.newuser >/dev/null 2>&1 || true
  fi
}

launch_permission_clean_app() {
  open "$new_user_app_path"
}

case "$mode" in
  app-clean)
    write_env_file "app-clean"
    seed_app_clean_profile
    write_metadata "app-clean" "$app_clean_app_path"
    write_assertions "app-clean"
    write_prompt \
      "app-clean" \
      "$app_clean_app_path" \
      "02-my-diary-reader-refresh" \
      "03-todo-inbox" \
      "04-other-source-connectors" \
      "05-my-wiki-source-library-agent" \
      "06-engine-settings-status"
    if [[ "$dry_run" == false ]]; then
      build_app_clean_app
      if [[ "$launch_after_prepare" == true ]]; then
        launch_app_clean_app
      fi
    fi
    ;;
  permission-clean)
    write_env_file "permission-clean"
    prepare_permission_clean
    write_metadata "permission-clean" "$new_user_app_path"
    write_assertions "permission-clean"
    write_prompt \
      "permission-clean" \
      "$new_user_app_path" \
      "01-first-run-onboarding"
    if [[ "$dry_run" == false && "$launch_after_prepare" == true ]]; then
      launch_permission_clean_app
    fi
    ;;
  true-clean-checklist)
    write_env_file "true-clean"
    write_metadata "true-clean" "fresh signed app or DMG in a separate macOS user or VM"
    write_assertions "true-clean"
    write_prompt \
      "true-clean" \
      "fresh signed app or DMG in a separate macOS user or VM" \
      "01-first-run-onboarding" \
      "09-release-gate"
    ;;
esac

cat <<EOF
Regression run prepared.
Run directory: $run_dir
Computer Use prompt: $prompt_file
Assertions: $assertions_file
Metadata: $metadata_file
EOF
