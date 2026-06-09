#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

export KNOWYOU_RELEASE_MARKETING_VERSION="1.2.3"
export KNOWYOU_RELEASE_BUILD_NUMBER="45"
export KNOWYOU_RELEASE_REPO_BUILD_NUMBER="145"
export KNOWYOU_RELEASE_DIR="$repo_root/build/test-release"

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

assert_eq "1.2.3" "$(marketing_version)" "marketing_version"
assert_eq "45" "$(build_number)" "build_number"
assert_eq "145" "$(release_repo_build_number)" "release_repo_build_number"
assert_eq "KnowYou-1.2.3-145" "$(artifact_basename)" "artifact_basename"
assert_eq "$repo_root/build/test-release/KnowYou-1.2.3-145.zip" "$(release_zip_path)" "release_zip_path"
assert_eq "$repo_root/build/test-release/KnowYou-1.2.3-145-notarized.zip" "$(notarized_zip_path)" "notarized_zip_path"
assert_eq "$repo_root/build/test-release/KnowYou-1.2.3-145.dmg" "$(release_dmg_path)" "release_dmg_path"

fake_derived_data_root="$KNOWYOU_RELEASE_DIR/fake-derived-data"
fake_sign_update="$fake_derived_data_root/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update"
mkdir -p "$(dirname "$fake_sign_update")" "$fake_derived_data_root/Build/Products"
touch "$fake_sign_update"
chmod +x "$fake_sign_update"
unset KNOWYOU_SPARKLE_SIGN_UPDATE
export KNOWYOU_RELEASE_BUILD_DIR_FOR_TESTING="$fake_derived_data_root/Build/Products"
assert_eq "$fake_sign_update" "$(resolve_sparkle_sign_update)" "resolve_sparkle_sign_update SwiftPM artifact fallback"
unset KNOWYOU_RELEASE_BUILD_DIR_FOR_TESTING

project_text="$(cat "$repo_root/KnowYou.xcodeproj/project.pbxproj")"
assert_contains "$project_text" 'INFOPLIST_FILE = KnowYou/Config/Info.plist;' "explicit app Info.plist"
assert_contains "$project_text" 'KNOWYOU_SPARKLE_PUBLIC_ED_KEY = "DPaKuqvU48UAoI0rOvKtWaStpzMsX9fwypStdx4md/M=";' "Sparkle public key setting"
assert_contains "$project_text" 'KNOWYOU_UPDATE_CHANNEL = direct;' "update channel setting"
assert_contains "$project_text" 'KNOWYOU_UPDATE_METADATA_URL = "https://raw.githubusercontent.com/gift-is-coding/know-you-downloads/main/update-feed/latest.json";' "release update metadata URL"
assert_contains "$project_text" 'KNOWYOU_UPDATE_METADATA_URL = "http://127.0.0.1:8765/Support/update-feed/debug-update.json";' "debug update metadata URL"
assert_contains "$project_text" 'KNOWYOU_SPARKLE_FEED_URL = "https://raw.githubusercontent.com/gift-is-coding/know-you-downloads/main/update-feed/appcast.xml";' "release Sparkle appcast URL"
assert_contains "$project_text" 'scripts/write-build-metadata.sh' "build metadata script path"

info_plist="$(cat "$repo_root/KnowYou/Config/Info.plist")"
assert_contains "$info_plist" '<key>KYUpdateMetadataURL</key>' "Info.plist update metadata key"
assert_contains "$info_plist" '<string>$(KNOWYOU_UPDATE_CHANNEL)</string>' "Info.plist update channel setting"
assert_contains "$info_plist" '<string>$(KNOWYOU_UPDATE_METADATA_URL)</string>' "Info.plist update metadata setting"
assert_contains "$info_plist" '<key>SUFeedURL</key>' "Info.plist Sparkle feed key"
assert_contains "$info_plist" '<string>$(KNOWYOU_SPARKLE_FEED_URL)</string>' "Info.plist Sparkle feed setting"
assert_contains "$info_plist" '<key>SUPublicEDKey</key>' "Info.plist Sparkle public key"

assert_eq "DPaKuqvU48UAoI0rOvKtWaStpzMsX9fwypStdx4md/M=" "$(sparkle_public_ed_key)" "sparkle_public_ed_key default"

build_metadata_script="$(cat "$repo_root/scripts/write-build-metadata.sh")"
assert_contains "$build_metadata_script" 'KYUpdateChannel' "build metadata script writes update channel"
assert_contains "$build_metadata_script" 'KYUpdateMetadataURL' "build metadata script writes update metadata URL"
assert_contains "$build_metadata_script" 'KNOWYOU_UPDATE_METADATA_URL' "build metadata script reads update metadata setting"

release_common_script="$(cat "$repo_root/scripts/release-common.sh")"
assert_contains "$release_common_script" 'sign_release_app_nested_code()' "release helper re-signs nested code"
assert_contains "$release_common_script" 'Sparkle.framework' "release helper targets Sparkle framework"
assert_contains "$release_common_script" 'XPCServices/Downloader.xpc' "release helper targets Sparkle downloader"
assert_contains "$release_common_script" 'XPCServices/Installer.xpc' "release helper targets Sparkle installer"
assert_contains "$release_common_script" 'Updater.app' "release helper targets Sparkle updater"
assert_contains "$release_common_script" 'sign_mywiki_runner_nested_code()' "release helper signs MyWikiRunner"
assert_contains "$release_common_script" 'Contents/Resources/MyWikiRunner/node' "release helper targets bundled MyWiki node"
assert_contains "$release_common_script" 'mywiki-runner-node.entitlements' "release helper applies MyWiki node entitlements"
assert_contains "$release_common_script" '--entitlements "$runner_node_entitlements"' "release helper signs MyWiki node with entitlements"
assert_contains "$release_common_script" '--preserve-metadata=identifier,entitlements,requirements' "release helper preserves signing metadata"

runner_node_entitlements="$(cat "$repo_root/scripts/mywiki-runner-node.entitlements")"
assert_contains "$runner_node_entitlements" 'com.apple.security.cs.allow-jit' "MyWiki node allows V8 JIT under hardened runtime"

build_release_script="$(cat "$repo_root/scripts/build-release.sh")"
assert_contains "$build_release_script" 'embed-mywiki-runner.sh" "$app_path"' "build release embeds MyWikiRunner through shared helper"
embed_mywiki_runner_script="$(cat "$repo_root/scripts/embed-mywiki-runner.sh")"
assert_contains "$embed_mywiki_runner_script" 'scripts/build-mywiki-runner.sh' "shared helper builds MyWikiRunner"
assert_contains "$embed_mywiki_runner_script" 'Contents/Resources/MyWikiRunner' "shared helper embeds into app resources"
assert_contains "$embed_mywiki_runner_script" 'Contents/Resources/KnowledgeOntology/LLM Wiki.app' "shared helper rejects LLM Wiki app"
assert_contains "$embed_mywiki_runner_script" 'Contents/Resources/MyWikiRunner' "shared helper copies MyWikiRunner"
assert_contains "$build_release_script" 'sign_mywiki_runner_nested_code "$app_path"' "build release signs MyWikiRunner"
assert_contains "$build_release_script" 'sign_release_app_nested_code "$app_path"' "build release signs app before zip"

install_new_user_script="$(cat "$repo_root/scripts/install-new-user-app.sh")"
assert_contains "$install_new_user_script" 'embed-mywiki-runner.sh" "$installed_app"' "new user install embeds MyWikiRunner"
assert_contains "$install_new_user_script" 'Contents/Resources/MyWikiRunner/node' "new user install verifies bundled MyWiki node"

run_dev_app_script="$(cat "$repo_root/scripts/run-dev-app.sh")"
assert_contains "$run_dev_app_script" 'embed-mywiki-runner.sh" "$app_path"' "dev launch embeds MyWikiRunner"
assert_contains "$run_dev_app_script" 'Contents/Resources/MyWikiRunner/node' "dev launch verifies bundled MyWiki node"

dmg_script="$(cat "$repo_root/scripts/build-dmg.sh")"
assert_contains "$dmg_script" 'Contents/Resources/MyWikiRunner/node' "DMG build rejects apps missing MyWikiRunner"

verify_release_script="$(cat "$repo_root/scripts/verify-release.sh")"
assert_contains "$verify_release_script" 'Contents/Resources/MyWikiRunner/node' "verify release requires bundled MyWiki node"
assert_contains "$verify_release_script" 'KnowledgeOntology/LLM Wiki.app' "verify release rejects LLM Wiki app"

mkdir -p "$KNOWYOU_RELEASE_DIR"
touch "$KNOWYOU_RELEASE_DIR/smoke.txt"
ensure_file_exists "$KNOWYOU_RELEASE_DIR/smoke.txt"

echo "release-common.sh tests passed"
