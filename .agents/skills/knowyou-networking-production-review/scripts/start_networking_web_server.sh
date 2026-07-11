#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 4 ]]; then
  echo "Usage: start_networking_web_server.sh <web-env-script> <repo-root> <port> <log-file>" >&2
  exit 2
fi

web_env_script="$1"
repo_root="$2"
port="$3"
log_file="$4"

exec >> "$log_file" 2>&1

source "$web_env_script"
cd "$repo_root/NetworkingWeb"
exec npm start -- --hostname 127.0.0.1 --port "$port"
