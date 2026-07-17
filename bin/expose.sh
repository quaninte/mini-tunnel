#!/usr/bin/env bash
# Apply a rendered deployment conf to OpenResty over SSH.
# NEVER run this against production without explicit user approval.
# Flow: render → scp to /tmp → sudo install into others/ → nginx -t → reload
#       on fail: restore previous conf and abort.
set -eu

DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../lib_deploy.sh
. "$DIR/lib_deploy.sh"

usage() {
  echo "Usage: $0 <deployment-name>" >&2
  echo "  Renders, installs into OpenResty others/, nginx -t, reloads." >&2
  echo "  Rolls back previous conf on nginx -t failure." >&2
  exit 1
}

NAME="${1:-}"
if [ -z "$NAME" ] || [ "$NAME" = "-h" ] || [ "$NAME" = "--help" ]; then
  usage
fi

load_deployment "$NAME" || exit 1
validate_deployment || exit 1

if [ "${DEPLOY_STATUS}" != "active" ]; then
  echo "Error: refuse to expose DEPLOY_STATUS=${DEPLOY_STATUS} (must be active)" >&2
  exit 1
fi

REMOTE_HOST="${OPENRESTY_HOST}"
REMOTE_CONF_NAME="${HOSTNAME}.conf"
REMOTE_DIR="/usr/local/openresty/nginx/conf/others"
REMOTE_PATH="${REMOTE_DIR}/${REMOTE_CONF_NAME}"
REMOTE_BACKUP="/tmp/mini-tunnel-${NAME}.conf.bak"
REMOTE_TMP="/tmp/mini-tunnel-${NAME}.conf.new"
LOCAL_CONF="$DIR/deployments/${NAME}.conf"

echo "=== expose: ${NAME} → ${REMOTE_HOST}:${REMOTE_PATH} ==="

# 1. Render locally
"$DIR/bin/render.sh" "$NAME"
if [ ! -f "$LOCAL_CONF" ]; then
  echo "Error: render did not produce $LOCAL_CONF" >&2
  exit 1
fi

# 2. Upload
echo "Uploading conf..."
scp -q "$LOCAL_CONF" "${REMOTE_HOST}:${REMOTE_TMP}"

# 3. Install with backup, test, reload or restore
# shellcheck disable=SC2029
ssh "$REMOTE_HOST" bash -s <<EOF
set -eu
REMOTE_PATH="$REMOTE_PATH"
REMOTE_BACKUP="$REMOTE_BACKUP"
REMOTE_TMP="$REMOTE_TMP"
REMOTE_DIR="$REMOTE_DIR"

sudo mkdir -p "\$REMOTE_DIR"

# Backup existing conf if present
if [ -f "\$REMOTE_PATH" ]; then
  sudo cp -a "\$REMOTE_PATH" "\$REMOTE_BACKUP"
  HAD_PREV=1
else
  HAD_PREV=0
fi

sudo install -m 644 "\$REMOTE_TMP" "\$REMOTE_PATH"
rm -f "\$REMOTE_TMP"

# nginx -t gates every reload
if ! sudo /usr/local/openresty/bin/openresty -t 2>&1; then
  echo "ERROR: nginx -t failed — rolling back" >&2
  if [ "\$HAD_PREV" = 1 ]; then
    sudo mv "\$REMOTE_BACKUP" "\$REMOTE_PATH"
  else
    sudo rm -f "\$REMOTE_PATH"
  fi
  # Re-test after rollback (best effort)
  sudo /usr/local/openresty/bin/openresty -t 2>&1 || true
  exit 1
fi

# Test passed — reload
sudo /usr/local/openresty/bin/openresty -s reload
rm -f "\$REMOTE_BACKUP"
echo "Reloaded OpenResty with \$REMOTE_PATH"
EOF

echo "=== expose complete: https://${HOSTNAME} ==="
