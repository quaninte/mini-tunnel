#!/usr/bin/env bash
set -eu

DIR="$(cd "$(dirname "$0")" && pwd)"

# Source .env for port config (optional, defaults used if missing)
if [ -f "$DIR/.env" ]; then
  set -a
  source "$DIR/.env"
  set +a
fi

source "$DIR/lib.sh"

OPENCODE_PORT="${OPENCODE_PORT:-4096}"
OPENCHAMBER_PORT="${OPENCHAMBER_PORT:-3000}"

echo "=== Stopping services ==="
"$DIR/stop.sh" || true

echo ""
echo "=== Waiting for ports to be released ==="
wait_for_port_free "$OPENCHAMBER_PORT" 15 || true
wait_for_port_free "$OPENCODE_PORT" 15 || true

# Ensure openchamber's own stale state is fully cleaned
clean_all_openchamber_stale_state

echo ""
echo "=== Starting services ==="
exec "$DIR/start.sh"
