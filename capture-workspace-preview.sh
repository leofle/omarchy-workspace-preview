#!/usr/bin/env bash
set -euo pipefail

workspace_id="${1:-}"
destination="${2:-}"

if [[ -z "$workspace_id" || -z "$destination" ]]; then
  echo "usage: $0 <workspace-id> <destination>" >&2
  exit 2
fi

mkdir -p "$(dirname "$destination")"

monitor_name="$(
  hyprctl -j monitors | jq -r '.[] | select(.focused == true) | .name' | head -n1
)"

if [[ -z "$monitor_name" || "$monitor_name" == "null" ]]; then
  exit 1
fi

tmp_file="$(mktemp --suffix=.jpg)"
trap 'rm -f "$tmp_file"' EXIT

grim -t jpeg -q 60 -o "$monitor_name" "$tmp_file"
mv "$tmp_file" "$destination"
