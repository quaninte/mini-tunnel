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

. "$DIR/lib.sh"
. "$DIR/code_stack.sh"
. "$DIR/openwebui.sh"

OPENCODE_PORT="${OPENCODE_PORT:-4096}"
OPENCHAMBER_PORT="${OPENCHAMBER_PORT:-3000}"
OPENWEBUI_PORT="${OPENWEBUI_PORT:-8080}"
CF_HOSTNAME="${CF_HOSTNAME:-quinmini.leanflag.net}"
ENABLE_CODE_STACK="${ENABLE_CODE_STACK:-true}"
ENABLE_OPENWEBUI="${ENABLE_OPENWEBUI:-false}"

FORCE=false
if [ "${1:-}" = "--force" ] || [ "${1:-}" = "-f" ]; then
  FORCE=true
  shift
fi

if [ "$ENABLE_CODE_STACK" != true ] && [ "$ENABLE_OPENWEBUI" != true ]; then
  echo "Error: both ENABLE_CODE_STACK and ENABLE_OPENWEBUI are false — nothing to start."
  echo "  Enable at least one stack in .env."
  exit 1
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

echo ""
echo "=== Starting enabled stacks ==="
if [ "$ENABLE_CODE_STACK" = true ]; then
  start_code_stack
fi
if [ "$ENABLE_OPENWEBUI" = true ]; then
  start_openwebui
fi

# --- cloudflared tunnel(s) ---
# The code stack's tunnel (CF_TUNNEL_TOKEN) can either run as a system service or be
# started here manually. OpenWebUI can share that same tunnel (add a second Public
# Hostname rule to it in the dashboard, leave OPENWEBUI_CF_TUNNEL_TOKEN empty) or run
# its own dedicated tunnel (set OPENWEBUI_CF_TUNNEL_TOKEN to that tunnel's token).
CLOUDFLARED_MANAGED=false
if [ "$ENABLE_CODE_STACK" = true ]; then
  if cloudflared_is_service; then
    echo "cloudflared (code stack) is running as a system service (skipping manual start)"
    CLOUDFLARED_MANAGED=true
  else
    echo "Starting cloudflared tunnel (code stack)..."
    cloudflared tunnel run --token "$CF_TUNNEL_TOKEN" >"$DIR/cloudflared.log" 2>&1 &
    CLOUDFLARED_PID=$!
    echo "$CLOUDFLARED_PID" >"$DIR/tmp/cloudflared.pid"
  fi
fi

if [ "$ENABLE_OPENWEBUI" = true ] && [ -n "${OPENWEBUI_CF_TUNNEL_TOKEN:-}" ]; then
  echo "Starting cloudflared tunnel (OpenWebUI)..."
  cloudflared tunnel run --token "$OPENWEBUI_CF_TUNNEL_TOKEN" >"$DIR/cloudflared-openwebui.log" 2>&1 &
  OPENWEBUI_CLOUDFLARED_PID=$!
  echo "$OPENWEBUI_CLOUDFLARED_PID" >"$DIR/tmp/cloudflared-openwebui.pid"
fi

echo ""
echo "=== All services started ==="
if [ "$ENABLE_CODE_STACK" = true ]; then
  if [ "$CLOUDFLARED_MANAGED" = true ]; then
    TUNNEL_STATUS="system service"
  else
    TUNNEL_STATUS="PID ${CLOUDFLARED_PID:-already running}"
  fi
  echo "  tunnel:       https://$CF_HOSTNAME ($TUNNEL_STATUS)"
fi
if [ "$ENABLE_OPENWEBUI" = true ] && [ -n "${OPENWEBUI_HOSTNAME:-}" ]; then
  if [ -n "${OPENWEBUI_CF_TUNNEL_TOKEN:-}" ]; then
    echo "  tunnel:       https://$OPENWEBUI_HOSTNAME (PID ${OPENWEBUI_CLOUDFLARED_PID:-already running})"
  else
    echo "  tunnel:       https://$OPENWEBUI_HOSTNAME (via code stack's shared tunnel)"
  fi
fi
echo ""
echo "Logs: $DIR/*.log"
echo "Stop: $DIR/stop.sh"
