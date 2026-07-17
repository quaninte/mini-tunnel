#!/usr/bin/env bash
set -eu

DIR="$(cd "$(dirname "$0")" && pwd)"

# Source .env for port config (optional, defaults used if missing)
if [ -f "$DIR/.env" ]; then
  set -a
  . "$DIR/.env"
  set +a
fi

. "$DIR/lib.sh"

OPENCODE_PORT="${OPENCODE_PORT:-4096}"
OPENCHAMBER_PORT="${OPENCHAMBER_PORT:-3000}"
OPENWEBUI_PORT="${OPENWEBUI_PORT:-8080}"
ENABLE_CODE_STACK="${ENABLE_CODE_STACK:-true}"
ENABLE_OPENWEBUI="${ENABLE_OPENWEBUI:-false}"

configure_code_profile

echo "=== Stopping services ==="
"$DIR/stop.sh" || true

echo ""
echo "=== Ensuring ports are released ==="
if [ "$ENABLE_CODE_STACK" = true ]; then
  if is_port_in_use "$OPENCHAMBER_PORT"; then
    echo "Port $OPENCHAMBER_PORT still occupied, force-killing..."
    kill_port_occupant "$OPENCHAMBER_PORT"
  fi
  if is_port_in_use "$OPENCODE_PORT"; then
    echo "Port $OPENCODE_PORT still occupied, force-killing..."
    kill_port_occupant "$OPENCODE_PORT"
  fi
  wait_for_port_free "$OPENCHAMBER_PORT" 15 || {
    echo "Error: port $OPENCHAMBER_PORT could not be freed"
    exit 1
  }
  wait_for_port_free "$OPENCODE_PORT" 15 || {
    echo "Error: port $OPENCODE_PORT could not be freed"
    exit 1
  }
  # Ensure openchamber's own stale state is fully cleaned
  clean_all_openchamber_stale_state
fi

if [ "$ENABLE_OPENWEBUI" = true ]; then
  if is_port_in_use "$OPENWEBUI_PORT"; then
    echo "Port $OPENWEBUI_PORT still occupied, force-killing..."
    kill_port_occupant "$OPENWEBUI_PORT"
  fi
  wait_for_port_free "$OPENWEBUI_PORT" 15 || {
    echo "Error: port $OPENWEBUI_PORT could not be freed"
    exit 1
  }
fi

echo ""
echo "=== Starting services ==="
exec "$DIR/start.sh"
