#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 1 ] || [ "$#" -gt 5 ]; then
  echo "usage: $0 <script_name> [viewport_preset] [output_dir] [seed] [fps]" >&2
  exit 2
fi

script_name="$1"
viewport_preset="${2:-phone_landscape}"
output_dir="${3:-output/visual-playtests/${viewport_preset}/${script_name}}"
fps="${5:-24}"

args=("$script_name" "$output_dir" "$viewport_preset")
if [ "$#" -ge 4 ]; then
  args+=("$4")
fi
if [ "$#" -ge 5 ]; then
  args+=("$fps")
fi

mkdir -p "$output_dir"
godot4 --path . --display-driver x11 --rendering-driver opengl3 --audio-driver Dummy -s res://tools/visual_playtest_runner.gd -- "${args[@]}"
