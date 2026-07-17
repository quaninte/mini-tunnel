#!/usr/bin/env bash
# Upsert a Cloudflare A record for a deployment via API.
# Resolves CF_TOKEN_REF with `op read`. Supports --dry-run.
# Do NOT invoke against the live API unless the user explicitly asks.
set -eu

DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../lib_deploy.sh
. "$DIR/lib_deploy.sh"

usage() {
  echo "Usage: $0 <deployment-name> [--dry-run] [--replace-cname]" >&2
  echo "  op read CF_TOKEN_REF → resolve zone_id → upsert A record (ORIGIN_IP, CF_PROXIED)." >&2
  echo "  --replace-cname permits replacing an existing Cloudflare Tunnel CNAME with the A record." >&2
  exit 1
}

NAME="${1:-}"
DRY_RUN=false
REPLACE_CNAME=false
if [ -z "$NAME" ]; then
  usage
fi
shift || true
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    --replace-cname) REPLACE_CNAME=true ;;
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

# Lookup an existing A or CNAME record. Cloudflare Tunnel hostnames commonly
# use a CNAME, which must be removed before an A record can be created.
REC_RESP=$(curl -fsS "${AUTH_HDR[@]}" \
  "${API}/zones/${ZONE_ID}/dns_records?name=${HOSTNAME}")
if command -v jq >/dev/null 2>&1; then
  REC_LINE=$(echo "$REC_RESP" | jq -r '.result[]? | select(.type == "A" or .type == "CNAME") | [.id, .type, .content, (.proxied // false)] | @tsv' | head -1)
else
  REC_LINE=$(echo "$REC_RESP" | python3 -c 'import sys,json
r=json.load(sys.stdin).get("result") or []
for x in r:
    if x.get("type") in ("A", "CNAME"):
        print("\t".join(str(x.get(k, "")) for k in ("id", "type", "content", "proxied")))
        break')
fi

REC_ID=""
REC_TYPE=""
CUR_IP=""
CUR_PROXIED=""
if [ -n "$REC_LINE" ]; then
  IFS=$'\t' read -r REC_ID REC_TYPE CUR_IP CUR_PROXIED <<<"$REC_LINE"
fi

PAYLOAD=$(printf '{"type":"A","name":"%s","content":"%s","proxied":%s,"ttl":1}' \
  "$HOSTNAME" "$ORIGIN_IP" "$PROXIED_JSON")

if [ -n "$REC_ID" ] && [ "$REC_TYPE" = "A" ] && [ "$CUR_IP" = "$ORIGIN_IP" ]; then
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
    if [ "$REC_TYPE" = "CNAME" ]; then
      echo "[dry-run] Would DELETE record ${REC_ID}: CNAME ${HOSTNAME} → ${CUR_IP}"
      echo "[dry-run] Would CREATE A ${HOSTNAME} → ${ORIGIN_IP} proxied=${PROXIED_JSON}"
    else
      echo "[dry-run] Would UPDATE record ${REC_ID}: A ${HOSTNAME} → ${ORIGIN_IP} proxied=${PROXIED_JSON}"
      echo "[dry-run] current: A ${CUR_IP} proxied=${CUR_PROXIED}"
    fi
  else
    echo "[dry-run] Would CREATE A ${HOSTNAME} → ${ORIGIN_IP} proxied=${PROXIED_JSON} in zone ${CF_ZONE} (${ZONE_ID})"
  fi
  echo "[dry-run] payload: $PAYLOAD"
  exit 0
fi

if [ -n "$REC_ID" ]; then
  if [ "$REC_TYPE" = "CNAME" ]; then
    if [ "$REPLACE_CNAME" != true ]; then
      echo "Error: ${HOSTNAME} has a CNAME record; rerun with --replace-cname to replace it with A" >&2
      exit 1
    fi
    echo "Deleting legacy CNAME record ${REC_ID}..."
    DELETE_RESP=$(curl -fsS -X DELETE "${AUTH_HDR[@]}" \
      "${API}/zones/${ZONE_ID}/dns_records/${REC_ID}")
    if command -v jq >/dev/null 2>&1; then
      DELETE_OK=$(echo "$DELETE_RESP" | jq -r '.success')
    else
      DELETE_OK=$(echo "$DELETE_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('success'))")
    fi
    if [ "$DELETE_OK" != "True" ] && [ "$DELETE_OK" != "true" ]; then
      echo "Error: legacy CNAME deletion failed: $DELETE_RESP" >&2
      exit 1
    fi
    echo "Creating replacement A record..."
    RESP=$(curl -fsS -X POST "${AUTH_HDR[@]}" \
      --data "$PAYLOAD" \
      "${API}/zones/${ZONE_ID}/dns_records")
  else
    echo "Updating DNS record ${REC_ID}..."
    RESP=$(curl -fsS -X PUT "${AUTH_HDR[@]}" \
      --data "$PAYLOAD" \
      "${API}/zones/${ZONE_ID}/dns_records/${REC_ID}")
  fi
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
