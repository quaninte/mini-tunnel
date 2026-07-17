#!/usr/bin/env bash
# Remove a deployment conf from OpenResty, nginx -t, reload, flip DEPLOY_STATUS.
set -eu

DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../lib_deploy.sh
. "$DIR/lib_deploy.sh"

usage() {
  echo "Usage: $0 <deployment-name>" >&2
  exit 1
}

NAME="${1:-}"
if [ -z "$NAME" ] || [ "$NAME" = "-h" ] || [ "$NAME" = "--help" ]; then
  usage
fi

load_deployment "$NAME" || exit 1

REMOTE_HOST="${OPENRESTY_HOST}"
REMOTE_CONF_NAME="${HOSTNAME}.conf"
REMOTE_DIR="/usr/local/openresty/nginx/conf/others"
REMOTE_PATH="${REMOTE_DIR}/${REMOTE_CONF_NAME}"
ENV_FILE="$DIR/deployments/${NAME}.env"

echo "=== unexpose: ${NAME} from ${REMOTE_HOST} ==="

# shellcheck disable=SC2029
ssh "$REMOTE_HOST" bash -s <<EOF
set -eu
REMOTE_PATH="$REMOTE_PATH"

if [ ! -f "\$REMOTE_PATH" ]; then
  echo "No conf at \$REMOTE_PATH (already absent)"
else
  sudo rm -f "\$REMOTE_PATH"
  echo "Removed \$REMOTE_PATH"
fi

if ! sudo /usr/local/openresty/bin/openresty -t 2>&1; then
  echo "ERROR: nginx -t failed after removal — manual intervention required" >&2
  exit 1
fi

sudo /usr/local/openresty/bin/openresty -s reload
echo "Reloaded OpenResty"
EOF

# Flip local status to decommissioned
if [ -f "$ENV_FILE" ]; then
  if grep -q '^DEPLOY_STATUS=' "$ENV_FILE"; then
    # portable in-place edit
    tmp=$(mktemp)
    sed 's/^DEPLOY_STATUS=.*/DEPLOY_STATUS=decommissioned/' "$ENV_FILE" >"$tmp"
    mv "$tmp" "$ENV_FILE"
  else
    echo "DEPLOY_STATUS=decommissioned" >>"$ENV_FILE"
  fi
  echo "Set DEPLOY_STATUS=decommissioned in $ENV_FILE"
fi

echo "=== unexpose complete ==="
