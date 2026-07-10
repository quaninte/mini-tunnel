#!/usr/bin/env bash
set -eu

DIR="$(cd "$(dirname "$0")" && pwd)"
PID_DIR="$DIR/tmp"

if [ -f "$DIR/.env" ]; then
  set -a
  . "$DIR/.env"
  set +a
fi

. "$DIR/lib.sh"
. "$DIR/code_stack.sh"
. "$DIR/openwebui.sh"

OPENWEBUI_PORT="${OPENWEBUI_PORT:-8080}"
ENABLE_CODE_STACK="${ENABLE_CODE_STACK:-true}"
ENABLE_OPENWEBUI="${ENABLE_OPENWEBUI:-false}"

cloudflared_is_service() {
  if command -v launchctl >/dev/null 2>&1; then
    launchctl list 2>/dev/null | grep -q cloudflared
  elif command -v systemctl >/dev/null 2>&1; then
    systemctl is-active --quiet cloudflared 2>/dev/null
  else
    return 1
  fi
}

check_pid_service() {
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

if [ "$ENABLE_CODE_STACK" = true ]; then
  status_code_stack
else
  echo "opencode: disabled (ENABLE_CODE_STACK=false)"
  echo "openchamber: disabled (ENABLE_CODE_STACK=false)"
fi

if [ "$ENABLE_OPENWEBUI" = true ]; then
  status_openwebui
else
  echo "openwebui: disabled (ENABLE_OPENWEBUI=false)"
fi

if cloudflared_is_service; then
  echo "cloudflared: running (system service)"
else
  check_pid_service "cloudflared" "" "cloudflared"
fi

if [ "$ENABLE_OPENWEBUI" = true ] && [ -n "${OPENWEBUI_CF_TUNNEL_TOKEN:-}" ]; then
  check_pid_service "cloudflared-openwebui" "" "cloudflared-openwebui"
fi
