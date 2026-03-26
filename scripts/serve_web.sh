#!/usr/bin/env bash
set -euo pipefail

root_dir="${1:-build/web}"
port="${2:-8060}"

if [ ! -d "$root_dir" ]; then
  echo "missing directory: $root_dir" >&2
  echo "build first with ./scripts/build_web.sh" >&2
  exit 2
fi

echo "Serving $root_dir on http://0.0.0.0:$port"
cd "$root_dir"
python3 -m http.server "$port" --bind 0.0.0.0
