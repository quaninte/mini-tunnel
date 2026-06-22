#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"

if [ ! -f "$DIR/.env" ]; then
  echo "Error: .env not found. Copy .env.example to .env and fill in values."
  exit 1
fi

set -a
source "$DIR/.env"
set +a

OPENCODE_PORT="${OPENCODE_PORT:-4096}"
OPENCHAMBER_PORT="${OPENCHAMBER_PORT:-3000}"
CF_HOSTNAME="${CF_HOSTNAME:-quinmini.leanflag.net}"

wait_for_port() {
  local port=$1 name=$2 max=${3:-30}
  local i=0
  while ! nc -z 127.0.0.1 "$port" 2>/dev/null; do
    i=$((i + 1))
    if [ "$i" -ge "$max" ]; then
      echo "Timeout waiting for $name on port $port"
      return 1
    fi
    sleep 1
  done
  echo "$name ready on port $port"
}

# --- opencode serve ---
echo "Starting opencode serve..."
opencode serve --port "$OPENCODE_PORT" --hostname 127.0.0.1 > "$DIR/opencode.log" 2>&1 &
OPENCODE_PID=$!
echo "$OPENCODE_PID" > "$DIR/tmp/opencode.pid"
wait_for_port "$OPENCODE_PORT" "opencode" 15

# --- openchamber ---
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

# --- cloudflared tunnel ---
CLOUDFLARED_MANAGED=false
if launchctl list 2>/dev/null | grep -q cloudflared; then
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
echo "  opencode:     http://127.0.0.1:$OPENCODE_PORT (PID $OPENCODE_PID)"
echo "  openchamber:  http://127.0.0.1:$OPENCHAMBER_PORT (PID $OPENCHAMBER_PID)"
if [ "$CLOUDFLARED_MANAGED" = true ]; then
  echo "  tunnel:       https://$CF_HOSTNAME (system service)"
else
  echo "  tunnel:       https://$CF_HOSTNAME (PID $CLOUDFLARED_PID)"
fi
echo ""
echo "Logs: $DIR/*.log"
echo "Stop: $DIR/stop.sh"
