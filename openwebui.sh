#!/usr/bin/env bash
# OpenWebUI stack: a single Docker Compose service (see compose.yml).
# Sourced by start.sh/stop.sh/status.sh — expects lib.sh already sourced and
# DIR/OPENWEBUI_PORT/FORCE already set by the caller.

_OPENWEBUI_CONTAINER="mini-tunnel-open-webui"

_openwebui_require_docker() {
  if ! docker_compose_available; then
    echo "Error: Docker (with the 'compose' plugin) is required for OpenWebUI but was not found."
    echo "  Install Docker Desktop (macOS) or Docker Engine + docker-compose-plugin (Linux), or set ENABLE_OPENWEBUI=false."
    exit 1
  fi
}

start_openwebui() {
  _openwebui_require_docker

  if is_port_in_use "$OPENWEBUI_PORT" && ! is_container_running "$_OPENWEBUI_CONTAINER"; then
    local owner_pid
    owner_pid=$(get_port_owner_pid "$OPENWEBUI_PORT")
    if [ "${FORCE:-false}" = true ]; then
      echo "Port $OPENWEBUI_PORT is in use (PID ${owner_pid:-unknown}) by something other than OpenWebUI. Forcing..."
      if [ -n "${owner_pid:-}" ]; then
        kill_and_wait "$owner_pid" 5 3
      fi
      wait_for_port_free "$OPENWEBUI_PORT" 10 || {
        echo "Error: port $OPENWEBUI_PORT is still occupied. Cannot start OpenWebUI."
        exit 1
      }
    else
      echo "Error: port $OPENWEBUI_PORT is already in use by another process (PID ${owner_pid:-unknown})."
      echo "  Run '$DIR/restart.sh' to stop, clean up, and restart everything,"
      echo "  or '$DIR/start.sh --force' to kill the occupant and restart."
      exit 1
    fi
  fi

  echo "Starting OpenWebUI..."
  (cd "$DIR" && docker compose up -d)
  wait_for_port "$OPENWEBUI_PORT" "openwebui" 30

  echo "  openwebui:    http://127.0.0.1:$OPENWEBUI_PORT"
  if [ -z "${OPENWEBUI_HOSTNAME:-}" ]; then
    echo "  Warning: OPENWEBUI_HOSTNAME is not set — OpenWebUI has no public hostname configured"
    echo "           and won't be reachable through the tunnel until you add a Public Hostname"
    echo "           rule for it in the Cloudflare Zero Trust dashboard (see README)."
  fi
}

stop_openwebui() {
  _openwebui_require_docker
  echo "Stopping OpenWebUI..."
  (cd "$DIR" && docker compose down)
}

status_openwebui() {
  local status="not started"
  if docker_compose_available && is_container_running "$_OPENWEBUI_CONTAINER"; then
    status="running"
  fi
  if is_port_in_use "$OPENWEBUI_PORT"; then
    status="$status, port $OPENWEBUI_PORT occupied"
  else
    status="$status, port $OPENWEBUI_PORT free"
  fi
  echo "openwebui: $status"
}
