#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_repo="$repo_root"
source_branch='main'
destination=''
gitleaks_bin="${GITLEAKS_BIN:-}"
skip_gitleaks=false

usage() {
  cat <<'EOF'
Usage: scripts/create-public-history.sh --destination PATH [options]

Creates a new local public-history repository from a private source branch.
The destination must not exist. The source repository is never rewritten, and
the resulting repository has no remote configured and is never pushed.

Options:
  --source-repo PATH      Private source repository. Defaults to this repository.
  --source-branch NAME    Private branch to sanitize. Defaults to main.
  --destination PATH      New local directory for the sanitized repository.
  --gitleaks-bin PATH     Gitleaks executable. Defaults to GITLEAKS_BIN or PATH.
  --skip-gitleaks         Skip Gitleaks with an explicit warning.
  -h, --help              Show this help.
EOF
}

fail() {
  echo "Public history creation failed: $*" >&2
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
  [[ -n "$value" ]] || fail 'deny path must not be empty'
  [[ "$value" != /* ]] || fail "deny path must be repository-relative: $value"
  case "$value" in
    .|./*|*/./*|*//*) fail "deny path must use a canonical repository-relative path: $value" ;;
  esac
  case "/$value/" in
    */../*) fail "deny path must not contain '..': $value" ;;
  esac
  case "$value" in
    *'*'*|*'?'*|*'['*) fail "deny path must not contain glob syntax: $value" ;;
  esac
}

filter_index_for_public_history() {
  local allow_config="${PUBLIC_HISTORY_ALLOW_FILE:?}"
  local deny_config="${PUBLIC_HISTORY_DENY_FILE:?}"
  local tracked_path
  local allow_path
  local deny_path
  local keep

  git ls-files -z | while IFS= read -r -d '' tracked_path; do
    keep=false

    while IFS= read -r deny_path || [[ -n "$deny_path" ]]; do
      [[ -n "$deny_path" ]] || continue
      if [[ "$tracked_path" == "$deny_path" || "$tracked_path" == "$deny_path/"* ]]; then
        printf '%s\0' "$tracked_path"
        continue 2
      fi
    done <"$deny_config"

    while IFS= read -r allow_path || [[ -n "$allow_path" ]]; do
      [[ -n "$allow_path" ]] || continue
      if [[ "$tracked_path" == "$allow_path" || "$tracked_path" == "$allow_path/"* ]]; then
        keep=true
        break
      fi
    done <"$allow_config"

    if [[ "$keep" != true ]]; then
      printf '%s\0' "$tracked_path"
    fi
  done | git update-index -z --force-remove --stdin
}

if [[ "${1:-}" == '__filter-index' ]]; then
  filter_index_for_public_history
  exit 0
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source-repo)
      [[ $# -ge 2 ]] || fail '--source-repo requires a path'
      source_repo="$2"
      shift 2
      ;;
    --source-branch)
      [[ $# -ge 2 ]] || fail '--source-branch requires a name'
      source_branch="$2"
      shift 2
      ;;
    --destination)
      [[ $# -ge 2 ]] || fail '--destination requires a path'
      destination="$2"
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

[[ -n "$destination" ]] || fail '--destination is required'
[[ ! -e "$destination" ]] || fail "destination already exists: $destination"
[[ -d "$source_repo" ]] || fail "source repository does not exist: $source_repo"
source_repo="$(git -C "$source_repo" rev-parse --show-toplevel 2>/dev/null)" \
  || fail "source is not a Git repository: $source_repo"
source_repo="$(cd "$source_repo" && pwd -P)"
git check-ref-format --branch "$source_branch" >/dev/null 2>&1 \
  || fail "invalid source branch name: $source_branch"
source_commit="$(git -C "$source_repo" rev-parse --verify "refs/heads/$source_branch^{commit}" 2>/dev/null)" \
  || fail "source branch does not exist locally: $source_branch"

tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/knowyou-public-history.XXXXXX")"
trap 'rm -rf "$tmp_root"' EXIT
deny_file="$tmp_root/public-deny-paths.txt"
allow_file="$tmp_root/public-files.txt"
git -C "$source_repo" show "$source_commit:config/public-files.txt" >"$allow_file" \
  || fail 'source branch is missing config/public-files.txt'
git -C "$source_repo" show "$source_commit:config/public-deny-paths.txt" >"$deny_file" \
  || fail 'source branch is missing config/public-deny-paths.txt'

deny_paths=()
while IFS= read -r raw_line || [[ -n "$raw_line" ]]; do
  deny_path="$(trim_config_line "$raw_line")"
  [[ -n "$deny_path" ]] || continue
  validate_relative_path "$deny_path"
  deny_paths+=("${deny_path%/}")
done <"$deny_file"
[[ ${#deny_paths[@]} -gt 0 ]] || fail 'deny path configuration must not be empty'

allow_paths=()
while IFS= read -r raw_line || [[ -n "$raw_line" ]]; do
  allow_path="$(trim_config_line "$raw_line")"
  [[ -n "$allow_path" ]] || continue
  validate_relative_path "$allow_path"
  allow_path="${allow_path%/}"
  for deny_path in "${deny_paths[@]}"; do
    if [[ "$allow_path" == "$deny_path" \
      || "$allow_path" == "$deny_path/"* \
      || "$deny_path" == "$allow_path/"* ]]; then
      fail "allowlist overlaps denied path: $allow_path <-> $deny_path"
    fi
  done
  allow_paths+=("$allow_path")
done <"$allow_file"
[[ ${#allow_paths[@]} -gt 0 ]] || fail 'public allowlist must not be empty'

normalized_allow_file="$tmp_root/public-files.normalized.txt"
normalized_deny_file="$tmp_root/public-deny-paths.normalized.txt"
printf '%s\n' "${allow_paths[@]}" >"$normalized_allow_file"
printf '%s\n' "${deny_paths[@]}" >"$normalized_deny_file"

git clone \
  --quiet \
  --no-local \
  --no-tags \
  --single-branch \
  --branch "$source_branch" \
  "$source_repo" \
  "$destination"
destination="$(cd "$destination" && pwd -P)"
git -C "$destination" remote remove origin
git -C "$destination" symbolic-ref -d refs/remotes/origin/HEAD 2>/dev/null || true
remote_refs="$(git -C "$destination" for-each-ref --format='%(refname)' refs/remotes/)"
if [[ -n "$remote_refs" ]]; then
  while IFS= read -r remote_ref; do
    [[ -n "$remote_ref" ]] || continue
    git -C "$destination" update-ref -d "$remote_ref"
  done <<<"$remote_refs"
fi

printf -v index_filter '%q %q' "$repo_root/scripts/create-public-history.sh" '__filter-index'
export PUBLIC_HISTORY_ALLOW_FILE="$normalized_allow_file"
export PUBLIC_HISTORY_DENY_FILE="$normalized_deny_file"

FILTER_BRANCH_SQUELCH_WARNING=1 \
  git -C "$destination" filter-branch \
    --force \
    --prune-empty \
    --index-filter "$index_filter" \
    -- --all >/dev/null

original_refs="$(git -C "$destination" for-each-ref --format='%(refname)' refs/original/)"
if [[ -n "$original_refs" ]]; then
  while IFS= read -r original_ref; do
    [[ -n "$original_ref" ]] || continue
    git -C "$destination" update-ref -d "$original_ref"
  done <<<"$original_refs"
fi
git -C "$destination" reflog expire --expire=now --all
git -C "$destination" gc --prune=now --quiet

reachable_denied_commits="$(git -C "$destination" log --all --format=%H -- "${deny_paths[@]}")"
[[ -z "$reachable_denied_commits" ]] \
  || fail 'one or more denied paths remain reachable after history rewrite'

export_args=(
  --source-repo "$source_repo"
  --source-ref "$source_branch"
  --destination "$destination"
  --commit
)
if [[ -n "$gitleaks_bin" ]]; then
  export_args+=(--gitleaks-bin "$gitleaks_bin")
fi
if [[ "$skip_gitleaks" == true ]]; then
  export_args+=(--skip-gitleaks)
fi
"$repo_root/scripts/export-public-repo.sh" "${export_args[@]}"

if [[ "$skip_gitleaks" == true ]]; then
  echo 'WARNING: public history Gitleaks scan skipped by explicit request.' >&2
else
  if [[ -z "$gitleaks_bin" ]]; then
    gitleaks_bin="$(command -v gitleaks || true)"
  fi
  [[ -n "$gitleaks_bin" && -x "$gitleaks_bin" ]] \
    || fail 'gitleaks is required for the public history scan'
  "$gitleaks_bin" git "$destination" \
    --config "$destination/.gitleaks.toml" \
    --gitleaks-ignore-path "$destination/.gitleaksignore" \
    --redact \
    --no-banner
fi

[[ -z "$(git -C "$destination" status --porcelain --untracked-files=all)" ]] \
  || fail 'sanitized public history repository is not clean'

echo "Created sanitized public history at $destination from private source $source_commit."
echo 'No remote was configured and nothing was pushed.'
