#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/scripts/release-common.sh"

require_command xcrun
require_command python3
require_command ditto

prepare_release_dir
ensure_notary_profile
ensure_file_exists "$(release_zip_path)"
ensure_file_exists "$app_path"

result_json="$release_dir/notary-result.json"
rm -f "$result_json" "$(notarized_zip_path)"

xcrun notarytool submit "$(release_zip_path)" \
  --keychain-profile "$notary_profile" \
  --wait \
  --output-format json >"$result_json"

status="$(python3 - <<'PY' "$result_json"
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as fh:
    payload = json.load(fh)

print(payload.get("status", ""))
PY
)"

if [[ "$status" != "Accepted" ]]; then
  echo "Notarization failed. See $result_json" >&2
  cat "$result_json" >&2
  exit 1
fi

xcrun stapler staple "$app_path"
xcrun stapler validate "$app_path"
ditto -c -k --sequesterRsrc --keepParent "$app_path" "$(notarized_zip_path)"

echo "Notarization status: $status"
echo "Result JSON: $result_json"
echo "Notarized zip: $(notarized_zip_path)"
