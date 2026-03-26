#!/usr/bin/env bash
set -euo pipefail

mode="${1:-debug}"
output_dir="${2:-build/web}"

case "$mode" in
  debug)
    mkdir -p "$output_dir"
    godot4 --headless --path . --export-debug "Web" "$output_dir/index.html"
    ;;
  release)
    mkdir -p "$output_dir"
    godot4 --headless --path . --export-release "Web" "$output_dir/index.html"
    ;;
  *)
    echo "usage: $0 [debug|release] [output_dir]" >&2
    exit 2
    ;;
esac

echo "$output_dir/index.html"
