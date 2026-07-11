#!/usr/bin/env bash
set -Eeuo pipefail

port=3028
output_root="docs/reviews/networking-production-review"
claude_budget_usd="2"
full_test_timeout_seconds=900
keep_server=0
run_full_xcode_test=1
launch_app=1
run_claude=1
dry_run=0

usage() {
  cat <<'USAGE'
Usage: run_pipeline.sh [options]

Run the KnowYou Networking production-readiness pipeline:
  - verify git/worktree state
  - run Web and macOS build/test gates
  - restart/verify the local NetworkingWeb preview
  - optionally launch the fresh macOS app
  - run Claude production review against the current diff
  - write a review packet under docs/reviews/networking-production-review/

Options:
  --port <port>                         Local web preview port (default: 3028)
  --output-root <path>                  Report root (default: docs/reviews/networking-production-review)
  --claude-budget-usd <amount>          Claude CLI max budget (default: 2)
  --full-test-timeout-seconds <seconds> Full xcodebuild test timeout (default: 900)
  --skip-full-xcode-test                Mark full suite as skipped instead of running it
  --skip-launch                         Do not open the fresh macOS app
  --skip-claude                         Do not call Claude review
  --keep-server                         Leave the local web server running after verification
  --dry-run                             Print planned commands without running them
  -h, --help                            Show this help
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --port)
      port="$2"
      shift 2
      ;;
    --output-root)
      output_root="$2"
      shift 2
      ;;
    --claude-budget-usd)
      claude_budget_usd="$2"
      shift 2
      ;;
    --full-test-timeout-seconds)
      full_test_timeout_seconds="$2"
      shift 2
      ;;
    --skip-full-xcode-test)
      run_full_xcode_test=0
      shift
      ;;
    --skip-launch)
      launch_app=0
      shift
      ;;
    --skip-claude)
      run_claude=0
      shift
      ;;
    --keep-server)
      keep_server=1
      shift
      ;;
    --dry-run)
      dry_run=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

repo_root="$(git rev-parse --show-toplevel)"
skill_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
prompt_file="$skill_dir/references/claude-production-review-prompt.md"
run_id="$(date +%Y%m%d-%H%M%S)"
out_dir="$repo_root/$output_root/$run_id"
command_tsv="$out_dir/commands.tsv"
report_file="$out_dir/report.md"
failures_file="$out_dir/failures.txt"
web_env_script="$out_dir/web-node-env.sh"
server_pid=""
overall_status=0

mkdir -p "$out_dir"
: > "$command_tsv"
: > "$failures_file"

cd "$repo_root"

select_web_node_bin() {
  local candidate
  if [[ -n "${KNOWYOU_NETWORKING_NODE_BIN:-}" ]]; then
    candidate="$KNOWYOU_NETWORKING_NODE_BIN"
    if [[ -x "$candidate/node" ]] && "$candidate/node" -e 'process.exit(Number(process.versions.node.split(".")[0]) >= 20 ? 0 : 1)'; then
      printf '%s\n' "$candidate"
      return 0
    fi
  fi

  for candidate in \
    "$HOME/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin" \
    "/opt/homebrew/bin" \
    "/usr/local/bin"; do
    if [[ -x "$candidate/node" ]] && "$candidate/node" -e 'process.exit(Number(process.versions.node.split(".")[0]) >= 20 ? 0 : 1)'; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
}

select_claude_command() {
  if [[ -n "${KNOWYOU_CLAUDE_BIN:-}" ]] && [[ -x "$KNOWYOU_CLAUDE_BIN" ]]; then
    claude_cmd=("$KNOWYOU_CLAUDE_BIN")
  elif command -v claude >/dev/null 2>&1; then
    claude_cmd=(claude)
  elif command -v npm >/dev/null 2>&1; then
    claude_cmd=(npm exec --yes --package=@anthropic-ai/claude-code -- claude)
  else
    claude_cmd=()
  fi
}

web_node_bin="$(select_web_node_bin || true)"
{
  echo 'set -euo pipefail'
  if [[ -n "$web_node_bin" ]]; then
    printf 'export PATH=%q:$PATH\n' "$web_node_bin"
  fi
  echo 'echo "NODE=$(command -v node) $(node --version)"'
  echo 'echo "NPM=$(command -v npm) $(npm --version)"'
  echo 'node -e '\''process.exit(Number(process.versions.node.split(".")[0]) >= 20 ? 0 : 1)'\'' || { echo "Node $(node --version) is too old for NetworkingWeb" >&2; exit 1; }'
} > "$web_env_script"

note() {
  printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"
}

slugify() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9_' '-' | sed 's/^-//; s/-$//'
}

record() {
  local name="$1"
  local code="$2"
  local log="$3"
  local state
  if [[ "$code" -eq 0 ]]; then
    state="PASS"
  else
    state="FAIL"
    overall_status=1
    printf '%s\n' "$name" >> "$failures_file"
  fi
  printf '%s\t%s\t%s\n' "$name" "$state" "$log" >> "$command_tsv"
  note "$state $name"
}

run_cmd() {
  local name="$1"
  shift
  local slug
  slug="$(slugify "$name")"
  local log="$out_dir/${slug}.log"
  note "RUN $name"
  {
    printf '$'
    printf ' %q' "$@"
    printf '\n\n'
  } > "$log"
  if [[ "$dry_run" -eq 1 ]]; then
    echo "DRY RUN" >> "$log"
    record "$name" 0 "$log"
    return 0
  fi
  set +e
  "$@" >> "$log" 2>&1
  local code=$?
  set -e
  record "$name" "$code" "$log"
  return 0
}

run_cmd_timeout() {
  local name="$1"
  local seconds="$2"
  shift 2
  local slug
  slug="$(slugify "$name")"
  local log="$out_dir/${slug}.log"
  note "RUN $name (timeout ${seconds}s)"
  if [[ "$dry_run" -eq 1 ]]; then
    {
      printf '$ timeout %q' "$seconds"
      printf ' %q' "$@"
      printf '\n\nDRY RUN\n'
    } > "$log"
    record "$name" 0 "$log"
    return 0
  fi
  set +e
  python3 - "$seconds" "$log" "$@" <<'PY'
import subprocess
import sys

seconds = int(sys.argv[1])
log_path = sys.argv[2]
cmd = sys.argv[3:]

with open(log_path, "w", encoding="utf-8") as log:
    log.write("$ timeout {} ".format(seconds) + " ".join(cmd) + "\n\n")
    log.flush()
    try:
        completed = subprocess.run(
            cmd,
            stdout=log,
            stderr=subprocess.STDOUT,
            timeout=seconds,
            check=False,
        )
        raise SystemExit(completed.returncode)
    except subprocess.TimeoutExpired:
        log.write("\nTIMEOUT after {} seconds\n".format(seconds))
        raise SystemExit(124)
PY
  local code=$?
  set -e
  record "$name" "$code" "$log"
  return 0
}

skip_cmd() {
  local name="$1"
  local blocking="${2:-0}"
  local slug
  slug="$(slugify "$name")"
  local log="$out_dir/${slug}.log"
  echo "SKIPPED by option" > "$log"
  printf '%s\t%s\t%s\n' "$name" "SKIP" "$log" >> "$command_tsv"
  if [[ "$blocking" -eq 1 && "$dry_run" -eq 0 ]]; then
    overall_status=1
    printf '%s\n' "$name (skipped)" >> "$failures_file"
  fi
  note "SKIP $name"
}

cleanup_server() {
  if [[ -n "$server_pid" && "$keep_server" -eq 0 ]]; then
    kill "$server_pid" >/dev/null 2>&1 || true
  fi
}
trap cleanup_server EXIT

write_report() {
  local result="PASS"
  if [[ "$overall_status" -ne 0 ]]; then
    result="FAIL"
  fi
  {
    echo "# KnowYou Networking Production Review Packet"
    echo
    echo "- Run ID: \`$run_id\`"
    echo "- Worktree: \`$repo_root\`"
    echo "- Result: **$result**"
    echo "- Local web URL: \`http://127.0.0.1:$port/?platform=knowyou-friends\`"
    echo
    echo "## Git"
    echo
    echo '```'
    cat "$out_dir/git-status.log" 2>/dev/null || true
    echo '```'
    echo
    echo "## Command Results"
    echo
    echo "| Gate | Status | Log |"
    echo "| --- | --- | --- |"
    while IFS=$'\t' read -r name state log; do
      rel="${log#$repo_root/}"
      echo "| $name | $state | \`$rel\` |"
    done < "$command_tsv"
    echo
    echo "## Claude Review"
    echo
    if [[ -f "$out_dir/claude-review.md" ]]; then
      echo "See \`${out_dir#$repo_root/}/claude-review.md\`."
    else
      echo "No Claude review artifact was produced."
    fi
    echo
    echo "## Required Follow-Up"
    echo
    if [[ -s "$failures_file" ]]; then
      sed 's/^/- Fix failing gate: /' "$failures_file"
    else
      echo "- None from automated gates."
    fi
    echo
    echo "## Production Benchmarks To Inspect"
    echo
    echo "- App: stale activation migration, three-step cockpit guidance, Open Square inline errors, fresh app metadata."
    echo "- Web: signed-out guidance/no composer, signed-in viewer-scoped profile rail, app handoff, CSS chunk health."
    echo "- Agent/MCP: no plaintext token in tool output, sandbox/stale state rejection, Agent Home queue shape."
  } > "$report_file"
}
trap 'write_report; cleanup_server' EXIT

run_cmd "git status/log" bash -lc 'git status --short --branch && git log --oneline -2 && git diff --stat' || true
cp "$out_dir/git-status-log.log" "$out_dir/git-status.log" 2>/dev/null || true

run_cmd "git diff check" git diff --check || true
run_cmd "localhost fallback audit" bash -lc '
set -euo pipefail
hits="$(rg -n "127\\.0\\.0\\.1:3028" KnowYou/ || true)"
if [[ -z "$hits" ]]; then
  echo "No localhost web fallback found."
  exit 0
fi
echo "$hits"
bad_hits="$(printf "%s\n" "$hits" | grep -v "^KnowYou/Services/Networking/NetworkingPlatformClient.swift:" || true)"
if [[ -n "$bad_hits" ]]; then
  echo "Unexpected localhost fallback outside NetworkingBackendConfiguration:" >&2
  printf "%s\n" "$bad_hits" >&2
  exit 1
fi
python3 - <<PY
from pathlib import Path

path = Path("KnowYou/Services/Networking/NetworkingPlatformClient.swift")
lines = path.read_text(encoding="utf-8").splitlines()
for index, line in enumerate(lines):
    if "127.0.0.1:3028" not in line:
        continue
    window = "\n".join(lines[max(0, index - 6): index + 2])
    if "#if DEBUG" not in window:
        print("Localhost fallback is not protected by #if DEBUG", file=__import__("sys").stderr)
        raise SystemExit(1)
print("Localhost fallback is restricted to DEBUG NetworkingBackendConfiguration.")
PY
' || true

run_cmd "NetworkingWeb tests" bash -lc 'source "'"$web_env_script"'"; cd NetworkingWeb && npm test -- --run' || true
run_cmd "NetworkingWeb lint" bash -lc 'source "'"$web_env_script"'"; cd NetworkingWeb && npm run lint' || true
run_cmd "NetworkingWeb typecheck" bash -lc 'source "'"$web_env_script"'"; cd NetworkingWeb && npm run typecheck' || true
run_cmd "NetworkingWeb build" bash -lc 'source "'"$web_env_script"'"; cd NetworkingWeb && npm run build' || true

run_cmd "Swift networking targeted tests" xcodebuild test \
  -scheme KnowYou \
  -destination 'platform=macOS' \
  -only-testing:KnowYouTests/NetworkingCockpitPresentationTests \
  -only-testing:KnowYouTests/NetworkingPlatformClientTests \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY= || true

if [[ "$run_full_xcode_test" -eq 1 ]]; then
  run_cmd_timeout "Full xcodebuild test" "$full_test_timeout_seconds" xcodebuild test \
    -scheme KnowYou \
    -destination 'platform=macOS' \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY= || true
else
  skip_cmd "Full xcodebuild test" 1
fi

run_cmd "xcodebuild build" xcodebuild build \
  -scheme KnowYou \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY= || true

if [[ "$dry_run" -eq 0 ]]; then
  occupied_pids="$(lsof -tiTCP:"$port" -sTCP:LISTEN 2>/dev/null || true)"
  if [[ -n "$occupied_pids" ]]; then
    for pid in $occupied_pids; do
      cwd_path="$(lsof -a -p "$pid" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p' | head -1)"
      if [[ "$cwd_path" == "$repo_root/NetworkingWeb" ]]; then
        kill "$pid" >/dev/null 2>&1 || true
      else
        echo "Port $port is used by PID $pid outside this worktree: $cwd_path" > "$out_dir/web-server.log"
        record "NetworkingWeb dev server" 1 "$out_dir/web-server.log"
      fi
    done
    sleep 2
  fi

  if ! lsof -tiTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; then
    : > "$out_dir/web-server.log"
    if [[ "$keep_server" -eq 1 && -x "$(command -v screen)" ]]; then
      screen_name="knowyou-networking-$run_id"
      echo "SCREEN_SESSION=$screen_name" >> "$out_dir/web-server.log"
      screen -dmS "$screen_name" bash "$skill_dir/scripts/start_networking_web_server.sh" \
        "$web_env_script" "$repo_root" "$port" "$out_dir/web-server.log"
      echo "$screen_name" > "$out_dir/web-server.screen"
    else
      bash "$skill_dir/scripts/start_networking_web_server.sh" \
        "$web_env_script" "$repo_root" "$port" "$out_dir/web-server.log" &
      server_pid=$!
      echo "$server_pid" > "$out_dir/web-server.pid"
    fi
    for _ in $(seq 1 60); do
      if curl -fsS "http://127.0.0.1:$port/?platform=knowyou-friends" >/dev/null 2>&1; then
        break
      fi
      sleep 1
    done
    if curl -fsS "http://127.0.0.1:$port/?platform=knowyou-friends" >/dev/null 2>&1; then
      record "NetworkingWeb dev server" 0 "$out_dir/web-server.log"
    else
      record "NetworkingWeb dev server" 1 "$out_dir/web-server.log"
    fi
  fi
else
  echo "DRY RUN" > "$out_dir/dry-run-web-server.log"
  record "NetworkingWeb dev server" 0 "$out_dir/dry-run-web-server.log"
fi

run_cmd "NetworkingWeb HTML and CSS chunk" bash -lc '
set -euo pipefail
html="'"$out_dir"'/web.html"
curl -fsS -D "'"$out_dir"'/web.headers" "http://127.0.0.1:'"$port"'/?platform=knowyou-friends" -o "$html"
html_status="$(head -1 "'"$out_dir"'/web.headers")"
css="$(python3 - <<PY
from pathlib import Path
import re
html = Path("'"$out_dir"'/web.html").read_text(errors="ignore")
match = re.search(r"href=\"([^\"]+\\.css[^\"]*)\"", html)
print(match.group(1) if match else "")
PY
)"
if [ -z "$css" ]; then
  echo "HTML_STATUS=$html_status"
  echo "CSS_HREF=missing"
  exit 1
fi
case "$css" in
  http*) css_url="$css" ;;
  *) css_url="http://127.0.0.1:'"$port"'$css" ;;
esac
curl -fsS -D "'"$out_dir"'/web-css.headers" "$css_url" -o "'"$out_dir"'/web.css"
css_status="$(head -1 "'"$out_dir"'/web-css.headers")"
echo "HTML_STATUS=$html_status"
echo "CSS_HREF=$css"
echo "CSS_STATUS=$css_status"
' || true

run_cmd "Resolve fresh app path and metadata" bash -lc '
set -euo pipefail
build_dir="$(xcodebuild -scheme KnowYou -destination "platform=macOS" -showBuildSettings 2>/dev/null | awk -F= "/BUILT_PRODUCTS_DIR/ {gsub(/^[ \t]+|[ \t]+$/, \"\", \$2); print \$2; exit}")"
app="$build_dir/KnowYou.app"
test -d "$app"
echo "$app" > "'"$out_dir"'/fresh-app-path.txt"
test -f "$app/Contents/Resources/BuildMetadata.json"
cat "$app/Contents/Resources/BuildMetadata.json" > "'"$out_dir"'/BuildMetadata.json"
cat "'"$out_dir"'/BuildMetadata.json"
' || true

if [[ "$launch_app" -eq 1 ]]; then
  run_cmd "Launch fresh macOS app" bash "$skill_dir/scripts/verify_fresh_app_launch.sh" "$out_dir/fresh-app-path.txt" "$out_dir" || true
else
  skip_cmd "Launch fresh macOS app" 0
fi

if [[ "$run_claude" -eq 1 ]]; then
  select_claude_command
  if [[ "${#claude_cmd[@]}" -gt 0 ]]; then
    run_cmd "Claude CLI version" "${claude_cmd[@]}" --version || true
  else
    echo "Claude CLI unavailable: install claude or npm, or set KNOWYOU_CLAUDE_BIN" > "$out_dir/claude-cli-version.log"
    record "Claude CLI version" 1 "$out_dir/claude-cli-version.log"
  fi
  if [[ -f "$prompt_file" ]] && [[ "${#claude_cmd[@]}" -gt 0 ]]; then
    claude_prompt="$(cat "$prompt_file")

Worktree: $repo_root
Review packet directory: $out_dir

Review the current uncommitted diff in this worktree. Do not edit files."
    note "RUN Claude production review"
    claude_log="$out_dir/claude-review.log"
    if [[ "$dry_run" -eq 1 ]]; then
      echo "DRY RUN: claude -p <production-review-prompt>" > "$claude_log"
      touch "$out_dir/claude-review.md"
      record "Claude production review" 0 "$claude_log"
    else
      set +e
      "${claude_cmd[@]}" -p "$claude_prompt" --permission-mode dontAsk --max-budget-usd "$claude_budget_usd" \
        > "$out_dir/claude-review.md" 2> "$claude_log"
      claude_code=$?
      set -e
      record "Claude production review" "$claude_code" "$claude_log"
    fi
  else
    echo "Missing prompt file: $prompt_file" > "$out_dir/claude-review.log"
    record "Claude production review" 1 "$out_dir/claude-review.log"
  fi
else
  skip_cmd "Claude production review" 1
fi

write_report
note "Report: $report_file"
exit "$overall_status"
