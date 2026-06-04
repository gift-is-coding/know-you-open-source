#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_dir="$repo_root/ThirdParty/llm_wiki"
runner_dir="${KNOWYOU_MYWIKI_RUNNER_DIR:-$repo_root/build/MyWikiRunner}"

node_bin="${KNOWYOU_BUNDLED_NODE:-$(command -v node || true)}"
if [[ -z "$node_bin" || ! -x "$node_bin" ]]; then
  echo "Missing Node binary for building MyWikiRunner. Set KNOWYOU_BUNDLED_NODE." >&2
  exit 1
fi

realpath_portable() {
  python3 - "$1" <<'PY'
import os
import sys

print(os.path.realpath(sys.argv[1]))
PY
}

is_system_dylib() {
  local path="$1"
  [[ "$path" == /usr/lib/* || "$path" == /System/Library/* ]]
}

resolve_dylib_source() {
  local dependency="$1"
  local node_root="$2"
  local base
  base="$(basename "$dependency")"

  if [[ "$dependency" == @rpath/* || "$dependency" == @loader_path/* || "$dependency" == @executable_path/* ]]; then
    find -L "$node_root" /opt/homebrew/opt /usr/local/opt \
      -name "$base" \
      -print \
      -quit 2>/dev/null || true
    return
  fi

  if [[ -f "$dependency" ]]; then
    realpath_portable "$dependency"
  fi
}

otool_dependencies() {
  local binary="$1"
  otool -L "$binary" | tail -n +2 | awk '{ print $1 }'
}

copy_node_runtime() {
  local node_source="$1"
  local target_dir="$2"
  local node_real
  local node_root
  node_real="$(realpath_portable "$node_source")"
  node_root="$(cd "$(dirname "$node_real")/.." && pwd)"

  cp "$node_real" "$target_dir/node"
  chmod 755 "$target_dir/node"

  local -a queue=("$target_dir/node")
  local -a targets=("$target_dir/node")
  local index=0
  while (( index < ${#queue[@]} )); do
    local current="${queue[$index]}"
    index=$((index + 1))

    local dependency
    while IFS= read -r dependency; do
      [[ -z "$dependency" ]] && continue
      is_system_dylib "$dependency" && continue

      local source
      source="$(resolve_dylib_source "$dependency" "$node_root")"
      [[ -n "$source" && -f "$source" ]] || continue

      local destination="$target_dir/$(basename "$dependency")"
      if [[ ! -f "$destination" ]]; then
        cp "$source" "$destination"
        chmod 755 "$destination"
        queue+=("$destination")
        targets+=("$destination")
      fi
    done < <(otool_dependencies "$current")
  done

  local target
  for target in "${targets[@]}"; do
    if [[ "$target" == *.dylib ]]; then
      install_name_tool -id "@loader_path/$(basename "$target")" "$target" 2>/dev/null || true
    fi

    local dependency
    while IFS= read -r dependency; do
      [[ -z "$dependency" ]] && continue
      is_system_dylib "$dependency" && continue
      install_name_tool -change "$dependency" "@loader_path/$(basename "$dependency")" "$target" 2>/dev/null || true
    done < <(otool_dependencies "$target")

    codesign --force --sign - "$target" >/dev/null 2>&1 || true
  done
}

pushd "$source_dir" >/dev/null
npm run build:knowyou-runner
popd >/dev/null

rm -rf "$runner_dir"
mkdir -p "$runner_dir"
copy_node_runtime "$node_bin" "$runner_dir"
cp "$source_dir/dist-knowyou-runner/mywiki-runner.js" "$runner_dir/mywiki-runner.js"

echo "MyWikiRunner: $runner_dir"
