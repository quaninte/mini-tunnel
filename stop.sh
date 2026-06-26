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
  local port=$3
  if [ -f "$pidfile" ]; then
    local pid
    pid=$(cat "$pidfile")
    if is_process_alive "$pid"; then
      kill_and_wait "$pid" 5 3
      echo "Stopped $name (PID $pid)"
    else
      echo "$name (PID $pid) not running"
    fi
    rm -f "$pidfile"
  else
    echo "$name: no pidfile found"
  fi

  # If the port is still occupied (by a process our pidfile didn't know about),
  # kill whoever is on it.
  if [ -n "${port:-}" ] && is_port_in_use "$port"; then
    echo "$name: port $port still occupied by another process, killing it..."
    kill_port_occupant "$port"
  fi
}

if cloudflared_is_service && [ ! -f "$PID_DIR/cloudflared.pid" ]; then
  echo "cloudflared: managed by system service (skipping stop)"
else
  kill_pid "cloudflared" "cloudflared" ""
fi

kill_pid "openchamber" "openchamber" "${OPENCHAMBER_PORT:-3000}"
kill_pid "opencode" "opencode" "${OPENCODE_PORT:-4096}"

# Clean openchamber's own stale state files so future starts are clean
clean_openchamber_stale_state "${OPENCHAMBER_PORT:-3000}"

echo "Done."
