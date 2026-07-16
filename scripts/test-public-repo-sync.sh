#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export_script="$repo_root/scripts/export-public-repo.sh"
history_script="$repo_root/scripts/create-public-history.sh"
verify_script="$repo_root/scripts/verify-public-repo.sh"
tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/knowyou-public-sync-test.XXXXXX")"
trap 'rm -rf "$tmp_root"' EXIT

fail() {
  echo "Assertion failed: $*" >&2
  exit 1
}

assert_file() {
  [[ -f "$1" ]] || fail "expected file: $1"
}

assert_absent() {
  [[ ! -e "$1" ]] || fail "expected path to be absent: $1"
}

assert_contains() {
  local file="$1"
  local expected="$2"
  grep -Fq "$expected" "$file" || fail "expected $file to contain: $expected"
}

expect_failure() {
  local label="$1"
  shift
  if "$@" >"$tmp_root/failure.stdout" 2>"$tmp_root/failure.stderr"; then
    fail "$label unexpectedly succeeded"
  fi
}

write_file() {
  local path="$1"
  local content="$2"
  mkdir -p "$(dirname "$path")"
  printf '%s\n' "$content" >"$path"
}

commit_all() {
  local repository="$1"
  local message="$2"
  git -C "$repository" add .
  git -C "$repository" \
    -c user.name='Public Sync Test' \
    -c user.email="${PUBLIC_SYNC_TEST_EMAIL:-public-sync@example.invalid}" \
    commit -q -m "$message"
}

source_repo="$tmp_root/private"
public_repo="$tmp_root/public"
mkdir -p "$source_repo" "$public_repo"
git -C "$source_repo" init -q -b main
git -C "$public_repo" init -q -b main

write_file "$source_repo/README.md" '# Fixture'
write_file "$source_repo/LICENSE" $'GNU GENERAL PUBLIC LICENSE\nVersion 3, 29 June 2007'
write_file "$source_repo/SECURITY.md" '# Security'
write_file "$source_repo/TERMS.md" '# Terms'
write_file "$source_repo/THIRD_PARTY_NOTICES.md" '# Notices'
write_file "$source_repo/.gitleaks.toml" $'title = "Fixture"\n[extend]\nuseDefault = true'
write_file "$source_repo/.gitleaksignore" '# no fixture exceptions'
write_file "$source_repo/.gitattributes" 'KnowYou/app.txt export-ignore'
write_file "$source_repo/KnowYou/app.txt" 'public app source'
write_file "$source_repo/docs/agent-guide.md" 'public agent guide'
write_file "$source_repo/docs/investor-pitch/private.txt" 'private investor material'
write_file "$source_repo/docs/fundraising/private.txt" 'private fundraising material'
write_file "$source_repo/private-notes.txt" 'unlisted private material'
write_file "$source_repo/config/public-files.txt" $'.gitattributes\n.gitleaks.toml\n.gitleaksignore\nREADME.md\nLICENSE\nSECURITY.md\nTERMS.md\nTHIRD_PARTY_NOTICES.md\nKnowYou\ndocs/agent-guide.md\nconfig/public-files.txt\nconfig/public-deny-paths.txt'
write_file "$source_repo/config/public-deny-paths.txt" $'docs/investor-pitch\ndocs/fundraising'
write_file "$source_repo/config/public-history-author-map.txt" \
  'private-author@example.com 12345+public-author@users.noreply.github.com'
export PUBLIC_SYNC_TEST_EMAIL='private-author@example.com'
commit_all "$source_repo" 'fixture source'
unset PUBLIC_SYNC_TEST_EMAIL
source_commit="$(git -C "$source_repo" rev-parse HEAD)"

write_file "$public_repo/obsolete.txt" 'remove me during sync'
commit_all "$public_repo" 'public baseline'

fake_gitleaks="$tmp_root/fake-gitleaks"
write_file "$fake_gitleaks" $'#!/usr/bin/env bash\nset -euo pipefail\ncase "$1" in dir|git) ;; *) exit 70 ;; esac\nroot="$2"\n[[ "$1" != dir || "$root" == . ]] || exit 72\n[[ "${FAKE_GITLEAKS_FAIL:-0}" != "1" ]] || exit 71\nprintf "%s:%s\\n" "$1" "$root" >> "${FAKE_GITLEAKS_LOG:?}"'
chmod +x "$fake_gitleaks"
export FAKE_GITLEAKS_LOG="$tmp_root/gitleaks.log"

"$export_script" \
  --source-repo "$source_repo" \
  --source-ref main \
  --destination "$public_repo" \
  --branch sync/test \
  --commit \
  --gitleaks-bin "$fake_gitleaks"

[[ "$(git -C "$public_repo" branch --show-current)" == 'sync/test' ]] || fail 'sync branch was not selected'
[[ -z "$(git -C "$public_repo" status --porcelain)" ]] || fail 'public repository is dirty after committed sync'
assert_file "$public_repo/KnowYou/app.txt"
assert_file "$public_repo/docs/agent-guide.md"
assert_file "$public_repo/.public-sync/source.json"
assert_absent "$public_repo/obsolete.txt"
assert_absent "$public_repo/private-notes.txt"
assert_absent "$public_repo/docs/investor-pitch"
assert_absent "$public_repo/docs/fundraising"
assert_contains "$public_repo/.public-sync/source.json" "\"source_commit\": \"$source_commit\""
[[ "$(git -C "$public_repo" log -1 --format=%s)" == "sync: private ${source_commit:0:12}" ]] || fail 'unexpected sync commit subject'
[[ "$(git -C "$public_repo" log -1 --format=%B)" == *"Public-Source-Commit: $source_commit"* ]] || fail 'sync commit is missing source SHA trailer'
[[ "$(wc -l <"$FAKE_GITLEAKS_LOG" | tr -d ' ')" == '1' ]] || fail 'gitleaks did not run exactly once'

commit_count="$(git -C "$public_repo" rev-list --count HEAD)"
"$export_script" \
  --source-repo "$source_repo" \
  --source-ref main \
  --destination "$public_repo" \
  --commit \
  --gitleaks-bin "$fake_gitleaks"
[[ "$(git -C "$public_repo" rev-list --count HEAD)" == "$commit_count" ]] || fail 'no-op sync created a commit'

history_repo="$tmp_root/public-history"
"$history_script" \
  --source-repo "$source_repo" \
  --source-branch main \
  --destination "$history_repo" \
  --gitleaks-bin "$fake_gitleaks"
assert_file "$history_repo/.public-sync/source.json"
assert_absent "$history_repo/docs/investor-pitch"
assert_absent "$history_repo/docs/fundraising"
[[ -z "$(git -C "$history_repo" log --all --format=%H -- docs/investor-pitch docs/fundraising)" ]] \
  || fail 'denied paths remain reachable in sanitized history'
[[ -z "$(git -C "$history_repo" log --all --format=%H -- private-notes.txt)" ]] \
  || fail 'unlisted path remains reachable in sanitized history'
[[ -z "$(git -C "$history_repo" log --all --format='%ae%n%ce' | grep -Fx 'private-author@example.com' || true)" ]] \
  || fail 'private author email remains reachable in sanitized history'
git -C "$history_repo" log --all --format='%ae%n%ce' \
  | grep -Fxq '12345+public-author@users.noreply.github.com' \
  || fail 'public noreply author email was not written into sanitized history'
assert_absent "$history_repo/config/public-history-author-map.txt"
[[ -z "$(git -C "$history_repo" remote)" ]] || fail 'sanitized history retained the private remote'
[[ -z "$(git -C "$history_repo" status --porcelain)" ]] || fail 'sanitized history repository is dirty'

write_file "$public_repo/local-change.txt" 'do not destroy'
expect_failure 'dirty destination guard' \
  "$export_script" --source-repo "$source_repo" --destination "$public_repo" --gitleaks-bin "$fake_gitleaks"
assert_file "$public_repo/local-change.txt"
rm "$public_repo/local-change.txt"

write_file "$source_repo/config/public-files.txt" $'.gitleaks.toml\n.gitleaksignore\nREADME.md\nLICENSE\nSECURITY.md\nTERMS.md\nTHIRD_PARTY_NOTICES.md\nKnowYou\ndocs/agent-guide.md\ndocs/investor-pitch\nconfig/public-files.txt\nconfig/public-deny-paths.txt'
commit_all "$source_repo" 'attempt denied export'
expect_failure 'allowlist and denylist overlap' \
  "$export_script" --source-repo "$source_repo" --destination "$public_repo" --gitleaks-bin "$fake_gitleaks"
assert_absent "$public_repo/docs/investor-pitch"

write_file "$source_repo/config/public-files.txt" $'.gitleaks.toml\n.gitleaksignore\nREADME.md\nLICENSE\nSECURITY.md\nTERMS.md\nTHIRD_PARTY_NOTICES.md\n../outside\nconfig/public-files.txt\nconfig/public-deny-paths.txt'
commit_all "$source_repo" 'attempt unsafe allowlist path'
expect_failure 'unsafe allowlist path' \
  "$export_script" --source-repo "$source_repo" --destination "$public_repo" --gitleaks-bin "$fake_gitleaks"

verification_fixture="$tmp_root/verification-fixture"
mkdir -p "$verification_fixture/config"
write_file "$verification_fixture/README.md" '# Fixture'
write_file "$verification_fixture/LICENSE" $'GNU GENERAL PUBLIC LICENSE\nVersion 3, 29 June 2007'
write_file "$verification_fixture/SECURITY.md" '# Security'
write_file "$verification_fixture/TERMS.md" '# Terms'
write_file "$verification_fixture/THIRD_PARTY_NOTICES.md" '# Notices'
write_file "$verification_fixture/.gitleaks.toml" $'title = "Fixture"\n[extend]\nuseDefault = true'
write_file "$verification_fixture/.gitleaksignore" '# no fixture exceptions'
write_file "$verification_fixture/config/public-files.txt" $'.gitleaks.toml\n.gitleaksignore\nREADME.md\nLICENSE\nSECURITY.md\nTERMS.md\nTHIRD_PARTY_NOTICES.md\nconfig/public-files.txt\nconfig/public-deny-paths.txt\nprivate.pem\nexternal-link'
write_file "$verification_fixture/config/public-deny-paths.txt" $'docs/investor-pitch\ndocs/fundraising'
"$verify_script" --root "$verification_fixture" --gitleaks-bin "$fake_gitleaks"

write_file "$verification_fixture/config/public-deny-paths.txt" 'docs/investor-pitch'
expect_failure 'mandatory deny path verification' \
  "$verify_script" --root "$verification_fixture" --gitleaks-bin "$fake_gitleaks"
write_file "$verification_fixture/config/public-deny-paths.txt" $'docs/investor-pitch\ndocs/fundraising'

write_file "$verification_fixture/unlisted.txt" 'must fail'
expect_failure 'unlisted path verification' \
  "$verify_script" --root "$verification_fixture" --gitleaks-bin "$fake_gitleaks"
rm "$verification_fixture/unlisted.txt"

write_file "$verification_fixture/docs/fundraising/private.txt" 'must fail'
expect_failure 'denied path verification' \
  "$verify_script" --root "$verification_fixture" --gitleaks-bin "$fake_gitleaks"
rm -rf "$verification_fixture/docs"

write_file "$verification_fixture/private.pem" 'must fail'
expect_failure 'sensitive filename verification' \
  "$verify_script" --root "$verification_fixture" --gitleaks-bin "$fake_gitleaks"
rm "$verification_fixture/private.pem"

ln -s /etc/passwd "$verification_fixture/external-link"
expect_failure 'symbolic link verification' \
  "$verify_script" --root "$verification_fixture" --gitleaks-bin "$fake_gitleaks"
rm "$verification_fixture/external-link"

export FAKE_GITLEAKS_FAIL=1
expect_failure 'gitleaks failure propagation' \
  "$verify_script" --root "$verification_fixture" --gitleaks-bin "$fake_gitleaks"
unset FAKE_GITLEAKS_FAIL

echo 'public repository sync tests passed'
