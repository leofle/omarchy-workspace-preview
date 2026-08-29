#!/usr/bin/env bash
set -euo pipefail

workspace_id="${1:-}"
destination="${2:-}"
helper="$(cd "$(dirname "$0")" && pwd)/preview-helper.py"

if [[ -z "$workspace_id" || -z "$destination" ]]; then
  echo "usage: $0 <workspace-id> <destination>" >&2
  exit 2
fi

mkdir -p -m 700 "$(dirname "$destination")"

monitor_json="$(python3 "$helper" run 1000 65536 -- hyprctl -j monitors)"
monitor_name="$(
  printf '%s' "$monitor_json" | jq -r '.[] | select(.focused == true) | .name' | head -n1
)"

if [[ -z "$monitor_name" || "$monitor_name" == "null" ]]; then
  exit 1
fi

tmp_file="$(mktemp --suffix=.jpg)"
trap 'rm -f "$tmp_file"' EXIT

timeout 3s grim -t jpeg -q 60 -o "$monitor_name" "$tmp_file"
python3 "$helper" write "$destination" < "$tmp_file"
