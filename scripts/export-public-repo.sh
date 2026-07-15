#!/usr/bin/env bash

set -euo pipefail

tool_repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_repo="$tool_repo_root"
source_ref='HEAD'
destination=''
sync_branch=''
create_commit=false
gitleaks_bin="${GITLEAKS_BIN:-}"
skip_gitleaks=false

usage() {
  cat <<'EOF'
Usage: scripts/export-public-repo.sh --destination PATH [options]

Exports a committed, allowlisted snapshot into a clean public Git checkout.
The script never pushes or force-pushes.

Options:
  --source-repo PATH      Private source repository. Defaults to this repository.
  --source-ref REF        Committed source ref to export. Defaults to HEAD.
  --destination PATH      Existing clean public Git checkout to replace.
  --branch NAME           Create or reuse this public sync branch (requires --commit).
  --commit                Commit the exported snapshot and source SHA mapping.
  --gitleaks-bin PATH     Gitleaks executable. Defaults to GITLEAKS_BIN or PATH.
  --skip-gitleaks         Skip Gitleaks with an explicit warning.
  -h, --help              Show this help.
EOF
}

fail() {
  echo "Public repository export failed: $*" >&2
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
    --source-repo)
      [[ $# -ge 2 ]] || fail '--source-repo requires a path'
      source_repo="$2"
      shift 2
      ;;
    --source-ref)
      [[ $# -ge 2 ]] || fail '--source-ref requires a ref'
      source_ref="$2"
      shift 2
      ;;
    --destination)
      [[ $# -ge 2 ]] || fail '--destination requires a path'
      destination="$2"
      shift 2
      ;;
    --branch)
      [[ $# -ge 2 ]] || fail '--branch requires a name'
      sync_branch="$2"
      shift 2
      ;;
    --commit)
      create_commit=true
      shift
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
[[ -d "$source_repo" ]] || fail "source repository does not exist: $source_repo"
source_repo="$(git -C "$source_repo" rev-parse --show-toplevel 2>/dev/null)" \
  || fail "source is not a Git repository: $source_repo"
source_repo="$(cd "$source_repo" && pwd -P)"
source_commit="$(git -C "$source_repo" rev-parse --verify "$source_ref^{commit}" 2>/dev/null)" \
  || fail "source ref is not a commit: $source_ref"
source_short="${source_commit:0:12}"

[[ -d "$destination" ]] || fail "destination does not exist: $destination"
destination="$(cd "$destination" && pwd -P)"
[[ "$destination" != "$source_repo" ]] || fail 'source and destination repositories must be different'
destination_root="$(git -C "$destination" rev-parse --show-toplevel 2>/dev/null)" \
  || fail "destination is not a Git repository: $destination"
destination_root="$(cd "$destination_root" && pwd -P)"
[[ "$destination_root" == "$destination" ]] \
  || fail 'destination must be the root of its Git checkout'
[[ -z "$(git -C "$destination" status --porcelain --untracked-files=all)" ]] \
  || fail 'destination Git checkout must be clean'

if [[ -n "$sync_branch" ]]; then
  [[ "$create_commit" == true ]] || fail '--branch requires --commit'
  git check-ref-format --branch "$sync_branch" >/dev/null 2>&1 \
    || fail "invalid sync branch name: $sync_branch"
  if git -C "$destination" show-ref --verify --quiet "refs/heads/$sync_branch"; then
    [[ "$(git -C "$destination" branch --show-current)" == "$sync_branch" ]] \
      || fail "sync branch already exists but is not checked out: $sync_branch"
  fi
fi

tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/knowyou-public-export.XXXXXX")"
trap 'rm -rf "$tmp_root"' EXIT
allow_file="$tmp_root/public-files.txt"
deny_file="$tmp_root/public-deny-paths.txt"
staging_root="$tmp_root/staging"
mkdir -p "$staging_root"

git -C "$source_repo" show "$source_commit:config/public-files.txt" >"$allow_file" \
  || fail 'source ref is missing config/public-files.txt'
git -C "$source_repo" show "$source_commit:config/public-deny-paths.txt" >"$deny_file" \
  || fail 'source ref is missing config/public-deny-paths.txt'

deny_paths=()
while IFS= read -r raw_line || [[ -n "$raw_line" ]]; do
  deny_path="$(trim_config_line "$raw_line")"
  [[ -n "$deny_path" ]] || continue
  validate_relative_path "$deny_path" 'deny path'
  deny_paths+=("${deny_path%/}")
done <"$deny_file"
[[ ${#deny_paths[@]} -gt 0 ]] || fail 'deny path configuration must not be empty'

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

  git -C "$source_repo" cat-file -e "$source_commit:$allow_path" 2>/dev/null \
    || fail "allowlist path does not exist at $source_ref: $allow_path"
  allow_paths+=("$allow_path")
done <"$allow_file"
[[ ${#allow_paths[@]} -gt 0 ]] || fail 'public allowlist must not be empty'

export_index="$tmp_root/public-export.index"
GIT_INDEX_FILE="$export_index" git -C "$source_repo" read-tree "$source_commit"
GIT_INDEX_FILE="$export_index" git -C "$source_repo" ls-files -z \
  | while IFS= read -r -d '' tracked_path; do
      keep=false

      for deny_path in "${deny_paths[@]}"; do
        if [[ "$tracked_path" == "$deny_path" || "$tracked_path" == "$deny_path/"* ]]; then
          printf '%s\0' "$tracked_path"
          continue 2
        fi
      done

      for allow_path in "${allow_paths[@]}"; do
        if [[ "$tracked_path" == "$allow_path" || "$tracked_path" == "$allow_path/"* ]]; then
          keep=true
          break
        fi
      done

      if [[ "$keep" != true ]]; then
        printf '%s\0' "$tracked_path"
      fi
    done \
  | GIT_INDEX_FILE="$export_index" git -C "$source_repo" update-index -z --force-remove --stdin
GIT_INDEX_FILE="$export_index" git -C "$source_repo" checkout-index \
  --all \
  --force \
  --prefix="$staging_root/"

mkdir -p "$staging_root/.public-sync"
printf '{\n  "schema_version": 1,\n  "source_commit": "%s"\n}\n' \
  "$source_commit" >"$staging_root/.public-sync/source.json"

verify_args=(--root "$staging_root")
if [[ -n "$gitleaks_bin" ]]; then
  verify_args+=(--gitleaks-bin "$gitleaks_bin")
fi
if [[ "$skip_gitleaks" == true ]]; then
  verify_args+=(--skip-gitleaks)
fi
"$tool_repo_root/scripts/verify-public-repo.sh" "${verify_args[@]}"

if [[ -n "$sync_branch" ]] \
  && ! git -C "$destination" show-ref --verify --quiet "refs/heads/$sync_branch"; then
  git -C "$destination" switch -c "$sync_branch"
fi

find "$destination" -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +
tar -C "$staging_root" -cf - . | tar -C "$destination" -xf -

if [[ "$create_commit" == true ]]; then
  git -C "$destination" add -A
  if git -C "$destination" diff --cached --quiet; then
    echo "Public repository already matches private source $source_short; no commit created."
    exit 0
  fi

  git -C "$destination" \
    -c user.name="${PUBLIC_SYNC_GIT_NAME:-KnowYou Public Sync}" \
    -c user.email="${PUBLIC_SYNC_GIT_EMAIL:-public-sync@users.noreply.github.com}" \
    commit \
    -m "sync: private $source_short" \
    -m "Public-Source-Commit: $source_commit"
  public_commit="$(git -C "$destination" rev-parse HEAD)"
  echo "Created public sync commit $public_commit from private source $source_commit."
else
  echo "Exported private source $source_commit to $destination without committing."
fi
