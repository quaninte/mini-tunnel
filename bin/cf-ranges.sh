#!/usr/bin/env bash
# Fetch public Cloudflare IP ranges and emit set_real_ip_from lines for nginx.
# Network: only https://www.cloudflare.com/ips-v4 and ips-v6 (public, unauthenticated).
set -eu

DIR="$(cd "$(dirname "$0")/.." && pwd)"
CACHE_DIR="${DIR}/tmp"
CACHE_V4="${CACHE_DIR}/cf-ips-v4.txt"
CACHE_V6="${CACHE_DIR}/cf-ips-v6.txt"
MAX_AGE_SECONDS=86400

usage() {
  echo "Usage: $0 [--cache-only] [--refresh]" >&2
  echo "  Prints set_real_ip_from <cidr>; lines for all Cloudflare edge ranges." >&2
  exit 1
}

CACHE_ONLY=false
REFRESH=false
for arg in "$@"; do
  case "$arg" in
    --cache-only) CACHE_ONLY=true ;;
    --refresh) REFRESH=true ;;
    -h|--help) usage ;;
    *) usage ;;
  esac
done

mkdir -p "$CACHE_DIR"

fetch_ranges() {
  local url=$1 dest=$2
  if ! curl -fsSL --max-time 30 "$url" -o "$dest.tmp"; then
    rm -f "$dest.tmp"
    return 1
  fi
  # Keep only non-empty CIDR-looking lines
  grep -E '^[0-9a-fA-F.:/]+$' "$dest.tmp" >"$dest" || true
  rm -f "$dest.tmp"
  [ -s "$dest" ]
}

cache_fresh() {
  local f=$1
  [ -f "$f" ] || return 1
  local now mtime age
  now=$(date +%s)
  if stat -f %m "$f" >/dev/null 2>&1; then
    mtime=$(stat -f %m "$f")
  else
    mtime=$(stat -c %Y "$f" 2>/dev/null || echo 0)
  fi
  age=$((now - mtime))
  [ "$age" -lt "$MAX_AGE_SECONDS" ]
}

ensure_cache() {
  local need_fetch=false
  if [ "$REFRESH" = true ]; then
    need_fetch=true
  elif ! cache_fresh "$CACHE_V4" || ! cache_fresh "$CACHE_V6"; then
    need_fetch=true
  fi

  if [ "$need_fetch" = true ]; then
    if [ "$CACHE_ONLY" = true ]; then
      echo "Error: cache missing/stale and --cache-only set" >&2
      return 1
    fi
    fetch_ranges "https://www.cloudflare.com/ips-v4" "$CACHE_V4" || {
      echo "Error: failed to fetch Cloudflare IPv4 ranges" >&2
      return 1
    }
    fetch_ranges "https://www.cloudflare.com/ips-v6" "$CACHE_V6" || {
      echo "Error: failed to fetch Cloudflare IPv6 ranges" >&2
      return 1
    }
  fi

  if [ ! -s "$CACHE_V4" ] || [ ! -s "$CACHE_V6" ]; then
    echo "Error: Cloudflare IP range cache empty" >&2
    return 1
  fi
}

ensure_cache

while IFS= read -r cidr; do
  [ -n "$cidr" ] || continue
  echo "    set_real_ip_from $cidr;"
done <"$CACHE_V4"

while IFS= read -r cidr; do
  [ -n "$cidr" ] || continue
  echo "    set_real_ip_from $cidr;"
done <"$CACHE_V6"
