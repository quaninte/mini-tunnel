#!/usr/bin/env bash
set -eu

DIR="$(cd "$(dirname "$0")" && pwd)"

if [ ! -f "$DIR/.env" ]; then
  echo "Error: .env not found. Copy .env.example to .env and fill in values."
  exit 1
fi

set -a
source "$DIR/.env"
set +a

source "$DIR/lib.sh"

OPENCODE_PORT="${OPENCODE_PORT:-4096}"
OPENCHAMBER_PORT="${OPENCHAMBER_PORT:-3000}"
CF_HOSTNAME="${CF_HOSTNAME:-quinmini.leanflag.net}"

FORCE=false
if [ "${1:-}" = "--force" ] || [ "${1:-}" = "-f" ]; then
  FORCE=true
  shift
fi

cloudflared_is_service() {
  if command -v launchctl >/dev/null 2>&1; then
    launchctl list 2>/dev/null | grep -q cloudflared
  elif command -v systemctl >/dev/null 2>&1; then
    systemctl is-active --quiet cloudflared 2>/dev/null
  else
    return 1
  fi
}

# --- Pre-flight: ensure port is free ---
ensure_port_free() {
  local port=$1 name=$2
  if ! is_port_in_use "$port"; then
    return 0
  fi

  local owner_pid
  owner_pid=$(get_port_owner_pid "$port")

  # If we have a pidfile for this service and the PID matches, it's already our process.
  if [ -n "${owner_pid:-}" ] && [ -f "$DIR/tmp/$name.pid" ]; then
    local our_pid
    our_pid=$(cat "$DIR/tmp/$name.pid" 2>/dev/null || true)
    if [ "$owner_pid" = "$our_pid" ]; then
      echo "$name already running on port $port (PID $our_pid)"
      return 2  # 2 = already running (skip)
    fi
  fi

  if [ "$FORCE" = true ]; then
    echo "Port $port is in use (PID ${owner_pid:-unknown}). Forcing..."
    if [ -n "${owner_pid:-}" ]; then
      kill_and_wait "$owner_pid" 5 3
    fi
    clean_openchamber_stale_state "$port"
    wait_for_port_free "$port" 10 || {
      echo "Error: port $port is still occupied. Cannot start $name."
      exit 1
    }
    return 0
  fi

  echo "Error: port $port is already in use by another process (PID ${owner_pid:-unknown})."
  echo "  Use '$DIR/stop.sh' to stop existing services first,"
  echo "  or '$DIR/start.sh --force' to kill the occupant and restart."
  exit 1
}

# --- opencode serve ---
OPENCODE_SKIP=false
ensure_port_free "$OPENCODE_PORT" "opencode" || OPENCODE_RESULT=$?
if [ "${OPENCODE_RESULT:-0}" -eq 2 ]; then
  OPENCODE_SKIP=true
fi
if [ "$OPENCODE_SKIP" = false ]; then
  echo "Starting opencode serve..."
  opencode serve --port "$OPENCODE_PORT" --hostname 127.0.0.1 > "$DIR/opencode.log" 2>&1 &
  OPENCODE_PID=$!
  echo "$OPENCODE_PID" > "$DIR/tmp/opencode.pid"
  wait_for_port "$OPENCODE_PORT" "opencode" 15
fi

# --- openchamber ---
# Clean stale openchamber state BEFORE starting so its own CLI doesn't
# see a stale pidfile and refuse to start ("already running on port X").
clean_openchamber_stale_state "$OPENCHAMBER_PORT"

OPENCHAMBER_SKIP=false
ensure_port_free "$OPENCHAMBER_PORT" "openchamber" || OPENCHAMBER_RESULT=$?
if [ "${OPENCHAMBER_RESULT:-0}" -eq 2 ]; then
  OPENCHAMBER_SKIP=true
fi
if [ "$OPENCHAMBER_SKIP" = false ]; then
  echo "Starting openchamber..."
  OPENCODE_HOST="http://127.0.0.1:$OPENCODE_PORT" \
    openchamber serve \
      --port "$OPENCHAMBER_PORT" \
      --host 127.0.0.1 \
      --ui-password "$PASS_KEY" \
      --foreground > "$DIR/openchamber.log" 2>&1 &
  OPENCHAMBER_PID=$!
  echo "$OPENCHAMBER_PID" > "$DIR/tmp/openchamber.pid"
  wait_for_port "$OPENCHAMBER_PORT" "openchamber" 15
fi

# --- cloudflared tunnel ---
CLOUDFLARED_MANAGED=false
if cloudflared_is_service; then
  echo "cloudflared is running as a system service (skipping manual start)"
  CLOUDFLARED_MANAGED=true
else
  echo "Starting cloudflared tunnel..."
  cloudflared tunnel run --token "$CF_TUNNEL_TOKEN" > "$DIR/cloudflared.log" 2>&1 &
  CLOUDFLARED_PID=$!
  echo "$CLOUDFLARED_PID" > "$DIR/tmp/cloudflared.pid"
fi

echo ""
echo "=== All services started ==="
echo "  opencode:     http://127.0.0.1:$OPENCODE_PORT (PID ${OPENCODE_PID:-already running})"
echo "  openchamber:  http://127.0.0.1:$OPENCHAMBER_PORT (PID ${OPENCHAMBER_PID:-already running})"
if [ "$CLOUDFLARED_MANAGED" = true ]; then
  echo "  tunnel:       https://$CF_HOSTNAME (system service)"
else
  echo "  tunnel:       https://$CF_HOSTNAME (PID ${CLOUDFLARED_PID:-already running})"
fi
echo ""
echo "Logs: $DIR/*.log"
echo "Stop: $DIR/stop.sh"
