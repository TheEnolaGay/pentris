#!/usr/bin/env bash
set -euo pipefail

root_dir="${1:-build/web}"
port="${2:-8060}"
state_dir="/tmp/pentris-web"
server_pid_file="$state_dir/http-${port}.pid"
tunnel_pid_file="$state_dir/tunnel-${port}.pid"
server_log_file="/tmp/pentris-web-http.log"

if [ ! -d "$root_dir" ]; then
  echo "missing directory: $root_dir" >&2
  echo "build first with ./scripts/build_web.sh" >&2
  exit 2
fi

server_pid=""
tunnel_pid=""

mkdir -p "$state_dir"

pid_is_alive() {
  local pid="$1"
  kill -0 "$pid" 2>/dev/null
}

cleanup_pid_file() {
  local pid_file="$1"
  local expected_fragment="$2"
  if [ ! -f "$pid_file" ]; then
    return
  fi
  local pid
  pid="$(cat "$pid_file" 2>/dev/null || true)"
  if [ -n "$pid" ] && pid_is_alive "$pid"; then
    local args
    args="$(ps -p "$pid" -o args= 2>/dev/null || true)"
    if [[ "$args" == *"$expected_fragment"* ]]; then
      kill "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
    fi
  fi
  rm -f "$pid_file"
}

cleanup() {
  if [ -n "$server_pid" ] && kill -0 "$server_pid" 2>/dev/null; then
    kill "$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
  fi
  if [ -n "$tunnel_pid" ] && kill -0 "$tunnel_pid" 2>/dev/null; then
    kill "$tunnel_pid" 2>/dev/null || true
    wait "$tunnel_pid" 2>/dev/null || true
  fi
  rm -f "$server_pid_file" "$tunnel_pid_file"
}

trap cleanup EXIT INT TERM

cleanup_pid_file "$tunnel_pid_file" "127.0.0.1:$port"
cleanup_pid_file "$server_pid_file" "http.server $port"

cd "$root_dir"
python3 -m http.server "$port" --bind 127.0.0.1 >"$server_log_file" 2>&1 &
server_pid=$!
printf '%s\n' "$server_pid" >"$server_pid_file"

sleep 1
if ! kill -0 "$server_pid" 2>/dev/null; then
  echo "failed to start local web server on 127.0.0.1:$port" >&2
  echo "server log: $server_log_file" >&2
  exit 1
fi

echo "Serving $root_dir on http://127.0.0.1:$port"
echo "Starting HTTPS tunnel for secure-context phone testing..."

if command -v cloudflared >/dev/null 2>&1; then
  echo "Tunnel provider: cloudflared"
  echo "Open the printed https:// URL on your phone."
  cloudflared tunnel --url "http://127.0.0.1:$port" &
  tunnel_pid=$!
elif command -v ngrok >/dev/null 2>&1; then
  echo "Tunnel provider: ngrok"
  echo "Open the printed https:// URL on your phone."
  ngrok http "127.0.0.1:$port" &
  tunnel_pid=$!
else
  echo "No supported tunnel client found." >&2
  echo "Install one of the following and rerun this script:" >&2
  echo "- cloudflared" >&2
  echo "- ngrok" >&2
  echo >&2
  echo "Manual fallback after this script exits:" >&2
  echo "1. ./scripts/serve_web.sh build/web $port" >&2
  echo "2. cloudflared tunnel --url http://127.0.0.1:$port" >&2
  echo "   or: ngrok http 127.0.0.1:$port" >&2
  exit 3
fi

printf '%s\n' "$tunnel_pid" >"$tunnel_pid_file"
wait "$tunnel_pid"
