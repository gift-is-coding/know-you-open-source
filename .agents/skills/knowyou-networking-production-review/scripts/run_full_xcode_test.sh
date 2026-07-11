#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
temp_root="${TMPDIR:-/tmp}"

# SIGKILL cannot trigger traps. Remove only stale mirrors so concurrent test
# runs keep their isolated workspace.
find "$temp_root" -maxdepth 1 -type d \
  -name 'knowyou-networking-full-test.*' -mtime +1 -exec rm -rf {} +

mirror="$(mktemp -d "$temp_root/knowyou-networking-full-test.XXXXXX")"
trap 'rm -rf "$mirror"' EXIT INT TERM

# macOS can block an ad-hoc-signed XCTest host from reading source fixtures
# under ~/Documents. Test the exact current workspace snapshot outside that
# privacy boundary without copying local credentials or generated artifacts.
rsync -a \
  --exclude '.git' \
  --exclude '.knowyou' \
  --exclude '.env*' \
  --exclude '.derived-data' \
  --exclude 'build' \
  --exclude 'NetworkingWeb/.next' \
  --exclude 'NetworkingWeb/node_modules' \
  "$repo_root/" "$mirror/"

cd "$mirror"
xcodebuild test \
  -scheme KnowYou \
  -destination 'platform=macOS' \
  -derivedDataPath "$mirror/.derived-data" \
  -parallel-testing-enabled YES \
  -parallel-testing-worker-count 3 \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY=
