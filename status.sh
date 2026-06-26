#!/usr/bin/env bash
set -eu

DIR="$(cd "$(dirname "$0")" && pwd)"
PID_DIR="$DIR/tmp"

source "$DIR/lib.sh"

cloudflared_is_service() {
  if command -v launchctl >/dev/null 2>&1; then
    launchctl list 2>/dev/null | grep -q cloudflared
  elif command -v systemctl >/dev/null 2>&1; then
    systemctl is-active --quiet cloudflared 2>/dev/null
  else
    return 1
  fi
}

check_service() {
  local name=$1 port=$2 pidfile="$PID_DIR/$3.pid"
  local status="not started"

  if [ -f "$pidfile" ]; then
    local pid
    pid=$(cat "$pidfile")
    if is_process_alive "$pid"; then
      status="running (PID $pid)"
    else
      status="not running (stale pidfile)"
    fi
  fi

  if is_port_in_use "$port"; then
    status="$status, port $port occupied"
  else
    status="$status, port $port free"
  fi

  echo "$name: $status"
}

check_service "opencode" "${OPENCODE_PORT:-4096}" "opencode"
check_service "openchamber" "${OPENCHAMBER_PORT:-3000}" "openchamber"

if cloudflared_is_service; then
  echo "cloudflared: running (system service)"
else
  check_service "cloudflared" "" "cloudflared"
fi
