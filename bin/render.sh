#!/usr/bin/env bash
# Render a deployment .env + nginx/site.conf.tmpl → deployments/<name>.conf
# Usage: bin/render.sh <name> [--stdout]
set -eu

DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../lib_deploy.sh
. "$DIR/lib_deploy.sh"

usage() {
  echo "Usage: $0 <deployment-name> [--stdout]" >&2
  exit 1
}

NAME="${1:-}"
STDOUT=false
if [ -z "$NAME" ]; then
  usage
fi
shift || true
for arg in "$@"; do
  case "$arg" in
    --stdout) STDOUT=true ;;
    -h|--help) usage ;;
    *) usage ;;
  esac
done

load_deployment "$NAME" || exit 1
validate_deployment || exit 1

# Active records must not still have placeholders that would produce a broken conf
if [ "${DEPLOY_STATUS}" = "active" ]; then
  if [ "${ALLOW_CIDRS}" = "__FILL_ME__" ] || [ -z "${ALLOW_CIDRS}" ]; then
    echo "Error: cannot render active deployment with empty/__FILL_ME__ ALLOW_CIDRS" >&2
    exit 1
  fi
fi

TMPL="$DIR/nginx/site.conf.tmpl"
if [ ! -f "$TMPL" ]; then
  echo "Error: template not found: $TMPL" >&2
  exit 1
fi

# Safe upstream name: alnum + underscore only
UPSTREAM_NAME="mt_${DEPLOY_NAME//[^a-zA-Z0-9_]/_}"

# Build REAL_IP_BLOCK via cf-ranges.sh
REAL_IP_BLOCK=""
if [ -x "$DIR/bin/cf-ranges.sh" ] || [ -f "$DIR/bin/cf-ranges.sh" ]; then
  if ! REAL_IP_BLOCK=$("$DIR/bin/cf-ranges.sh" 2>/dev/null); then
    # Offline fallback: use cache if present, else a comment so render still works for dry review
    if [ -s "$DIR/tmp/cf-ips-v4.txt" ]; then
      REAL_IP_BLOCK=$("$DIR/bin/cf-ranges.sh" --cache-only)
    else
      echo "Error: cf-ranges.sh failed and no cache available. Run bin/cf-ranges.sh once online." >&2
      exit 1
    fi
  fi
else
  echo "Error: bin/cf-ranges.sh missing" >&2
  exit 1
fi

# Build ALLOW_BLOCK from space-separated CIDRs (skip __FILL_ME__ / empty for pending)
ALLOW_BLOCK=""
if [ -n "${ALLOW_CIDRS:-}" ] && [ "${ALLOW_CIDRS}" != "__FILL_ME__" ]; then
  for cidr in $ALLOW_CIDRS; do
    ALLOW_BLOCK="${ALLOW_BLOCK}    allow ${cidr};
"
  done
fi

# OAuth2 blocks — omitted entirely when AUTH_MODE=none
OAUTH2_BLOCK=""
AUTH_REQUEST_BLOCK=""
if [ "${AUTH_MODE}" = "oauth2" ]; then
  OAUTH2_BLOCK=$(cat <<'OAUTH'
    # oauth2-proxy (listens 127.0.0.1:4180 on the OpenResty box)
    # Pattern from others/leanflag-openwebui.conf
    location /oauth2/ {
        proxy_pass       http://127.0.0.1:4180;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Auth-Request-Redirect $request_uri;
    }

    location = /oauth2/auth {
        proxy_pass       http://127.0.0.1:4180;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Content-Length "";
        proxy_pass_request_body off;
    }
OAUTH
)
  AUTH_REQUEST_BLOCK=$(cat <<'AUTH'
        auth_request /oauth2/auth;
        error_page 401 = /oauth2/sign_in;

        auth_request_set $auth_user $upstream_http_x_auth_request_user;
        auth_request_set $auth_email $upstream_http_x_auth_request_email;
        proxy_set_header X-User  $auth_user;
        proxy_set_header X-Email $auth_email;
AUTH
)
fi

# Escape replacement values for sed (use | delimiter; escape \ & |)
_sed_escape() {
  printf '%s' "$1" | sed -e 's/[\\|&]/\\&/g'
}

OUT_CONTENT=$(cat "$TMPL")
# Order matters: replace longer / multi-line tokens carefully via envsubst-like manual pass
# We use a temp file and awk/python-free pure bash with sed per token.

replace_token() {
  local token=$1 value=$2
  local tmp
  tmp=$(mktemp)
  # Write value to a file to preserve newlines safely
  printf '%s' "$value" >"$tmp.value"
  # Use awk for multi-line safe replacement
  TOKEN="$token" VALUE_FILE="$tmp.value" awk '
    BEGIN {
      token = ENVIRON["TOKEN"]
      vf = ENVIRON["VALUE_FILE"]
      while ((getline line < vf) > 0) {
        if (n++) val = val ORS line
        else val = line
      }
      close(vf)
    }
    {
      while (match($0, token)) {
        $0 = substr($0, 1, RSTART-1) val substr($0, RSTART+RLENGTH)
      }
      print
    }
  ' <<<"$OUT_CONTENT" >"$tmp"
  OUT_CONTENT=$(cat "$tmp")
  rm -f "$tmp" "$tmp.value"
}

replace_token "{{DEPLOY_NAME}}" "$DEPLOY_NAME"
replace_token "{{HOSTNAME}}" "$HOSTNAME"
replace_token "{{DEPLOY_STATUS}}" "$DEPLOY_STATUS"
replace_token "{{UPSTREAM_NAME}}" "$UPSTREAM_NAME"
replace_token "{{UPSTREAM_HOST}}" "$UPSTREAM_HOST"
replace_token "{{UPSTREAM_PORT}}" "$UPSTREAM_PORT"
replace_token "{{SSL_CERT}}" "$SSL_CERT"
replace_token "{{REAL_IP_BLOCK}}" "$REAL_IP_BLOCK"
replace_token "{{ALLOW_BLOCK}}" "$ALLOW_BLOCK"
replace_token "{{OAUTH2_BLOCK}}" "$OAUTH2_BLOCK"
replace_token "{{AUTH_REQUEST_BLOCK}}" "$AUTH_REQUEST_BLOCK"

if [ "$STDOUT" = true ]; then
  printf '%s\n' "$OUT_CONTENT"
else
  OUT_FILE="$DIR/deployments/${NAME}.conf"
  printf '%s\n' "$OUT_CONTENT" >"$OUT_FILE"
  echo "Wrote $OUT_FILE" >&2
fi
