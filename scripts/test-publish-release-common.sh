#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

export KNOWYOU_RELEASE_MARKETING_VERSION="1.0.2"
export KNOWYOU_RELEASE_BUILD_NUMBER="2"
export KNOWYOU_RELEASE_REPO_BUILD_NUMBER="116"
export KNOWYOU_RELEASE_REPO_COMMIT="c2f294c"
export KNOWYOU_RELEASE_DATE="2026-04-21"

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

assert_eq "116" "$(release_repo_build_number)" "release_repo_build_number"
assert_eq "v1.0.2-build116" "$(download_release_tag)" "download_release_tag"
assert_eq "KnowYou v1.0.2 (116)" "$(download_release_title)" "download_release_title"
assert_eq "KnowYou-1.0.2-2-notarized.zip.sha256" "$(checksum_asset_name)" "checksum_asset_name"

expected_url="https://github.com/gift-is-coding/know-you-downloads/releases/download/v1.0.2-build116/KnowYou-1.0.2-2-notarized.zip"
assert_eq "$expected_url" "$(download_asset_url)" "download_asset_url"

notes="$(release_notes_body)"
assert_contains "$notes" "- Version: 1.0.2" "release_notes version"
assert_contains "$notes" "- Build: 116" "release_notes build"
assert_contains "$notes" "- Commit: c2f294c" "release_notes commit"
assert_contains "$notes" "- Artifact: KnowYou-1.0.2-2-notarized.zip" "release_notes artifact"
assert_contains "$notes" "- Notarization: Accepted on 2026-04-21" "release_notes notarization date"

temp_dir="$(mktemp -d)"
trap 'rm -rf "$temp_dir"' EXIT
index_path="$temp_dir/index.html"

cat >"$index_path" <<'EOF'
<a class="btn btn-primary" href="https://github.com/gift-is-coding/know-you-downloads/releases/download/v1.0.0-build109/KnowYou-macOS-v1.0-build1-3c05f40.zip">Download for macOS</a>
<a class="btn btn-secondary" href="https://github.com/gift-is-coding/know-you-downloads/releases/tag/v1.0.0-build109">Release notes</a>
<div class="metric">
  <div class="metric-label">Version</div>
  <div class="metric-value">1.0 (109)</div>
</div>
<div class="metric">
  <div class="metric-label">Commit</div>
  <div class="metric-value"><code>3c05f40</code></div>
</div>
<div class="metric">
  <div class="metric-label">Artifact</div>
  <div class="metric-value">6.1 MB zip</div>
</div>
<div class="metric">
  <div class="metric-label">SHA-256</div>
  <div class="metric-value"><code>76720050f283a1103e0e2a73aefe42845cc8a83cbb4f68bdd33563dc79098998</code></div>
</div>
<div class="notice">
  This build is signed but not notarized with a Developer ID certificate yet. On first launch, macOS may warn that the app cannot be verified.
</div>
EOF

update_download_index_html "$index_path" "6.4 MB zip" "4773fe766ab2ae074b8bab946e57f1ca4bef41590f34d9a7b0c4e0fba7df41f0"

updated_html="$(cat "$index_path")"
assert_contains "$updated_html" "v1.0.2-build116/KnowYou-1.0.2-2-notarized.zip" "index primary download"
assert_contains "$updated_html" "releases/tag/v1.0.2-build116" "index release notes"
assert_contains "$updated_html" ">1.0.2 (116)<" "index version"
assert_contains "$updated_html" "<code>c2f294c</code>" "index commit"
assert_contains "$updated_html" ">6.4 MB zip<" "index size"
assert_contains "$updated_html" "<code>4773fe766ab2ae074b8bab946e57f1ca4bef41590f34d9a7b0c4e0fba7df41f0</code>" "index checksum"
assert_contains "$updated_html" "signed with Developer ID, notarized by Apple, and stapled" "index notice"

echo "publish-release helper tests passed"
