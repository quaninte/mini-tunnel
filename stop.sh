#!/usr/bin/env bash
set -eu

DIR="$(cd "$(dirname "$0")" && pwd)"
PID_DIR="$DIR/tmp"

# Source .env for port config (optional, defaults used if missing)
if [ -f "$DIR/.env" ]; then
  set -a
  . "$DIR/.env"
  set +a
fi

. "$DIR/lib.sh"
. "$DIR/code_stack.sh"
. "$DIR/openwebui.sh"

OPENCODE_PORT="${OPENCODE_PORT:-4096}"
OPENCHAMBER_PORT="${OPENCHAMBER_PORT:-3000}"
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

if cloudflared_is_service && [ ! -f "$PID_DIR/cloudflared.pid" ]; then
  echo "cloudflared: managed by system service (skipping stop)"
else
  if [ -f "$PID_DIR/cloudflared.pid" ]; then
    pid=$(cat "$PID_DIR/cloudflared.pid")
    if is_process_alive "$pid"; then
      kill_and_wait "$pid" 5 3
      echo "Stopped cloudflared (PID $pid)"
    else
      echo "cloudflared (PID $pid) not running"
    fi
    rm -f "$PID_DIR/cloudflared.pid"
  else
    echo "cloudflared: no pidfile found"
  fi
fi

if [ -f "$PID_DIR/cloudflared-openwebui.pid" ]; then
  pid=$(cat "$PID_DIR/cloudflared-openwebui.pid")
  if is_process_alive "$pid"; then
    kill_and_wait "$pid" 5 3
    echo "Stopped cloudflared-openwebui (PID $pid)"
  else
    echo "cloudflared-openwebui (PID $pid) not running"
  fi
  rm -f "$PID_DIR/cloudflared-openwebui.pid"
fi

if [ "$ENABLE_CODE_STACK" = true ]; then
  stop_code_stack
fi
if [ "$ENABLE_OPENWEBUI" = true ]; then
  stop_openwebui
fi

echo "Done."
