#!/usr/bin/env bash
# Upsert a Cloudflare A record for a deployment via API.
# Resolves CF_TOKEN_REF with `op read`. Supports --dry-run.
# Do NOT invoke against the live API unless the user explicitly asks.
set -eu

DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../lib_deploy.sh
. "$DIR/lib_deploy.sh"

usage() {
  echo "Usage: $0 <deployment-name> [--dry-run]" >&2
  echo "  op read CF_TOKEN_REF → resolve zone_id → upsert A record (ORIGIN_IP, CF_PROXIED)." >&2
  exit 1
}

NAME="${1:-}"
DRY_RUN=false
if [ -z "$NAME" ]; then
  usage
fi
shift || true
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    -h|--help) usage ;;
    *) usage ;;
  esac
done

load_deployment "$NAME" || exit 1
validate_deployment || exit 1

if [ -z "${CF_TOKEN_REF:-}" ] || [ "${CF_TOKEN_REF}" = "op://__FILL_ME__/__FILL_ME__/credential" ]; then
  echo "Error: CF_TOKEN_REF is unset or still __FILL_ME__ — refuse to call Cloudflare API" >&2
  exit 1
fi

if ! command -v op >/dev/null 2>&1; then
  echo "Error: 1Password CLI (op) not installed. brew install 1password-cli" >&2
  exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "Error: curl required" >&2
  exit 1
fi

# Prefer jq if present; fall back to python3 for JSON
json_get() {
  local expr=$1
  if command -v jq >/dev/null 2>&1; then
    jq -r "$expr"
  else
    python3 -c "import sys,json; d=json.load(sys.stdin); print($expr)" 2>/dev/null || {
      echo "Error: need jq or python3 for JSON parsing" >&2
      return 1
    }
  fi
}

echo "Reading Cloudflare token from 1Password: $CF_TOKEN_REF"
CF_TOKEN=$(op read "$CF_TOKEN_REF")
if [ -z "${CF_TOKEN:-}" ]; then
  echo "Error: op read returned empty token" >&2
  exit 1
fi

API="https://api.cloudflare.com/client/v4"
AUTH_HDR=(-H "Authorization: Bearer ${CF_TOKEN}" -H "Content-Type: application/json")

# Resolve zone_id
echo "Resolving zone_id for ${CF_ZONE}..."
ZONE_RESP=$(curl -fsS "${AUTH_HDR[@]}" \
  "${API}/zones?name=${CF_ZONE}&status=active")
if command -v jq >/dev/null 2>&1; then
  ZONE_ID=$(echo "$ZONE_RESP" | jq -r '.result[0].id // empty')
  SUCCESS=$(echo "$ZONE_RESP" | jq -r '.success')
else
  ZONE_ID=$(echo "$ZONE_RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['result'][0]['id'] if d.get('result') else '')")
  SUCCESS=$(echo "$ZONE_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('success'))")
fi

if [ "$SUCCESS" != "True" ] && [ "$SUCCESS" != "true" ]; then
  echo "Error: Cloudflare zone lookup failed: $ZONE_RESP" >&2
  exit 1
fi
if [ -z "$ZONE_ID" ]; then
  echo "Error: no zone found for ${CF_ZONE}" >&2
  exit 1
fi

PROXIED_JSON=false
if [ "${CF_PROXIED}" = "true" ] || [ "${CF_PROXIED}" = "1" ]; then
  PROXIED_JSON=true
fi

# Lookup existing A record
REC_RESP=$(curl -fsS "${AUTH_HDR[@]}" \
  "${API}/zones/${ZONE_ID}/dns_records?type=A&name=${HOSTNAME}")
if command -v jq >/dev/null 2>&1; then
  REC_ID=$(echo "$REC_RESP" | jq -r '.result[0].id // empty')
  CUR_IP=$(echo "$REC_RESP" | jq -r '.result[0].content // empty')
  CUR_PROXIED=$(echo "$REC_RESP" | jq -r '.result[0].proxied // empty')
else
  REC_ID=$(echo "$REC_RESP" | python3 -c "import sys,json; r=json.load(sys.stdin).get('result') or []; print(r[0]['id'] if r else '')")
  CUR_IP=$(echo "$REC_RESP" | python3 -c "import sys,json; r=json.load(sys.stdin).get('result') or []; print(r[0]['content'] if r else '')")
  CUR_PROXIED=$(echo "$REC_RESP" | python3 -c "import sys,json; r=json.load(sys.stdin).get('result') or []; print(r[0]['proxied'] if r else '')")
fi

PAYLOAD=$(printf '{"type":"A","name":"%s","content":"%s","proxied":%s,"ttl":1}' \
  "$HOSTNAME" "$ORIGIN_IP" "$PROXIED_JSON")

if [ -n "$REC_ID" ] && [ "$CUR_IP" = "$ORIGIN_IP" ]; then
  # Normalize proxied comparison
  want_proxied="$PROXIED_JSON"
  have_proxied="$CUR_PROXIED"
  if [ "$have_proxied" = "True" ]; then have_proxied=true; fi
  if [ "$have_proxied" = "False" ]; then have_proxied=false; fi
  if [ "$have_proxied" = "$want_proxied" ]; then
    echo "No-op: ${HOSTNAME} already A ${ORIGIN_IP} proxied=${PROXIED_JSON}"
    exit 0
  fi
fi

if [ "$DRY_RUN" = true ]; then
  if [ -n "$REC_ID" ]; then
    echo "[dry-run] Would UPDATE record ${REC_ID}: A ${HOSTNAME} → ${ORIGIN_IP} proxied=${PROXIED_JSON}"
    echo "[dry-run] current: A ${CUR_IP} proxied=${CUR_PROXIED}"
  else
    echo "[dry-run] Would CREATE A ${HOSTNAME} → ${ORIGIN_IP} proxied=${PROXIED_JSON} in zone ${CF_ZONE} (${ZONE_ID})"
  fi
  echo "[dry-run] payload: $PAYLOAD"
  exit 0
fi

if [ -n "$REC_ID" ]; then
  echo "Updating DNS record ${REC_ID}..."
  RESP=$(curl -fsS -X PUT "${AUTH_HDR[@]}" \
    --data "$PAYLOAD" \
    "${API}/zones/${ZONE_ID}/dns_records/${REC_ID}")
else
  echo "Creating DNS record..."
  RESP=$(curl -fsS -X POST "${AUTH_HDR[@]}" \
    --data "$PAYLOAD" \
    "${API}/zones/${ZONE_ID}/dns_records")
fi

if command -v jq >/dev/null 2>&1; then
  OK=$(echo "$RESP" | jq -r '.success')
else
  OK=$(echo "$RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('success'))")
fi
if [ "$OK" != "True" ] && [ "$OK" != "true" ]; then
  echo "Error: DNS upsert failed: $RESP" >&2
  exit 1
fi

echo "DNS upserted: A ${HOSTNAME} → ${ORIGIN_IP} proxied=${PROXIED_JSON}"
