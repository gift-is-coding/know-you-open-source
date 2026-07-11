#!/usr/bin/env bash
set -euo pipefail

skill_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
pipeline="$skill_dir/scripts/run_pipeline.sh"
launch_helper="$skill_dir/scripts/verify_fresh_app_launch.sh"
web_server_helper="$skill_dir/scripts/start_networking_web_server.sh"
full_test_helper="$skill_dir/scripts/run_full_xcode_test.sh"
skill_file="$skill_dir/SKILL.md"
prompt_file="$skill_dir/references/claude-production-review-prompt.md"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ -x "$pipeline" ]] || fail "pipeline script must exist and be executable"
[[ -x "$launch_helper" ]] || fail "launch helper must exist and be executable"
[[ -x "$web_server_helper" ]] || fail "web server helper must exist and be executable"
[[ -x "$full_test_helper" ]] || fail "full xcode test helper must exist and be executable"
[[ -f "$skill_file" ]] || fail "SKILL.md must exist"
[[ -f "$prompt_file" ]] || fail "Claude review prompt reference must exist"

grep -q "xcodebuild test" "$pipeline" || fail "pipeline must run Swift tests"
grep -q 'xcodebuild Release build' "$pipeline" || fail "pipeline must build the Release app path"
grep -q 'run_full_xcode_test.sh' "$pipeline" || fail "pipeline must use the TCC-safe full test helper"
grep -q 'parallel-testing-worker-count 3' "$full_test_helper" || fail "full tests must use the stable macOS worker count"
grep -q -- "--exclude '.knowyou'" "$full_test_helper" || fail "full test mirror must exclude local Networking secrets"
grep -q -- "--exclude '.env\*'" "$full_test_helper" || fail "full test mirror must exclude environment files"
grep -q "EXIT INT TERM" "$full_test_helper" || fail "full test mirror must clean up on exit and termination"
grep -q -- "-mtime +1" "$full_test_helper" || fail "full test helper must sweep stale mirrors left by untrappable termination"
if grep -q '^exec xcodebuild test' "$full_test_helper"; then
  fail "full test helper must not replace the shell before its cleanup trap runs"
fi
grep -q "npm test -- --run" "$pipeline" || fail "pipeline must run NetworkingWeb tests"
grep -q "npm run lint" "$pipeline" || fail "pipeline must run NetworkingWeb lint"
grep -q "npm run typecheck" "$pipeline" || fail "pipeline must run NetworkingWeb typecheck"
grep -q "npm run build" "$pipeline" || fail "pipeline must run NetworkingWeb build"
grep -q "claude -p" "$pipeline" || fail "pipeline must invoke Claude non-interactively"
grep -q '@anthropic-ai/claude-code' "$pipeline" || fail "pipeline must fall back to the npm Claude CLI"
grep -q "HTML_STATUS" "$pipeline" || fail "pipeline must verify web HTML status"
grep -q "CSS_STATUS" "$pipeline" || fail "pipeline must verify CSS chunk status"
grep -q "BuildMetadata.json" "$pipeline" || fail "pipeline must capture fresh app build metadata"
grep -q "verify_fresh_app_launch.sh" "$pipeline" || fail "pipeline must use launch helper"
grep -q "start_networking_web_server.sh" "$pipeline" || fail "pipeline must use web server helper"
grep -q "npm start" "$web_server_helper" || fail "web verification must use the production server"
grep -q '"start": "next start"' "$skill_dir/../../../NetworkingWeb/package.json" || fail "NetworkingWeb must expose its production start command"
grep -q "screen -dmS" "$pipeline" || fail "pipeline must detach keep-server mode"
grep -q "FAIL" "$pipeline" || fail "pipeline must fail closed"
grep -q "production" "$prompt_file" || fail "Claude prompt must be production oriented"
grep -q "App UX" "$prompt_file" || fail "Claude prompt must include App UX"
grep -q "Web UX" "$prompt_file" || fail "Claude prompt must include Web UX"
grep -q "benchmark" "$prompt_file" || fail "Claude prompt must request benchmarks"
grep -q "test case" "$prompt_file" || fail "Claude prompt must request test cases"
grep -q "run_pipeline.sh" "$skill_file" || fail "skill must point users to the pipeline script"

echo "PASS: pipeline contract"
