#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
target_root="$repo_root"
gitleaks_bin="${GITLEAKS_BIN:-}"
skip_gitleaks=false

usage() {
  cat <<'EOF'
Usage: scripts/verify-public-repo.sh [options]

Options:
  --root PATH             Public repository or staged export to verify.
  --gitleaks-bin PATH     Gitleaks executable. Defaults to GITLEAKS_BIN or PATH.
  --skip-gitleaks         Skip content scanning with an explicit warning.
  -h, --help              Show this help.
EOF
}

fail() {
  echo "Public repository verification failed: $*" >&2
  exit 1
}

trim_config_line() {
  local value="$1"
  value="${value%%#*}"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s\n' "$value"
}

validate_relative_path() {
  local value="$1"
  local label="$2"

  [[ -n "$value" ]] || fail "$label must not be empty"
  [[ "$value" != /* ]] || fail "$label must be repository-relative: $value"
  case "$value" in
    .|./*|*/./*|*//*) fail "$label must use a canonical repository-relative path: $value" ;;
  esac
  case "/$value/" in
    */../*) fail "$label must not contain '..': $value" ;;
  esac
  case "$value" in
    *'*'*|*'?'*|*'['*) fail "$label must not contain glob syntax: $value" ;;
  esac
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root)
      [[ $# -ge 2 ]] || fail '--root requires a path'
      target_root="$2"
      shift 2
      ;;
    --gitleaks-bin)
      [[ $# -ge 2 ]] || fail '--gitleaks-bin requires a path'
      gitleaks_bin="$2"
      shift 2
      ;;
    --skip-gitleaks)
      skip_gitleaks=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *) fail "unknown option: $1" ;;
  esac
done

[[ -d "$target_root" ]] || fail "root directory does not exist: $target_root"
target_root="$(cd "$target_root" && pwd -P)"

required_files=(
  README.md
  LICENSE
  SECURITY.md
  TERMS.md
  THIRD_PARTY_NOTICES.md
  .gitleaks.toml
  .gitleaksignore
  config/public-files.txt
  config/public-deny-paths.txt
)
for required_file in "${required_files[@]}"; do
  [[ -f "$target_root/$required_file" ]] || fail "missing required file: $required_file"
done

grep -Fq 'GNU GENERAL PUBLIC LICENSE' "$target_root/LICENSE" \
  || fail 'LICENSE is not the GNU General Public License'
grep -Fq 'Version 3, 29 June 2007' "$target_root/LICENSE" \
  || fail 'LICENSE is not GPL version 3'

deny_paths=()
while IFS= read -r raw_line || [[ -n "$raw_line" ]]; do
  deny_path="$(trim_config_line "$raw_line")"
  [[ -n "$deny_path" ]] || continue
  validate_relative_path "$deny_path" 'deny path'
  deny_paths+=("${deny_path%/}")
done <"$target_root/config/public-deny-paths.txt"
[[ ${#deny_paths[@]} -gt 0 ]] || fail 'deny path configuration must not be empty'

mandatory_deny_paths=(
  docs/investor-pitch
  docs/fundraising
)
for mandatory_deny_path in "${mandatory_deny_paths[@]}"; do
  found=false
  for deny_path in "${deny_paths[@]}"; do
    if [[ "$deny_path" == "$mandatory_deny_path" ]]; then
      found=true
      break
    fi
  done
  [[ "$found" == true ]] || fail "mandatory deny path is missing: $mandatory_deny_path"
done

allow_paths=()
while IFS= read -r raw_line || [[ -n "$raw_line" ]]; do
  allow_path="$(trim_config_line "$raw_line")"
  [[ -n "$allow_path" ]] || continue
  validate_relative_path "$allow_path" 'allowlist path'
  allow_path="${allow_path%/}"
  for deny_path in "${deny_paths[@]}"; do
    if [[ "$allow_path" == "$deny_path" \
      || "$allow_path" == "$deny_path/"* \
      || "$deny_path" == "$allow_path/"* ]]; then
      fail "allowlist overlaps denied path: $allow_path <-> $deny_path"
    fi
  done
  allow_paths+=("$allow_path")
done <"$target_root/config/public-files.txt"
[[ ${#allow_paths[@]} -gt 0 ]] || fail 'public allowlist must not be empty'

while IFS= read -r -d '' absolute_path; do
  relative_path="${absolute_path#"$target_root"/}"
  [[ "$relative_path" != '.git' && "$relative_path" != .git/* ]] || continue

  for deny_path in "${deny_paths[@]}"; do
    if [[ "$relative_path" == "$deny_path" || "$relative_path" == "$deny_path/"* ]]; then
      fail "denied path is present: $relative_path"
    fi
  done

  if [[ -f "$absolute_path" || -L "$absolute_path" ]]; then
    allowed=false
    if [[ "$relative_path" == '.public-sync/source.json' ]]; then
      allowed=true
    else
      for allow_path in "${allow_paths[@]}"; do
        if [[ "$relative_path" == "$allow_path" || "$relative_path" == "$allow_path/"* ]]; then
          allowed=true
          break
        fi
      done
    fi
    [[ "$allowed" == true ]] || fail "unlisted path is present: $relative_path"
  fi

  [[ ! -L "$absolute_path" ]] || fail "symbolic link is present: $relative_path"
  [[ -f "$absolute_path" ]] || continue
  base_name="${relative_path##*/}"
  case "$base_name" in
    .env.example|Secrets.example.xcconfig) ;;
    .env|.env.*|Secrets.xcconfig|*.local.xcconfig|*.private.xcconfig|*.pem|*.key|*.p12|*.mobileprovision|*.keychain-db)
      fail "sensitive filename is present: $relative_path"
      ;;
  esac
done < <(find "$target_root" -path "$target_root/.git" -prune -o -mindepth 1 -print0)

if [[ "$skip_gitleaks" == true ]]; then
  echo 'WARNING: Gitleaks scan skipped by explicit request.' >&2
else
  if [[ -z "$gitleaks_bin" ]]; then
    gitleaks_bin="$(command -v gitleaks || true)"
  fi
  [[ -n "$gitleaks_bin" && -x "$gitleaks_bin" ]] \
    || fail 'gitleaks is required; install it, set GITLEAKS_BIN, or explicitly use --skip-gitleaks'
  (
    cd "$target_root"
    "$gitleaks_bin" dir . \
      --config "$target_root/.gitleaks.toml" \
      --gitleaks-ignore-path "$target_root/.gitleaksignore" \
      --redact \
      --no-banner
  )
fi

echo "Public repository verification passed: $target_root"
