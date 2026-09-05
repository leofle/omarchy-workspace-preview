#!/usr/bin/env bash
set -euo pipefail

workspace_id="${1:-}"
destination="${2:-}"
helper="$(cd "$(dirname "$0")" && pwd)/preview-helper.py"

if [[ ! "$workspace_id" =~ ^[1-9][0-9]*$ || -z "$destination" ]]; then
  echo "usage: $0 <positive-workspace-id> <destination>" >&2
  exit 2
fi

# Snapshot the output identity and geometry. Reject special-workspace overlays.
monitor_snapshot() {
  python3 "$helper" run 1000 65536 -- hyprctl -j monitors |
    jq -ce --argjson workspace "$workspace_id" '
      [.[] | select(.focused == true and .activeWorkspace.id == $workspace
        and ((.specialWorkspace.id // 0) == 0))
        | {name, width, height, scale, transform}] |
      if length == 1 then .[0] else error("workspace is not focused") end'
}

before="$(monitor_snapshot)"
monitor_name="$(jq -r '.name' <<< "$before")"
# grim scale is relative to logical output dimensions. Bound the longest edge
# to 640 pixels (twice the maximum preview width), without upscaling.
capture_scale="$(jq -er '
  ([.width, .height] | max) as $edge |
  if $edge > 0 and .scale > 0 then
    ([1, 640 / $edge] | min) * .scale
  else error("invalid monitor geometry") end' <<< "$before")"

tmp_file="$(mktemp --suffix=.jpg)"
trap 'rm -f "$tmp_file"' EXIT

timeout 3s grim -t jpeg -q 60 -s "$capture_scale" -o "$monitor_name" "$tmp_file"
after="$(monitor_snapshot)"
[[ "$before" == "$after" ]] || exit 1
python3 "$helper" write "$destination" < "$tmp_file"
