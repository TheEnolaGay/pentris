#!/usr/bin/env bash
set -euo pipefail

mode="${1:-release}"
output_dir="${2:-build/web}"
godot_bin="${GODOT_BIN:-godot4}"

case "$mode" in
  debug)
    mkdir -p "$output_dir"
    "$godot_bin" --headless --path . --export-debug "Web" "$output_dir/index.html"
    ;;
  release)
    mkdir -p "$output_dir"
    "$godot_bin" --headless --path . --export-release "Web" "$output_dir/index.html"
    ;;
  *)
    echo "usage: $0 [release|debug] [output_dir]" >&2
    exit 2
    ;;
esac

echo "$output_dir/index.html"
