#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 1 ] || [ "$#" -gt 3 ]; then
  echo "usage: $0 <scenario> [viewport_preset|output_path] [output_path]" >&2
  exit 2
fi

scenario="$1"
viewport_preset="phone_landscape"
output_path=""

if [ "$#" -eq 2 ]; then
  if [[ "$2" == *.png ]] || [[ "$2" == */* ]]; then
    output_path="$2"
  else
    viewport_preset="$2"
  fi
elif [ "$#" -eq 3 ]; then
  viewport_preset="$2"
  output_path="$3"
fi

output_path="${output_path:-output/visual-checks/${viewport_preset}/${scenario}.png}"

mkdir -p "$(dirname "$output_path")"
godot4 --path . --display-driver x11 --rendering-driver opengl3 --audio-driver Dummy -s res://tools/visual_capture_runner.gd -- "$scenario" "$output_path" "$viewport_preset"
