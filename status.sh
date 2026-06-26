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

check_pid() {
  local name=$1
  local pidfile="$PID_DIR/$2.pid"
  if [ -f "$pidfile" ]; then
    local pid
    pid=$(cat "$pidfile")
    if kill -0 "$pid" 2>/dev/null; then
      echo "$name: running (PID $pid)"
    else
      echo "$name: not running (stale pidfile)"
    fi
  else
    echo "$name: not started"
  fi
}

check_pid "opencode" "opencode"
check_pid "openchamber" "openchamber"

if cloudflared_is_service; then
  echo "cloudflared: running (system service)"
else
  check_pid "cloudflared" "cloudflared"
fi
