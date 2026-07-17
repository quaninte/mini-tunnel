#!/usr/bin/env bash
# Deployment registry helpers. Source from bin/* scripts.
# Expects DIR to be the mini-tunnel repo root (set by the caller).

DEPLOYMENTS_DIR="${DIR:-.}/deployments"

# Load a deployment record by name. Sources KEY=VALUE into the current shell.
# Usage: load_deployment <name>
load_deployment() {
  local name=$1
  local file="$DEPLOYMENTS_DIR/${name}.env"

  if [ -z "${name:-}" ]; then
    echo "Error: load_deployment requires a deployment name" >&2
    return 1
  fi
  if [ ! -f "$file" ]; then
    echo "Error: deployment record not found: $file" >&2
    return 1
  fi

  # shellcheck disable=SC1090
  set -a
  # shellcheck source=/dev/null
  . "$file"
  set +a

  DEPLOY_NAME="${DEPLOY_NAME:-$name}"
  return 0
}

# List deployment names (filename stems of *.env under deployments/).
# Skips example if you pass --real; otherwise lists all.
list_deployments() {
  local f name
  if [ ! -d "$DEPLOYMENTS_DIR" ]; then
    return 0
  fi
  for f in "$DEPLOYMENTS_DIR"/*.env; do
    [ -f "$f" ] || continue
    name=$(basename "$f" .env)
    if [ "${1:-}" = "--real" ] && [ "$name" = "example" ]; then
      continue
    fi
    echo "$name"
  done
}

# Validate a loaded (or named) deployment.
# ALLOW_CIDRS is optional: empty/omitted means no IP allowlist (rely on AUTH_MODE).
# Usage: validate_deployment [name]
# If name is given, load_deployment is called first.
validate_deployment() {
  if [ -n "${1:-}" ]; then
    load_deployment "$1" || return 1
  fi

  local missing=0
  local req
  for req in DEPLOY_NAME DEPLOY_STATUS HOSTNAME CF_ZONE ORIGIN_IP UPSTREAM_HOST UPSTREAM_PORT OPENRESTY_HOST SSL_CERT AUTH_MODE; do
    if [ -z "${!req:-}" ]; then
      echo "Error: $req is required but empty" >&2
      missing=1
    fi
  done

  case "${DEPLOY_STATUS:-}" in
    active|pending|decommissioned) ;;
    *)
      echo "Error: DEPLOY_STATUS must be active|pending|decommissioned (got: ${DEPLOY_STATUS:-})" >&2
      missing=1
      ;;
  esac

  case "${AUTH_MODE:-}" in
    oauth2|none) ;;
    *)
      echo "Error: AUTH_MODE must be oauth2|none (got: ${AUTH_MODE:-})" >&2
      missing=1
      ;;
  esac

  # ALLOW_CIDRS is optional (empty = no IP gate). Reject placeholder on active.
  if [ "${DEPLOY_STATUS:-}" = "active" ]; then
    if [ "${ALLOW_CIDRS:-}" = "__FILL_ME__" ]; then
      echo "Error: DEPLOY_STATUS=active rejects ALLOW_CIDRS=__FILL_ME__ (omit or set real CIDRs)." >&2
      missing=1
    fi
    if [ "${UPSTREAM_HOST:-}" = "__FILL_ME__" ] || [ -z "${UPSTREAM_HOST:-}" ]; then
      echo "Error: DEPLOY_STATUS=active requires a real UPSTREAM_HOST (not __FILL_ME__)" >&2
      missing=1
    fi
    # Empty ALLOW_CIDRS + AUTH_MODE=none leaves the host open; require an explicit decision.
    if [ -z "${ALLOW_CIDRS:-}" ] && [ "${AUTH_MODE:-}" = "none" ]; then
      echo "Error: DEPLOY_STATUS=active with empty ALLOW_CIDRS requires AUTH_MODE=oauth2 (or set ALLOW_CIDRS)." >&2
      missing=1
    fi
  fi

  if [ "$missing" -ne 0 ]; then
    return 1
  fi
  return 0
}
