#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
PID_DIR="$DIR/tmp"

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
check_pid "cloudflared" "cloudflared"
