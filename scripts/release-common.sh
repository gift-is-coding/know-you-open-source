#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
project_path="$repo_root/KnowYou.xcodeproj"
scheme_name="${KNOWYOU_SCHEME:-KnowYou}"
release_dir="${KNOWYOU_RELEASE_DIR:-$repo_root/build/release}"
archive_path="${KNOWYOU_ARCHIVE_PATH:-$release_dir/KnowYou.xcarchive}"
app_path="${KNOWYOU_APP_PATH:-$release_dir/KnowYou.app}"
notary_profile="${KNOWYOU_NOTARY_PROFILE:-know-you-notary}"
developer_team="${KNOWYOU_DEVELOPER_TEAM:-3DY726RPHL}"
developer_id_identity="${KNOWYOU_DEVELOPER_ID_IDENTITY:-Developer ID Application: danhu ouyang (3DY726RPHL)}"

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

build_setting() {
  local key="$1"
  xcodebuild -project "$project_path" -scheme "$scheme_name" -configuration Release -showBuildSettings \
    | awk -F ' = ' -v key="$key" '$1 ~ ("^[[:space:]]*" key "$") { print $2; exit }'
}

marketing_version() {
  if [[ -n "${KNOWYOU_RELEASE_MARKETING_VERSION:-}" ]]; then
    printf '%s\n' "$KNOWYOU_RELEASE_MARKETING_VERSION"
    return
  fi

  build_setting "MARKETING_VERSION"
}

build_number() {
  if [[ -n "${KNOWYOU_RELEASE_BUILD_NUMBER:-}" ]]; then
    printf '%s\n' "$KNOWYOU_RELEASE_BUILD_NUMBER"
    return
  fi

  build_setting "CURRENT_PROJECT_VERSION"
}

artifact_basename() {
  printf 'KnowYou-%s-%s\n' "$(marketing_version)" "$(build_number)"
}

release_zip_path() {
  printf '%s/%s.zip\n' "$release_dir" "$(artifact_basename)"
}

notarized_zip_path() {
  printf '%s/%s-notarized.zip\n' "$release_dir" "$(artifact_basename)"
}

ensure_file_exists() {
  local path="$1"
  [[ -e "$path" ]] || {
    echo "Expected file not found: $path" >&2
    exit 1
  }
}

ensure_notary_profile() {
  if ! xcrun notarytool history --keychain-profile "$notary_profile" >/dev/null 2>&1; then
    echo "Missing notarytool keychain profile: $notary_profile" >&2
    echo "Store it first with xcrun notarytool store-credentials." >&2
    exit 1
  fi
}

prepare_release_dir() {
  mkdir -p "$release_dir"
}
