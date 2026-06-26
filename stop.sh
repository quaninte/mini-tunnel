#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
PID_DIR="$DIR/tmp"

cloudflared_is_service() {
  if command -v launchctl >/dev/null 2>&1; then
    launchctl list 2>/dev/null | grep -q cloudflared
  elif command -v systemctl >/dev/null 2>&1; then
    systemctl is-active --quiet cloudflared 2>/dev/null
  else
    return 1
  fi
}

kill_pid() {
  local name=$1
  local pidfile="$PID_DIR/$2.pid"
  if [ -f "$pidfile" ]; then
    local pid
    pid=$(cat "$pidfile")
    if kill -0 "$pid" 2>/dev/null; then
      kill "$pid" && echo "Stopped $name (PID $pid)"
    else
      echo "$name (PID $pid) not running"
    fi
    rm -f "$pidfile"
  else
    echo "$name: no pidfile found"
  fi
}

if cloudflared_is_service && [ ! -f "$PID_DIR/cloudflared.pid" ]; then
  echo "cloudflared: managed by system service (skipping stop)"
else
  kill_pid "cloudflared" "cloudflared"
fi
kill_pid "openchamber" "openchamber"
kill_pid "opencode" "opencode"

echo "Done."
