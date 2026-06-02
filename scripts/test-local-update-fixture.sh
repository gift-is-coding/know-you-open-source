#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

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

temp_dir="$(mktemp -d)"
trap 'rm -rf "$temp_dir"' EXIT

fixture_dir="$temp_dir/update-feed"

KNOWYOU_LOCAL_UPDATE_DIR="$fixture_dir" \
KNOWYOU_LOCAL_UPDATE_PUBLIC_PATH="fixture-feed" \
KNOWYOU_LOCAL_UPDATE_VERSION="9.9.0" \
KNOWYOU_LOCAL_UPDATE_BUILD="9999" \
KNOWYOU_LOCAL_UPDATE_BASE_URL="http://127.0.0.1:8765" \
KNOWYOU_LOCAL_UPDATE_PUBLISHED_AT="2026-06-02T08:00:00Z" \
KNOWYOU_LOCAL_UPDATE_NOTES=$'本地 fake 更新\n\n- 更新胶囊应该出现\n- Sheet 应该显示完整更新内容' \
  "$repo_root/scripts/prepare-local-update-fixture.sh" >/dev/null

json_payload="$(cat "$fixture_dir/debug-update.json")"
appcast_xml="$(cat "$fixture_dir/appcast.xml")"

assert_contains "$json_payload" '"version": "9.9.0"' "debug json version"
assert_contains "$json_payload" '"publishedAt": "2026-06-02T08:00:00Z"' "debug json publishedAt"
assert_contains "$json_payload" '"downloadURL": "http://127.0.0.1:8765/fixture-feed/KnowYou-local-update-9.9.0.dmg"' "debug json download URL"
assert_contains "$json_payload" '更新胶囊应该出现' "debug json release notes"

assert_contains "$appcast_xml" '<title>KnowYou Local Debug 9.9.0</title>' "appcast title"
assert_contains "$appcast_xml" '<sparkle:version>9999</sparkle:version>' "appcast build version"
assert_contains "$appcast_xml" '<sparkle:shortVersionString>9.9.0</sparkle:shortVersionString>' "appcast marketing version"
assert_contains "$appcast_xml" 'url="http://127.0.0.1:8765/fixture-feed/KnowYou-local-update-9.9.0.dmg"' "appcast enclosure URL"
assert_contains "$appcast_xml" 'sparkle:edSignature="local-fixture-placeholder" length="1"' "appcast UI-only signature"
assert_contains "$appcast_xml" 'Sheet 应该显示完整更新内容' "appcast release notes"

fake_dmg="$temp_dir/fake.dmg"
printf 'fake dmg payload' >"$fake_dmg"

fake_signer="$temp_dir/sign_update"
cat >"$fake_signer" <<'SH'
#!/usr/bin/env bash
printf 'sparkle:edSignature="signed-fixture" length="%s"\n' "$(wc -c <"$1" | tr -d ' ')"
SH
chmod +x "$fake_signer"

signed_dir="$temp_dir/signed-feed"
KNOWYOU_LOCAL_UPDATE_DIR="$signed_dir" \
KNOWYOU_LOCAL_UPDATE_PUBLIC_PATH="signed-feed" \
KNOWYOU_LOCAL_UPDATE_VERSION="10.0.0" \
KNOWYOU_LOCAL_UPDATE_BUILD="10000" \
KNOWYOU_LOCAL_UPDATE_BASE_URL="http://127.0.0.1:8765" \
KNOWYOU_LOCAL_UPDATE_PUBLISHED_AT="2026-06-02T09:00:00Z" \
KNOWYOU_LOCAL_UPDATE_DMG="$fake_dmg" \
KNOWYOU_SPARKLE_SIGN_UPDATE="$fake_signer" \
  "$repo_root/scripts/prepare-local-update-fixture.sh" >/dev/null

signed_appcast_xml="$(cat "$signed_dir/appcast.xml")"
assert_contains "$signed_appcast_xml" 'sparkle:edSignature="signed-fixture" length="16"' "signed appcast signature"
[[ -f "$signed_dir/KnowYou-local-update-10.0.0.dmg" ]] || {
  echo "Expected signed fixture DMG to be copied" >&2
  exit 1
}

echo "local update fixture tests passed"
